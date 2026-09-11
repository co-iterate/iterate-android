package com.kexin94yyds.iterate.mobile

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import org.json.JSONObject
import java.security.KeyStore
import java.util.UUID
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

class DeviceCredentialStore(context: Context) {
  private val prefs = context.getSharedPreferences("mobile_identity", Context.MODE_PRIVATE)
  val deviceId: String get() = prefs.getString("device_id", null) ?: "android-${UUID.randomUUID()}".also {
    check(prefs.edit().putString("device_id", it).commit()) { "无法保存设备身份" }
  }
  private fun key(): SecretKey {
    val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
    return (store.getKey("iterate.mobile.identity.v1", null) as? SecretKey) ?: KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
      init(KeyGenParameterSpec.Builder("iterate.mobile.identity.v1", KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
        .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
    }.generateKey()
  }
  fun save(connection: PairedConnection) {
    val value = JSONObject().put("base", connection.baseUrl).put("ws", connection.wsUrl).put("token", connection.token)
      .put("device", connection.deviceId).put("desktop", connection.desktopName).toString()
    writeSecret("credential", value)
  }
  fun writeSecret(name: String, value: String) {
    val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.ENCRYPT_MODE, key()) }
    val encrypted = cipher.doFinal(value.toByteArray(Charsets.UTF_8))
    check(prefs.edit().putString(name, Base64.encodeToString(cipher.iv + encrypted, Base64.NO_WRAP)).commit()) { "无法保存数据，请重试" }
  }
  fun readSecret(name: String): String? {
    val saved = prefs.getString(name, null) ?: return null
    val bytes = Base64.decode(saved, Base64.NO_WRAP)
    require(bytes.size > 12)
    val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, bytes.copyOfRange(0, 12))) }
    return String(cipher.doFinal(bytes.copyOfRange(12, bytes.size)), Charsets.UTF_8)
  }
  fun removeSecret(name: String) { check(prefs.edit().remove(name).commit()) }
  fun load(): PairedConnection? {
    val saved = readSecret("credential") ?: return null
    val json = JSONObject(saved)
    return PairedConnection(json.getString("base"), json.getString("ws"), json.getString("token"), json.getString("device"), json.getString("desktop"))
  }
  fun clear() { check(prefs.edit().remove("credential").commit()) }
}
