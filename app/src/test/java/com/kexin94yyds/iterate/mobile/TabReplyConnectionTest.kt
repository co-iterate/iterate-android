package com.kexin94yyds.iterate.mobile

import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import java.util.concurrent.atomic.AtomicReference
import javax.net.ServerSocketFactory
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import okhttp3.OkHttpClient
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class TabReplyConnectionTest {
  @Test fun droppedReplySocketAndLateWireEventsNeverRestoreTheSentTab() = runBlocking {
    RequestOrigin.values().forEach { origin ->
      val id = when (origin) {
        RequestOrigin.Mcp -> "serve-sent"
        RequestOrigin.Native -> "native-codex:sent"
        RequestOrigin.Mirror -> "cross-mirror:" + "a".repeat(64)
      }
      val project = if (origin == RequestOrigin.Mirror) "" else "E:/fixture"
      fun wireState(closed: Boolean = false): String {
        val request = JSONObject().put("id", id).put("message", "original question")
          .put("predefined_options", JSONArray(listOf("yes")))
        val payload = JSONObject().put("request_id", id)
          .put("request", if (closed) JSONObject.NULL else request)
        if (origin == RequestOrigin.Mirror) {
          payload.put("source", "cross_device_mirror").put("mirror_id", id).put("closed", closed)
        } else {
          request.put("project_path", project)
          payload.put("project_path", project).put("showMcpPopup", !closed)
          if (origin == RequestOrigin.Native) payload.put("source", "codex_native")
        }
        return JSONObject().put("message_type", if (origin == RequestOrigin.Mirror) "cross_device_mirror_state" else "mcp_state")
          .put("payload", payload).toString()
      }
      val sent = requireNotNull(BridgeJsonParser.parseRequest(wireState()))
      val other = MobileRequest("other", "E:/other", "other", "other question", null, emptyList())
      val actionId = "original-action"
      val payload = if (origin == RequestOrigin.Mirror)
        BridgeJsonParser.buildMirrorAction("submit", id, "original reply", listOf("yes"), actionId)
      else BridgeJsonParser.buildMcpAction("submit", project, id, "original reply", listOf("yes"), actionId)
      val pending = WorkbenchUiState().receiveRequest(sent).copy(userInput = "original reply", selectedOptions = setOf("yes"))
        .beginAction(id, project, actionId, "submit", payload, "fixture-phone")
        .receiveRequest(other).selectActiveRequest(other).copy(userInput = "editing other")
      val server = MockWebServer()
      val peerSocket = AtomicReference<Socket>()
      server.serverSocketFactory = object : ServerSocketFactory() {
        override fun createServerSocket(): ServerSocket = object : ServerSocket() {
          override fun accept(): Socket = super.accept().also { peerSocket.set(it) }
        }
        override fun createServerSocket(port: Int): ServerSocket =
          ServerSocketFactory.getDefault().createServerSocket(port)
        override fun createServerSocket(port: Int, backlog: Int): ServerSocket =
          ServerSocketFactory.getDefault().createServerSocket(port, backlog)
        override fun createServerSocket(port: Int, backlog: Int, address: InetAddress): ServerSocket =
          ServerSocketFactory.getDefault().createServerSocket(port, backlog, address)
      }
      val http = OkHttpClient.Builder().build()
      val received = CompletableDeferred<String>()
      server.enqueue(MockResponse().withWebSocketUpgrade(object : WebSocketListener() {
        override fun onMessage(webSocket: WebSocket, text: String) {
          received.complete(text)
          // Drop the transport after accepting the frame, without a receipt.
          requireNotNull(peerSocket.get()).close()
        }
      }))
      server.start()
      try {
        val pairing = SavedPairing(server.url("/").toString().trimEnd('/'),
          server.url("/ws").toString().replaceFirst("http://", "ws://"),
          "fixture-phone", "dt_fixture_not_a_real_credential")
        val receipt = withTimeout(5_000) {
          BridgeClient(http).sendAction(pairing, payload, id, project, actionId, "submit", origin)
        }
        assertEquals(payload, withTimeout(1_000) { received.await() })
        assertFalse(receipt.delivered)
        assertTrue("$origin dropped socket must leave delivery unknown", receipt.deliveryUnknown)
        for (closeFirst in listOf(false, true)) {
          val closedKey = requireNotNull(BridgeJsonParser.parseClosedRequest(wireState(closed = true)))
          val beforeFailure = if (closeFirst) pending.closeRequest(closedKey.first, closedKey.second) else pending
          val unknown = beforeFailure.actionFailed(id, project, receipt)
          assertEquals(listOf(other), unknown.requests)
          assertEquals(other, unknown.request)
          assertEquals("editing other", unknown.userInput)
          assertEquals(payload, unknown.drafts[id to project]?.unconfirmedAction?.payload)
          assertEquals(actionId, unknown.drafts[id to project]?.unconfirmedAction?.clientActionId)
          assertEquals(unknown, unknown.receiveRequest(requireNotNull(BridgeJsonParser.parseRequest(wireState()))))
          val offline = unknown.clearRemoteRequests(BridgeConnectionState.Offline)
          assertEquals(offline, offline.receiveRequest(sent))

          val finalPayload = JSONObject().put("request_id", id).put("project_path", project)
            .put("client_action_id", actionId).put("action", "submit").put("delivered", true)
            .put("status", if (origin == RequestOrigin.Mirror) "accepted" else "delivered")
          if (origin == RequestOrigin.Native) finalPayload.put("source", "codex_native")
            .put("final_result", true).put("result_kind", "cli_received")
          if (origin == RequestOrigin.Mirror) finalPayload.put("source", "cross_device_mirror")
            .put("mirror_id", id).put("result_kind", "mac_accepted")
          val finalWire = JSONObject().put("message_type", if (origin == RequestOrigin.Mirror)
            "cross_device_mirror_action_result" else "mcp_action_result").put("payload", finalPayload).toString()
          val finalReceipt = requireNotNull(BridgeJsonParser.parseActionReceipt(finalWire, id, project, actionId, "submit", origin))
          assertTrue(finalReceipt.delivered)
          val delivered = unknown.deliveredRequest(id, project, finalReceipt.resultKind)
          assertEquals(listOf(other), delivered.requests)
          assertEquals(other, delivered.request)
          assertEquals("editing other", delivered.userInput)
          assertEquals(delivered, delivered.receiveRequest(sent))
          assertNull(delivered.drafts[id to project])
        }
      } finally {
        http.dispatcher.cancelAll()
        http.dispatcher.executorService.shutdownNow()
        http.connectionPool.evictAll()
        server.shutdown()
      }
    }
  }
}
