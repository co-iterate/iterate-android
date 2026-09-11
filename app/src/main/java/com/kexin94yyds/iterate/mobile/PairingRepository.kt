package com.kexin94yyds.iterate.mobile

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.net.URI
import java.net.URLDecoder
import java.text.SimpleDateFormat
import java.util.Locale
import okio.ByteString.Companion.decodeBase64
import java.util.concurrent.TimeUnit

// Never include bearer credentials or enrollment grants in toString/logging.
class PairedConnection(val baseUrl: String, val wsUrl: String, val token: String, val deviceId: String, val desktopName: String) {
  override fun toString() = "PairedConnection(redacted)"
  fun client() = BridgeClient(baseUrl, wsUrl, token)
}
class PairingOffer(val baseUrl: String, val wsUrl: String, val grant: String, val desktopName: String) {
  override fun toString() = "PairingOffer(redacted)"
}

object PairingParser {
  fun parse(input: String, now: Long = System.currentTimeMillis(), allowDebugLoopback: Boolean = false): PairingOffer {
    require(input.length in 1..65_536) { "配对内容无效" }
    val raw = input.trim()
    val payload = if (raw.startsWith("{")) raw else {
      val uri = URI(raw)
      require(uri.scheme == "iterate" && uri.host == "pairing" || uri.scheme == "https") { "请粘贴电脑生成的配对链接" }
      val encoded = uri.rawQuery.orEmpty().split('&').firstOrNull { it.substringBefore('=') == "payload" }
        ?.substringAfter('=') ?: error("配对链接缺少内容")
      val decoded = URLDecoder.decode(encoded, "UTF-8")
      if (decoded.startsWith("{")) decoded else {
        val normalized = decoded.replace('-', '+').replace('_', '/')
        normalized.decodeBase64()?.utf8() ?: error("配对内容编码无效")
      }
    }
    val json = JSONObject(payload)
    require(json.optInt("version") == 2) { "此配对版本暂不支持，请在电脑重新生成" }
    val expiry = json.optString("expires_at").replace(Regex("\\.\\d+(?=Z|[+-]\\d\\d:)"), "")
    val formatter = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ssXXX", Locale.US).apply { isLenient = false }
    require((formatter.parse(expiry)?.time ?: 0) > now) { "配对链接已过期，请在电脑重新生成" }
    val base = json.getString("base_url").trimEnd('/')
    val ws = json.getString("ws_url")
    val http = URI(base); val socket = URI(ws)
    val loopback = allowDebugLoopback && http.host in setOf("127.0.0.1", "localhost") && http.scheme == "http" && socket.scheme == "ws"
    require(loopback || http.scheme == "https" && socket.scheme == "wss") { "配对需要安全的 HTTPS 连接" }
    require(!http.host.isNullOrBlank() && http.host == socket.host && http.port == socket.port &&
      http.userInfo == null && socket.userInfo == null && http.query == null && socket.query == null &&
      http.fragment == null && socket.fragment == null && http.path.orEmpty().isEmpty() && socket.path == "/ws") { "配对地址不一致" }
    require(!json.optString("transport_mode").contains("relay", true)) { "此链接使用 Relay，请使用电脑提供的 HTTPS 直连配对入口" }
    val grant = json.getString("pairing_token")
    require(grant.isNotBlank() && grant.length <= 4096) { "配对凭据无效" }
    return PairingOffer(base, ws, grant, json.optString("device_name", "电脑"))
  }
}

class PairingRepository(private val client: OkHttpClient = OkHttpClient.Builder()
  .connectTimeout(10, TimeUnit.SECONDS).readTimeout(15, TimeUnit.SECONDS)
  .followRedirects(false).followSslRedirects(false).build()) {
  suspend fun claim(offer: PairingOffer, deviceId: String, deviceName: String): PairedConnection = withContext(Dispatchers.IO) {
    val body = JSONObject().put("pairing_token", offer.grant).put("device_id", deviceId)
      .put("device_name", deviceName).put("client_kind", "android").toString()
    client.newCall(Request.Builder().url("${offer.baseUrl}/api/mobile/pairing/claim")
      .post(body.toRequestBody("application/json".toMediaType())).build()).execute().use { response ->
      val data = runCatching { JSONObject(response.body?.string().orEmpty()) }.getOrNull()
      if (!response.isSuccessful) {
        if (data?.optString("error") == "invalid_client_kind") error("电脑版本尚未支持安卓配对，请更新电脑端")
        error("配对未成功（HTTP ${response.code}），请检查电脑连接或重新生成链接")
      }
      require(data != null && data.optBoolean("ok") && data.optString("device_id") == deviceId) { "配对响应无效" }
      val token = data!!.optString("device_token")
      require(token.isNotBlank() && token.length <= 4096) { "电脑未返回设备凭据" }
      PairedConnection(offer.baseUrl, offer.wsUrl, token, deviceId, offer.desktopName)
    }
  }
}
