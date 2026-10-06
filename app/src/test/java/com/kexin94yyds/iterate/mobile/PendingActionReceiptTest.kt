package com.kexin94yyds.iterate.mobile

import kotlinx.coroutines.async
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import kotlinx.coroutines.CompletableDeferred
import okhttp3.OkHttpClient
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class PendingActionReceiptTest {
  @Test fun processingReceiptDoesNotRestoreTabBeforeFinalDelivery() = checkSequence(true)
  @Test fun processingReceiptDoesNotHideFinalRejection() = checkSequence(false)
  @Test fun nativeProcessingWaitsForFinalDelivery() = checkSequence(true, RequestOrigin.Native)
  @Test fun nativeProcessingPreservesFinalRejection() = checkSequence(false, RequestOrigin.Native)
  @Test fun mirrorProcessingWaitsForFinalDelivery() = checkSequence(true, RequestOrigin.Mirror)
  @Test fun mirrorProcessingPreservesFinalRejection() = checkSequence(false, RequestOrigin.Mirror)

  private fun checkSequence(delivered: Boolean, origin: RequestOrigin = RequestOrigin.Mcp) = runBlocking {
    val server = MockWebServer()
    val http = OkHttpClient.Builder().build()
    val pendingSent = CompletableDeferred<WebSocket>()
    val requestId = if (origin == RequestOrigin.Mirror) "cross-mirror:" + "a".repeat(64) else "fixture-request"
    val project = if (origin == RequestOrigin.Mirror) "" else "E:/fixture"
    fun receipt(status: String, success: Boolean) = JSONObject()
      .put("message_type", if (origin == RequestOrigin.Mirror) "cross_device_mirror_action_result" else "mcp_action_result")
      .put("payload", JSONObject().put("request_id", requestId)
        .put("project_path", project).put("client_action_id", "fixture-action")
        .put("action", "submit").put("status", status).put("delivered", success)
        .put("reason", if (status == "rejected") "fixture rejection" else "").apply {
          if (origin == RequestOrigin.Native) {
            put("source", "codex_native").put("final_result", status != "pending")
              .put("result_kind", if (success) "cli_received" else status)
          } else if (origin == RequestOrigin.Mirror) {
            put("source", "cross_device_mirror").put("mirror_id", requestId)
              .put("status", if (success) "accepted" else status)
              .put("result_kind", if (success) "mac_accepted" else status)
          }
        }).toString()
    server.enqueue(MockResponse().withWebSocketUpgrade(object : WebSocketListener() {
      override fun onMessage(webSocket: WebSocket, text: String) {
        webSocket.send(receipt("pending", false))
        pendingSent.complete(webSocket)
      }
      override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
        webSocket.close(1000, "fixture complete")
      }
    }))
    server.start()
    try {
      val pairing = SavedPairing(server.url("/").toString().trimEnd('/'),
        server.url("/ws").toString().replaceFirst("http://", "ws://"),
        "fixture-phone", "dt_fixture_not_a_real_credential")
      val request = MobileRequest(requestId, project, "fixture", "question", null, emptyList(), origin = origin)
      val state = WorkbenchUiState(request = request, requests = listOf(request), userInput = "reply")
        .beginAction(requestId, project, "fixture-action", "submit", "{}")
      assertTrue(state.requests.isEmpty())
      withTimeout(3_000) {
        val sending = async { BridgeClient(http).sendAction(pairing, "{}", requestId, project, "fixture-action", "submit", origin) }
        val socket = pendingSent.await()
        delay(100)
        val completedOnPending = sending.isCompleted
        // Always send final before asserting so fixture cleanup remains bounded.
        socket.send(receipt(if (delivered) "delivered" else "rejected", delivered))
        val result = sending.await()
        assertFalse("pending is not a final result and must not trigger tab restoration", completedOnPending)
        assertEquals(delivered, result.delivered)
        if (delivered) {
          assertTrue(state.deliveredRequest(requestId, project).requests.isEmpty())
        } else {
          assertEquals(if (origin == RequestOrigin.Native) "原回复未执行" else "fixture rejection", result.error)
          assertFalse(result.deliveryUnknown)
        }
      }
    } finally {
      http.dispatcher.cancelAll()
      http.dispatcher.executorService.shutdownNow()
      http.connectionPool.evictAll()
      server.shutdown()
    }
  }
}
