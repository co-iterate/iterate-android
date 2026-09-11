package com.kexin94yyds.iterate.mobile

import android.content.Context
import android.content.Intent
import android.app.NotificationManager
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.core.content.ContextCompat
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.By
import androidx.test.uiautomator.Until
import com.kexin94yyds.iterate.MainActivity
import kotlinx.coroutines.runBlocking
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import okhttp3.Response
import okhttp3.mockwebserver.*
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.FixMethodOrder
import org.junit.runners.MethodSorters
import org.junit.runner.RunWith
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.atomic.AtomicInteger

@RunWith(AndroidJUnit4::class)
@FixMethodOrder(MethodSorters.NAME_ASCENDING)
class CompanionConnectionTest {
  private fun eventually(predicate: () -> Boolean) {
    val deadline = System.currentTimeMillis() + 15_000
    while (System.currentTimeMillis() < deadline) {
      if (predicate()) return
      Thread.sleep(100)
    }
    assertTrue("condition not satisfied before timeout", predicate())
  }
  @Test fun corruptPendingReplyRemainsProtectedAtColdStart() {
    val instrumentation = InstrumentationRegistry.getInstrumentation()
    val app = instrumentation.targetContext
    val prefs = app.getSharedPreferences("mobile_identity", Context.MODE_PRIVATE)
    prefs.edit().putString("pending_reply", "corrupt-ciphertext").commit()
    val manager = ConnectionManager.get(app)
    try {
      assertTrue(manager.state.value.pendingReply)
      assertEquals("corrupt-ciphertext", prefs.getString("pending_reply", null))
    } finally {
      instrumentation.runOnMainSync { manager.discardPendingReply() }
    }
  }
  @Test fun pairedSessionPersistsNotifiesAndConfirmsSameReplyAcrossRetry() {
    val instrumentation = InstrumentationRegistry.getInstrumentation()
    val app = instrumentation.targetContext
    instrumentation.uiAutomation.executeShellCommand("pm grant ${app.packageName} android.permission.POST_NOTIFICATIONS").close()
    val server = MockWebServer()
    val sockets = CopyOnWriteArrayList<WebSocket>()
    val actions = CopyOnWriteArrayList<JSONObject>()
    val counter = AtomicInteger()
    server.dispatcher = object : Dispatcher() {
      override fun dispatch(request: RecordedRequest): MockResponse = when (request.path) {
        "/api/mobile/pairing/claim" -> {
          val body = JSONObject(request.body.readUtf8())
          assertEquals("android", body.getString("client_kind"))
          MockResponse().setBody(JSONObject().put("ok",true).put("device_id",body.getString("device_id")).put("device_token","instrumented-private-fixture").toString())
        }
        "/ws" -> {
          assertEquals("Bearer instrumented-private-fixture",request.getHeader("Authorization"))
          MockResponse().withWebSocketUpgrade(object : WebSocketListener() {
            override fun onOpen(socket: WebSocket, response: Response) { sockets.add(socket) }
            override fun onClosing(socket: WebSocket, code: Int, reason: String) { socket.close(code,reason) }
          })
        }
        "/api/mobile/reply" -> {
          assertEquals("Bearer instrumented-private-fixture",request.getHeader("Authorization"))
          val body = JSONObject(request.body.readUtf8()); actions.add(body)
          when (counter.getAndIncrement()) {
            0 -> MockResponse().setResponseCode(503)
            1 -> MockResponse().setResponseCode(408)
            2 -> MockResponse().setResponseCode(429)
            else -> MockResponse().setBody(JSONObject().put("operation_id",body.getString("operation_id")).put("status","delivered").toString())
          }
        }
        else -> MockResponse().setResponseCode(404)
      }
    }
    server.start()
    val prefs = app.getSharedPreferences("mobile_preferences",Context.MODE_PRIVATE)
    prefs.edit().putBoolean("notifications",true).remove("notified_requests").commit()
    val manager = ConnectionManager.get(app)
    try {
      ActivityScenario.launch(MainActivity::class.java).use { scenario ->
        val base = server.url("/").toString().trimEnd('/')
        val offer = PairingOffer(base,base.replace("http://","ws://")+"/ws","fixture-grant","Fixture desktop")
        val identity = DeviceCredentialStore(app)
        val connection = runBlocking { PairingRepository().claim(offer,identity.deviceId,"Instrumented Android") }
        scenario.onActivity { manager.install(connection) }
        eventually { manager.state.value.state == BridgeConnectionState.Connected }
        assertEquals("instrumented-private-fixture",DeviceCredentialStore(app).load()!!.token)
        assertFalse(app.getSharedPreferences("mobile_identity",Context.MODE_PRIVATE).getString("credential","")!!.contains("instrumented-private-fixture"))
        scenario.onActivity {
          prefs.edit().putBoolean("continuous",true).commit()
          ContextCompat.startForegroundService(it,Intent(it,ConnectionService::class.java))
        }
        eventually { app.getSystemService(NotificationManager::class.java).activeNotifications.any { it.id == 1 } }
        scenario.onActivity { it.moveTaskToBack(true) }
        Thread.sleep(500)
        val frame = """{"message_type":"mcp_state","payload":{"request":{"id":"instrumented-request","project_path":"/fixture/android","message":"Instrumented desktop message"}}}"""
        sockets.first().send(frame)
        eventually { manager.state.value.request?.requestId == "instrumented-request" }
        eventually { app.getSystemService(NotificationManager::class.java).activeNotifications.any { it.id == "instrumented-request".hashCode() } }
        assertEquals(1,sockets.size)
        val device = UiDevice.getInstance(instrumentation)
        assertTrue(device.openNotification())
        val reminder = device.wait(Until.findObject(By.text("电脑有一条消息等待回复")), 5_000)
        assertNotNull("system reminder is visible", reminder)
        reminder.click()
        eventually { scenario.state == androidx.lifecycle.Lifecycle.State.RESUMED }
        assertTrue(device.wait(Until.hasObject(By.text("Instrumented desktop message")), 5_000))
        assertEquals(1,sockets.size)
        instrumentation.uiAutomation.takeScreenshot()?.let { bitmap ->
          java.io.File(app.getExternalFilesDir(null), "companion-message.png").outputStream().use { bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it) }
          bitmap.recycle()
        }
        instrumentation.runOnMainSync {
          assertTrue(manager.queueReply(JSONObject().put("request_id","instrumented-request").put("project_path","/fixture/android").put("action","submit").put("user_input","reply fixture")))
          assertFalse(manager.queueReply(JSONObject().put("action","submit")))
        }
        eventually { !manager.state.value.pendingReply && manager.state.value.replyStatus == "电脑已收到回复" }
        assertEquals(4,actions.size)
        assertEquals(1,actions.map { it.getString("operation_id") }.distinct().size)
        assertEquals(1,sockets.size)
        assertNull(identity.readSecret("pending_reply"))
        instrumentation.runOnMainSync { app.startService(Intent(app,ConnectionService::class.java).setAction(ConnectionService.STOP)) }
        eventually { !prefs.getBoolean("continuous",true) }
      }
    } finally {
      instrumentation.runOnMainSync { app.stopService(Intent(app,ConnectionService::class.java)); manager.forget(); manager.discardPendingReply() }
      sockets.forEach { it.close(1000, "fixture complete") }
      server.shutdown()
    }
  }
}
