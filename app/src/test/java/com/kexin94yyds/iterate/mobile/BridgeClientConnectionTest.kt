package com.kexin94yyds.iterate.mobile

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import okhttp3.OkHttpClient
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.util.concurrent.TimeUnit

class BridgeClientConnectionTest {
  private lateinit var server: MockWebServer
  private lateinit var http: OkHttpClient

  @Before fun setUp() {
    server = MockWebServer().apply { start() }
    http = OkHttpClient.Builder().connectTimeout(1, TimeUnit.SECONDS).readTimeout(0, TimeUnit.SECONDS).build()
  }

  @After fun tearDown() {
    http.dispatcher.executorService.shutdownNow()
    http.connectionPool.evictAll()
    server.shutdown()
  }

  private fun client(retry: (Int) -> Long = { 20L }) = BridgeClient(
    baseUrl = server.url("/").toString().trimEnd('/'),
    wsUrl = server.url("/ws").toString(),
    client = http,
    retryDelayMillis = retry,
  )

  private class Peer : WebSocketListener() {
    val opened = CompletableDeferred<WebSocket>()
    val ended = CompletableDeferred<Unit>()
    val messages = Channel<String>(Channel.UNLIMITED)
    override fun onOpen(webSocket: WebSocket, response: Response) { opened.complete(webSocket) }
    override fun onMessage(webSocket: WebSocket, text: String) { messages.trySend(text) }
    override fun onClosed(webSocket: WebSocket, code: Int, reason: String) { ended.complete(Unit) }
    override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) { ended.complete(Unit) }
  }

  private fun enqueuePeer(): Peer = Peer().also {
    server.enqueue(MockResponse().withWebSocketUpgrade(it))
  }

  private suspend fun Channel<BridgeEvent>.state(expected: BridgeConnectionState) {
    withTimeout(5_000) {
      while (true) {
        val event = receive()
        if (event is BridgeEvent.Connection && event.state == expected) return@withTimeout
      }
    }
  }

  private suspend fun observe(client: BridgeClient = client(), block: suspend (Channel<BridgeEvent>) -> Unit) = coroutineScope {
    val events = Channel<BridgeEvent>(Channel.UNLIMITED)
    val job = launch { try { client.events().collect { events.send(it) } } finally { events.close() } }
    try { block(events) } finally { job.cancelAndJoin() }
  }

  @Test fun socketHandshakeConnectsWithoutARequestOrVersionProbe() = runBlocking {
    val peer = enqueuePeer()
    observe { events ->
      events.state(BridgeConnectionState.Connected)
      val handshake = server.takeRequest(1, TimeUnit.SECONDS)!!
      assertEquals("/ws", handshake.path)
      assertEquals("android", handshake.getHeader("X-Iterate-Client-Kind"))
      assertTrue(withTimeout(5_000) { peer.messages.receive() }.contains("client_hello"))
      assertTrue(withTimeout(5_000) { peer.messages.receive() }.contains("request_sync"))
      peer.opened.await().send("""{"message_type":"mcp_state","payload":{"request":{"request_id":"request-1","message":"hello"}}}""")
      val received = withTimeout(5_000) { events.receive() } as BridgeEvent.RequestReceived
      assertEquals("request-1", received.request.requestId)
      assertEquals(1, server.requestCount)
    }
  }

  @Test fun serverCloseLeavesOnlineThenReconnectsAndRequestsSync() = runBlocking {
    val first = enqueuePeer()
    val second = enqueuePeer()
    observe { events ->
      events.state(BridgeConnectionState.Connected)
      first.opened.await().close(1012, "restart")
      events.state(BridgeConnectionState.Offline)
      events.state(BridgeConnectionState.Retrying)
      events.state(BridgeConnectionState.Connected)
      withTimeout(5_000) { first.ended.await() }
      assertTrue(withTimeout(5_000) { second.messages.receive() }.contains("client_hello"))
      assertTrue(withTimeout(5_000) { second.messages.receive() }.contains("request_sync"))
      assertEquals(2, server.requestCount)
    }
  }

  @Test fun temporarilyUnavailableHandshakeRetries() = runBlocking {
    server.enqueue(MockResponse().setResponseCode(503))
    enqueuePeer()
    observe { events ->
      events.state(BridgeConnectionState.Retrying)
      events.state(BridgeConnectionState.Connected)
      assertEquals(2, server.requestCount)
    }
  }

  @Test fun abruptTransportLossReconnects() = runBlocking {
    enqueuePeer()
    val port = server.port
    observe { events ->
      events.state(BridgeConnectionState.Connected)
      // Server-side MockWebServer WebSockets have no outbound Call to cancel.
      // Closing the listener also tears down the actual established TCP socket.
      server.shutdown()
      server = MockWebServer().apply {
        enqueue(MockResponse().withWebSocketUpgrade(Peer()))
        start(port)
      }
      events.state(BridgeConnectionState.Retrying)
      events.state(BridgeConnectionState.Connected)
      assertEquals(1, server.requestCount)
    }
  }

  @Test fun forbiddenHandshakeTerminatesWithoutRetry() = runBlocking {
    server.enqueue(MockResponse().setResponseCode(403))
    observe { events ->
      events.state(BridgeConnectionState.Offline)
      assertTrue(withTimeout(5_000) { events.receiveCatching() }.isClosed)
      assertEquals(1, server.requestCount)
    }
  }

  @Test fun policyCloseTerminatesWithoutRetry() = runBlocking {
    val peer = enqueuePeer()
    observe { events ->
      events.state(BridgeConnectionState.Connected)
      peer.opened.await().close(1008, "access revoked")
      withTimeout(5_000) {
        for (event in events) {
          if (event is BridgeEvent.Connection) assertEquals(BridgeConnectionState.Offline, event.state)
        }
      }
      assertEquals(1, server.requestCount)
    }
  }

  @Test fun cancellationDuringBackoffDoesNotReconnect() = runBlocking {
    server.enqueue(MockResponse().setResponseCode(503))
    observe(client { 60_000L }) { events -> events.state(BridgeConnectionState.Retrying) }
    delay(100)
    assertEquals(1, server.requestCount)
  }

  @Test fun cancellationClosesLiveSocketWithoutReconnect() = runBlocking {
    val peer = enqueuePeer()
    observe { events -> events.state(BridgeConnectionState.Connected) }
    withTimeout(5_000) { peer.ended.await() }
    delay(100)
    assertEquals(1, server.requestCount)
  }

  @Test fun immediatelyClosingHandshakesDoNotResetBackoff() = runBlocking {
    repeat(2) {
      server.enqueue(MockResponse().withWebSocketUpgrade(object : WebSocketListener() {
        override fun onOpen(webSocket: WebSocket, response: Response) { webSocket.close(1012, "not ready") }
      }))
    }
    enqueuePeer()
    val attempts = mutableListOf<Int>()
    observe(client { attempts.add(it); 20L }) { events ->
      repeat(3) { events.state(BridgeConnectionState.Connected) }
      assertEquals(listOf(0, 1), attempts)
      assertEquals(3, server.requestCount)
    }
  }
}
