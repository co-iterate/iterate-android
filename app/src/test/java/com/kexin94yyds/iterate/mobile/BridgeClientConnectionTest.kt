package com.kexin94yyds.iterate.mobile

import kotlinx.coroutines.delay
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeout
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.flow.filterIsInstance
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.flow.take
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeoutOrNull
import okhttp3.OkHttpClient
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.util.concurrent.TimeUnit

class BridgeClientConnectionTest {
  private fun pairing(server: MockWebServer) = SavedPairing(
    server.url("/").toString().trimEnd('/'),
    server.url("/ws").toString().replaceFirst("http://", "ws://"),
    "fixture-phone", "dt_fixture_not_a_real_credential",
  )

  @Test fun serverCloseEndsReceiveFlowSoViewModelCanReconnect() = runBlocking {
    val server = MockWebServer()
    val http = OkHttpClient.Builder().pingInterval(0, TimeUnit.SECONDS).build()
    server.enqueue(MockResponse().withWebSocketUpgrade(object : WebSocketListener() {
      override fun onOpen(webSocket: WebSocket, response: Response) {
        webSocket.close(1000, "fixture remote close")
      }
      override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
        webSocket.close(1000, "fixture close acknowledged")
      }
    }))
    server.start()
    try {
      val events = withTimeoutOrNull(1_500) { BridgeClient(http).requests(pairing(server)).toList() }
      assertNotNull("remote close must end flow without waiting for a ping failure", events)
      assertTrue(events!!.any { it is BridgeEvent.Connected })
      assertTrue(events.any { it is BridgeEvent.Disconnected })
    } finally {
      http.dispatcher.cancelAll()
      http.dispatcher.executorService.shutdownNow()
      http.connectionPool.evictAll()
      server.shutdown()
    }
  }

  @Test fun rejectedHandshakeEndsFlowWithOneDisconnectedEvent() = runBlocking {
    val server = MockWebServer()
    val http = OkHttpClient.Builder().build()
    server.enqueue(MockResponse().setResponseCode(401))
    server.start()
    try {
      val bridge = BridgeClient(http)
      val events = withTimeout(1_500) { bridge.requests(pairing(server)).toList() }
      assertEquals(listOf(BridgeEvent.Disconnected("配对凭据已失效")), events)
      assertFalse(bridge.requestQuickTemplateSync("rejected"))
    } finally {
      http.dispatcher.cancelAll()
      http.dispatcher.executorService.shutdownNow()
      http.connectionPool.evictAll()
      server.shutdown()
    }
  }

  @Test fun snapshotBurstDoesNotSilentlyDropPendingRequests() = runBlocking {
    val server = MockWebServer()
    val http = OkHttpClient.Builder().pingInterval(0, TimeUnit.SECONDS).build()
    server.enqueue(MockResponse().withWebSocketUpgrade(object : WebSocketListener() {
      override fun onOpen(webSocket: WebSocket, response: Response) {
        repeat(200) { index ->
          val request = JSONObject().put("id", "serve-fixture-$index")
            .put("project_path", "E:/fixture").put("message", "fixture $index")
          webSocket.send(JSONObject().put("message_type", "mcp_state")
            .put("payload", JSONObject().put("request", request)).toString())
        }
      }
      override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
        webSocket.close(1000, "fixture close acknowledged")
      }
    }))
    server.start()
    try {
      val received = mutableListOf<BridgeEvent.Request>()
      val finished = withTimeoutOrNull(3_000) {
        BridgeClient(http).requests(pairing(server)).filterIsInstance<BridgeEvent.Request>()
          .onEach { delay(5); received.add(it) }.take(200).toList()
      }
      assertNotNull("only ${received.size}/200 pending requests reached the collector", finished)
      assertEquals(200, received.map { it.request.requestId }.toSet().size)
    } finally {
      http.dispatcher.cancelAll()
      http.dispatcher.executorService.shutdownNow()
      http.connectionPool.evictAll()
      server.shutdown()
    }
  }

  @Test fun reconnectReceivesNewRequestAndUsesNewSocketForSync() = runBlocking {
    val server = MockWebServer()
    val http = OkHttpClient.Builder().pingInterval(0, TimeUnit.SECONDS).build()
    val syncReceived = CompletableDeferred<Unit>()
    server.enqueue(MockResponse().withWebSocketUpgrade(object : WebSocketListener() {
      override fun onOpen(webSocket: WebSocket, response: Response) {
        webSocket.close(1000, "reconnect fixture")
      }
    }))
    server.enqueue(MockResponse().withWebSocketUpgrade(object : WebSocketListener() {
      override fun onOpen(webSocket: WebSocket, response: Response) {
        webSocket.send("""{"message_type":"mcp_state","payload":{"request":{"id":"serve-after-reconnect","project_path":"E:/fixture","message":"new request"}}}""")
      }
      override fun onMessage(webSocket: WebSocket, text: String) {
        if (JSONObject(text).optString("message_type") == "request_timeline_sync") {
          syncReceived.complete(Unit)
          webSocket.close(1000, "fixture complete")
        }
      }
    }))
    server.start()
    try {
      val bridge = BridgeClient(http)
      val events = mutableListOf<BridgeEvent>()
      withTimeout(3_000) {
        // The ViewModel collects again when the previous receive flow ends.
        repeat(2) {
          bridge.requests(pairing(server)).collect { event ->
            events.add(event)
            if (event is BridgeEvent.Request) {
              assertEquals("serve-after-reconnect", event.request.requestId)
              assertTrue(bridge.requestTimeline(requireNotNull(event.request.requestId), "E:/fixture"))
            }
          }
        }
        syncReceived.await()
      }
      assertEquals(2, events.filterIsInstance<BridgeEvent.Connected>().size)
      assertEquals(2, events.filterIsInstance<BridgeEvent.Disconnected>().size)
      assertEquals(1, events.filterIsInstance<BridgeEvent.Request>().size)
      assertFalse(bridge.requestQuickTemplateSync("after-close"))
    } finally {
      http.dispatcher.cancelAll()
      http.dispatcher.executorService.shutdownNow()
      http.connectionPool.evictAll()
      server.shutdown()
    }
  }

  @Test fun cancellationUnblocksBackpressuredSocketReader() = runBlocking {
    val server = MockWebServer()
    val http = OkHttpClient.Builder().pingInterval(0, TimeUnit.SECONDS).build()
    val burstSent = CompletableDeferred<Unit>()
    val closeReceived = CompletableDeferred<Unit>()
    server.enqueue(MockResponse().withWebSocketUpgrade(object : WebSocketListener() {
      override fun onOpen(webSocket: WebSocket, response: Response) {
        repeat(200) {
          webSocket.send("""{"message_type":"mcp_state","payload":{"request":{"id":"serve-cancel-$it","project_path":"E:/fixture","message":"fixture"}}}""")
        }
        burstSent.complete(Unit)
      }
      override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
        closeReceived.complete(Unit)
        webSocket.close(1000, "cancel acknowledged")
      }
    }))
    server.start()
    try {
      val bridge = BridgeClient(http)
      val collector = launch {
        bridge.requests(pairing(server)).collect { awaitCancellation() }
      }
      withTimeout(3_000) {
        burstSent.await()
        delay(100)
        collector.cancelAndJoin()
        closeReceived.await()
      }
      assertFalse(bridge.requestQuickTemplateSync("after-cancel"))
    } finally {
      http.dispatcher.cancelAll()
      http.dispatcher.executorService.shutdownNow()
      http.connectionPool.evictAll()
      server.shutdown()
    }
  }
}
