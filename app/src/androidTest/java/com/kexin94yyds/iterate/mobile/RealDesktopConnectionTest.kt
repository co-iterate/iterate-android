package com.kexin94yyds.iterate.mobile

import android.content.Context
import android.content.Intent
import androidx.core.content.ContextCompat
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import com.kexin94yyds.iterate.MainActivity
import kotlinx.coroutines.runBlocking
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import java.io.File

/** Opt-in only: the owner must issue a fresh pairing offer through the normal desktop UI. */
class RealDesktopConnectionTest {
  @Test fun pairThroughTheOwnersFreshOffer() {
    val instrumentation = InstrumentationRegistry.getInstrumentation()
    val app = instrumentation.targetContext
    val offerFile = File(app.getExternalFilesDir(null), "owner-pairing-offer.txt")
    assumeTrue("requires an owner-issued offer; no credentials are created or bypassed by this test", offerFile.isFile)
    val resultFile = File(app.getExternalFilesDir(null), "real-desktop-pairing-result.json")
    resultFile.delete()
    val raw = offerFile.readText()
    offerFile.delete()
    // Exercise production HTTPS/WSS rules even though the installed APK is a debug build.
    val offer = PairingParser.parse(raw, allowDebugLoopback = false)
    ActivityScenario.launch(MainActivity::class.java).use { scenario ->
      val connection = runBlocking {
        PairingRepository().claim(offer, DeviceCredentialStore(app).deviceId, "Android acceptance emulator")
      }
      val manager = ConnectionManager.get(app)
      scenario.onActivity { manager.install(connection) }
      val deadline = System.currentTimeMillis() + 30_000
      while (manager.state.value.state != BridgeConnectionState.Connected && System.currentTimeMillis() < deadline) Thread.sleep(100)
      assertEquals("authenticated desktop WebSocket connects", BridgeConnectionState.Connected, manager.state.value.state)
      val version = runBlocking { manager.client!!.checkVersion() }
      assertTrue(JSONObject(version).optString("version").isNotBlank())
      scenario.onActivity {
        app.getSharedPreferences("mobile_preferences", Context.MODE_PRIVATE).edit().putBoolean("continuous", true).commit()
        ContextCompat.startForegroundService(it, Intent(it, ConnectionService::class.java))
      }
      // Deliberately omit bearer, grant and response content from the result artifact.
      resultFile.writeText(
        JSONObject().put("paired", true).put("websocket", "authenticated_connected")
          .put("https", true).put("device_id", connection.deviceId).toString()
      )
    }
  }
}
