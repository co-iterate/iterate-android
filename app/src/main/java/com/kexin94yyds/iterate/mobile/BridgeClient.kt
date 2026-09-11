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
  private val baseUrl: String,
  private val wsUrl: String,
  private val token: String? = null,
  private val client: OkHttpClient = OkHttpClient.Builder()
    .connectTimeout(3, TimeUnit.SECONDS)
    .readTimeout(0, TimeUnit.SECONDS)
    .pingInterval(30, TimeUnit.SECONDS)
    .followRedirects(false).followSslRedirects(false)
    .build(),
  private val retryDelayMillis: (Int) -> Long = { attempt ->
    val ceiling = minOf(30_000L, 500L shl attempt.coerceIn(0, 6))
    Random.nextLong(ceiling + 1)
  },
) {
  @Volatile private var activeSocket: WebSocket? = null
  private fun request(url: String): Request.Builder = Request.Builder().url(url)
    .header("X-Iterate-Client-Kind", "android")
    .apply { token?.let { header("Authorization", "Bearer $it") } }

  fun syncProject(project: ActiveProject): Boolean = activeSocket?.send(org.json.JSONObject()
    .put("message_type", "request_sync").put("payload", org.json.JSONObject()
      .put("client_kind", "android").put("project_path", project.path).put("request_id", project.requestId)).toString()) == true

  suspend fun readJson(path: String): org.json.JSONObject = withContext(Dispatchers.IO) {
    require(path.startsWith("/") && !path.startsWith("//"))
    client.newBuilder().readTimeout(10, TimeUnit.SECONDS).build()
      .newCall(request("$baseUrl$path").build()).execute().use { response ->
        if (!response.isSuccessful) throw IOException("读取失败（HTTP ${response.code}）")
        org.json.JSONObject(response.body?.string().orEmpty())
      }
  }

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
    val request = request(wsUrl).build()

    val socket = client.newWebSocket(request, object : WebSocketListener() {
      override fun onOpen(webSocket: WebSocket, response: Response) {
        if (isClosedForSend) { webSocket.cancel(); return }
        activeSocket = webSocket
        webSocket.send("""{"message_type":"client_hello","payload":{"client_kind":"android"}}""")
        webSocket.send("""{"message_type":"request_sync","payload":{}}""")
        trySend(BridgeEvent.Connection(BridgeConnectionState.Connected))
      }

      override fun onMessage(webSocket: WebSocket, text: String) {
        val parsed = BridgeJsonParser.parseRequest(text)
        if (parsed != null) trySend(BridgeEvent.RequestReceived(parsed))
      }

      override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
        if (activeSocket === webSocket) activeSocket = null
        trySend(BridgeEvent.Connection(BridgeConnectionState.Offline, "连接已关闭（$code）"))
        // Acknowledge the peer's Close before releasing this session.
        webSocket.close(if (code == 1005) 1000 else code, reason)
      }

      override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
        close(SocketFailure("连接已关闭（$code）", code !in setOf(1002, 1003, 1007, 1008, 1009, 1010)))
      }

      override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
        if (activeSocket === webSocket) activeSocket = null
        val status = response?.code
        val retryable = status == null || status == 408 || status == 429 || status >= 500
        close(SocketFailure(if (status == null) "连接中断" else "连接失败（HTTP $status）", retryable, t))
      }
    })

    awaitClose {
      if (activeSocket === socket) activeSocket = null
      socket.cancel()
    }
  }

  private class SocketFailure(message: String, val retryable: Boolean, cause: Throwable? = null) :
    IOException(message, cause)

  suspend fun checkVersion(): String = withContext(Dispatchers.IO) {
    val request = request("$baseUrl/api/version").build()
    client.newCall(request).execute().use { response ->
      if (!response.isSuccessful) throw IOException("bridge version failed: ${response.code}")
      response.body?.string().orEmpty()
    }
  }

  suspend fun sendAction(json: String): Boolean = activeSocket?.send(json) == true

  suspend fun sendReply(payload: org.json.JSONObject): org.json.JSONObject = withContext(Dispatchers.IO) {
    client.newBuilder().readTimeout(20, TimeUnit.SECONDS).build().newCall(
      request("$baseUrl/api/mobile/reply").post(payload.toString().toRequestBody("application/json".toMediaType())).build()
    ).execute().use { response ->
      if (response.code == 404) throw ReplyUnsupported()
      if (response.code == 401 || response.code == 403) throw ReplyUnauthorized()
      if (response.code in 400..499) throw ReplyRejected()
      if (!response.isSuccessful) throw IOException("reply temporarily unavailable")
      org.json.JSONObject(response.body?.string().orEmpty())
    }
  }
  class ReplyUnsupported : IOException()
  class ReplyUnauthorized : IOException()
  class ReplyRejected : IOException()

  suspend fun openCodexChat(): Boolean = withContext(Dispatchers.IO) {
    val body = "{}".toRequestBody("application/json".toMediaType())
    val request = request("$baseUrl/api/open-codex-chat")
      .post(body)
      .build()
    runCatching {
      client.newCall(request).execute().use { it.isSuccessful }
    }.getOrDefault(false)
  }
}
