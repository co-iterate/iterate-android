package com.kexin94yyds.iterate.mobile

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
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

class BridgeClient(
  private val baseUrl: String = "http://127.0.0.1:8080",
  private val wsUrl: String = "ws://127.0.0.1:8080/ws",
  private val client: OkHttpClient = OkHttpClient.Builder()
    .connectTimeout(3, TimeUnit.SECONDS)
    .readTimeout(0, TimeUnit.SECONDS)
    .build(),
) {
  fun requests(): Flow<Result<MobileRequest>> = callbackFlow {
    val request = Request.Builder()
      .url(wsUrl)
      .header("X-Iterate-Client-Kind", "android")
      .build()

    val socket = client.newWebSocket(request, object : WebSocketListener() {
      override fun onOpen(webSocket: WebSocket, response: Response) {
        webSocket.send("""{"message_type":"client_hello","payload":{"client_kind":"android"}}""")
      }

      override fun onMessage(webSocket: WebSocket, text: String) {
        val parsed = BridgeJsonParser.parseRequest(text)
        if (parsed != null) trySend(Result.success(parsed))
      }

      override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
        trySend(Result.failure(t))
      }
    })

    awaitClose {
      socket.close(1000, "android_compose_closed")
    }
  }

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
