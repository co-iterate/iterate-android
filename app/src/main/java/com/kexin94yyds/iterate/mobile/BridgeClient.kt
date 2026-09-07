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
  @Volatile private var activeSocket: WebSocket? = null

  fun syncProject(project: ActiveProject): Boolean = activeSocket?.send(org.json.JSONObject()
    .put("message_type", "request_sync").put("payload", org.json.JSONObject()
      .put("client_kind", "android").put("project_path", project.path).put("request_id", project.requestId)).toString()) == true

  suspend fun readJson(path: String): org.json.JSONObject = withContext(Dispatchers.IO) {
    val http = client.newBuilder().readTimeout(10, TimeUnit.SECONDS).build()
    http.newCall(Request.Builder().url("$baseUrl$path").build()).execute().use { response ->
      if (!response.isSuccessful) throw IOException("读取失败：${response.code}")
      org.json.JSONObject(response.body?.string().orEmpty())
    }
  }

  fun requests(): Flow<Result<MobileRequest>> = callbackFlow {
    val request = Request.Builder().url(wsUrl).header("X-Iterate-Client-Kind", "android").build()

    val socket = client.newWebSocket(request, object : WebSocketListener() {
      override fun onOpen(webSocket: WebSocket, response: Response) {
        activeSocket = webSocket
        webSocket.send("""{"message_type":"client_hello","payload":{"client_kind":"android"}}""")
        webSocket.send("""{"message_type":"request_sync","payload":{}}""")
      }

      override fun onMessage(webSocket: WebSocket, text: String) {
        val parsed = BridgeJsonParser.parseRequest(text)
        if (parsed != null) trySend(Result.success(parsed))
      }

      override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
        if (activeSocket === webSocket) activeSocket = null
        trySend(Result.failure(IOException("连接已关闭")))
      }

      override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
        if (activeSocket === webSocket) activeSocket = null
        trySend(Result.failure(t))
      }
    })

    awaitClose {
      if (activeSocket === socket) activeSocket = null
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
    activeSocket?.send(json) == true
  }

  suspend fun openCodexChat(): Boolean = withContext(Dispatchers.IO) {
    val body = "{}".toRequestBody("application/json".toMediaType())
    val request = Request.Builder().url("$baseUrl/api/open-codex-chat")
      .post(body)
      .build()
    runCatching {
      client.newCall(request).execute().use { it.isSuccessful }
    }.getOrDefault(false)
  }
}
