package com.kexin94yyds.iterate.mobile

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import org.json.JSONObject
import java.net.URI
import java.nio.charset.StandardCharsets
import java.security.KeyStore
import java.util.UUID
import java.util.GregorianCalendar
import java.util.TimeZone
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

private const val ApprovedBaseUrl = "https://8.129.82.226:8443"
private const val ApprovedWsUrl = "wss://8.129.82.226:8443/ws"
private val Rfc3339 = Regex("""^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d+))?(Z|[+-]\d{2}:\d{2})$""")

internal fun rfc3339Millis(value: String): Long {
  val fields = Rfc3339.matchEntire(value)?.groupValues ?: throw IllegalArgumentException("二维码时间格式无效")
  val date = GregorianCalendar(TimeZone.getTimeZone("UTC")).apply {
    isLenient = false
    clear()
    set(fields[1].toInt(), fields[2].toInt() - 1, fields[3].toInt(), fields[4].toInt(), fields[5].toInt(), fields[6].toInt())
    set(GregorianCalendar.MILLISECOND, fields[7].padEnd(3, '0').take(3).toIntOrNull() ?: 0)
  }
  val offset = fields[8]
  val offsetMinutes = if (offset == "Z") 0 else {
    val minutes = offset.substring(1, 3).toInt() * 60 + offset.substring(4, 6).toInt()
    if (offset[0] == '-') -minutes else minutes
  }
  return date.timeInMillis - offsetMinutes * 60_000L
}

data class AndroidPairingPayload(
  val baseUrl: String,
  val wsUrl: String,
  val pairingToken: String,
) {
  companion object {
    fun parse(raw: String): AndroidPairingPayload {
      val encoded = if (raw.startsWith("iterate://pairing?")) {
        URI(raw).rawQuery?.split('&')?.firstOrNull { it.startsWith("payload=") }?.substringAfter('=')
          ?: throw IllegalArgumentException("二维码缺少配对内容")
      } else raw.trim()
      require(encoded.length in 20..12_000) { "配对内容长度无效" }
      val decoded = Base64.decode(encoded, Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING)
      return fromJson(JSONObject(String(decoded, StandardCharsets.UTF_8)))
    }

    internal fun fromJson(json: JSONObject): AndroidPairingPayload {
      require(json.optInt("version") == 2) { "二维码版本不受支持" }
      val base = json.getString("base_url").trimEnd('/')
      val ws = json.getString("ws_url")
      require(base == ApprovedBaseUrl && ws == ApprovedWsUrl) { "二维码地址不是当前阿里云连接" }
      val expires = rfc3339Millis(json.getString("expires_at"))
      require(expires > System.currentTimeMillis()) { "二维码已过期，请在电脑上刷新" }
      val token = json.getString("pairing_token")
      require(token.startsWith("pt_") && token.length >= 20) { "二维码凭据无效" }
      return AndroidPairingPayload(base, ws, token)
    }
  }
}

data class SavedPairing(
  val baseUrl: String,
  val wsUrl: String,
  val deviceId: String,
  val deviceToken: String,
)

/** Android Keystore AES-GCM protects the persisted device bearer. */
class PairingStore(context: Context) {
  private val prefs = context.applicationContext.getSharedPreferences("iterate_android_pairing", Context.MODE_PRIVATE)
  private val keyAlias = "iterate_android_device_v1"

  fun deviceId(): String {
    val saved = prefs.getString("device_id", null)
    if (!saved.isNullOrBlank()) return saved
    val generated = "android-${UUID.randomUUID()}"
    prefs.edit().putString("device_id", generated).apply()
    return generated
  }

  fun save(pairing: SavedPairing) {
    require(pairing.baseUrl == ApprovedBaseUrl && pairing.wsUrl == ApprovedWsUrl)
    val plain = JSONObject()
      .put("device_id", pairing.deviceId)
      .put("device_token", pairing.deviceToken)
      .toString().toByteArray(StandardCharsets.UTF_8)
    val cipher = Cipher.getInstance("AES/GCM/NoPadding")
    cipher.init(Cipher.ENCRYPT_MODE, secretKey())
    val encrypted = cipher.doFinal(plain)
    prefs.edit()
      .putString("iv", Base64.encodeToString(cipher.iv, Base64.NO_WRAP))
      .putString("credential", Base64.encodeToString(encrypted, Base64.NO_WRAP))
      .apply()
  }

  fun load(): SavedPairing? {
    val iv = prefs.getString("iv", null) ?: return null
    val data = prefs.getString("credential", null) ?: return null
    return runCatching {
      val cipher = Cipher.getInstance("AES/GCM/NoPadding")
      cipher.init(Cipher.DECRYPT_MODE, secretKey(), GCMParameterSpec(128, Base64.decode(iv, Base64.NO_WRAP)))
      val json = JSONObject(String(cipher.doFinal(Base64.decode(data, Base64.NO_WRAP)), StandardCharsets.UTF_8))
      SavedPairing(ApprovedBaseUrl, ApprovedWsUrl, json.getString("device_id"), json.getString("device_token"))
    }.getOrNull()
  }

  fun clear() {
    prefs.edit().remove("iv").remove("credential").apply()
  }

  private fun secretKey(): SecretKey {
    val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
    (store.getKey(keyAlias, null) as? SecretKey)?.let { return it }
    val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
    generator.init(KeyGenParameterSpec.Builder(
      keyAlias,
      KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
    ).setBlockModes(KeyProperties.BLOCK_MODE_GCM)
      .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
      .setRandomizedEncryptionRequired(true)
      .build())
    return generator.generateKey()
  }
}
