package com.kexin94yyds.iterate.mobile

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import java.io.IOException
import java.util.concurrent.TimeUnit
import kotlin.random.Random

class BridgeClient(
  private val baseUrl: String = "http://127.0.0.1:8080",
  private val wsUrl: String = "ws://127.0.0.1:8080/ws",
  private val client: OkHttpClient = OkHttpClient.Builder()
    .connectTimeout(3, TimeUnit.SECONDS)
    .readTimeout(0, TimeUnit.SECONDS)
    .pingInterval(30, TimeUnit.SECONDS)
    .build(),
  private val retryDelayMillis: (Int) -> Long = { attempt ->
    val ceiling = minOf(30_000L, 500L shl attempt.coerceIn(0, 6))
    Random.nextLong(ceiling + 1)
  },
) {
  fun events(): Flow<BridgeEvent> = flow {
    var attempt = 0
    while (currentCoroutineContext().isActive) {
      emit(BridgeEvent.Connection(BridgeConnectionState.Connecting))
      var openedAt: Long? = null
      try {
        socketEvents().collect { event ->
          if (event is BridgeEvent.Connection && event.state == BridgeConnectionState.Connected) {
            openedAt = System.nanoTime()
          }
          emit(event)
        }
        return@flow
      } catch (cancelled: CancellationException) {
        throw cancelled
      } catch (failure: SocketFailure) {
        if (!failure.retryable) {
          emit(BridgeEvent.Connection(BridgeConnectionState.Offline, failure.message))
          return@flow
        }
        // A handshake immediately followed by a close is not a stable recovery.
        if (openedAt?.let { System.nanoTime() - it >= TimeUnit.SECONDS.toNanos(30) } == true) {
          attempt = 0
        }
        emit(BridgeEvent.Connection(BridgeConnectionState.Retrying, failure.message))
        delay(retryDelayMillis(attempt).coerceAtLeast(0))
        attempt = (attempt + 1).coerceAtMost(6)
      }
    }
  }

  private fun socketEvents(): Flow<BridgeEvent> = callbackFlow {
    val request = Request.Builder()
      .url(wsUrl)
      .header("X-Iterate-Client-Kind", "android")
      .build()

    val socket = client.newWebSocket(request, object : WebSocketListener() {
      override fun onOpen(webSocket: WebSocket, response: Response) {
        webSocket.send("""{"message_type":"client_hello","payload":{"client_kind":"android"}}""")
        webSocket.send("""{"message_type":"request_sync","payload":{}}""")
        trySend(BridgeEvent.Connection(BridgeConnectionState.Connected))
      }

      override fun onMessage(webSocket: WebSocket, text: String) {
        val parsed = BridgeJsonParser.parseRequest(text)
        if (parsed != null) trySend(BridgeEvent.RequestReceived(parsed))
      }

      override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
        trySend(BridgeEvent.Connection(BridgeConnectionState.Offline, "连接已关闭（$code）"))
        // Acknowledge the peer's Close before releasing this session.
        webSocket.close(if (code == 1005) 1000 else code, reason)
      }

      override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
        close(SocketFailure("连接已关闭（$code）", code !in setOf(1002, 1003, 1007, 1008, 1009, 1010)))
      }

      override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
        val status = response?.code
        val retryable = status == null || status == 408 || status == 429 || status >= 500
        close(SocketFailure(if (status == null) "连接中断" else "连接失败（HTTP $status）", retryable, t))
      }
    })

    awaitClose {
      socket.cancel()
    }
  }

  private class SocketFailure(message: String, val retryable: Boolean, cause: Throwable? = null) :
    IOException(message, cause)

  suspend fun checkVersion(): String = withContext(Dispatchers.IO) {
    val request = Request.Builder().url("$baseUrl/api/version").build()
    client.newCall(request).execute().use { response ->
      if (!response.isSuccessful) throw IOException("bridge version failed: ${response.code}")
      response.body?.string().orEmpty()
    }
  }

  suspend fun sendAction(json: String): Boolean = withContext(Dispatchers.IO) {
    val opened = CompletableDeferred<WebSocket?>()
    val request = Request.Builder()
      .url(wsUrl)
      .header("X-Iterate-Client-Kind", "android")
      .build()
    val socket = client.newWebSocket(request, object : WebSocketListener() {
      override fun onOpen(webSocket: WebSocket, response: Response) {
        opened.complete(webSocket)
      }

      override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
        if (!opened.isCompleted) opened.complete(null)
      }
    })

    val readySocket = withTimeoutOrNull(3_000) { opened.await() }
    if (readySocket == null) {
      socket.close(1001, "android_action_open_failed")
      return@withContext false
    }
    val sent = readySocket.send(json)
    readySocket.close(1000, "android_action_sent")
    sent
  }

  suspend fun openCodexChat(): Boolean = withContext(Dispatchers.IO) {
    val body = "{}".toRequestBody("application/json".toMediaType())
    val request = Request.Builder()
      .url("$baseUrl/api/open-codex-chat")
      .post(body)
      .build()
    runCatching {
      client.newCall(request).execute().use { it.isSuccessful }
    }.getOrDefault(false)
  }
}
