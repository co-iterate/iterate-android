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
  fun hasSecret(name: String): Boolean = prefs.contains(name)
  fun readSecret(name: String): String? {
    val saved = prefs.getString(name, null) ?: return null
    val bytes = Base64.decode(saved, Base64.NO_WRAP)
    require(bytes.size > 12)
    val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, bytes.copyOfRange(0, 12))) }
    return String(cipher.doFinal(bytes.copyOfRange(12, bytes.size)), Charsets.UTF_8)
  }
  fun removeSecret(name: String) { check(prefs.edit().remove(name).commit()) }
  fun replyDraftKeys(): List<String> = prefs.all.keys.filter { it.startsWith("reply_draft_") }.sorted()
  fun readReplyDraft(name: String): String? {
    require(name.startsWith("reply_draft_"))
    return readSecret(name)
  }
  fun deleteReplyDraft(name: String) {
    require(name.startsWith("reply_draft_"))
    removeSecret(name)
  }
  fun archivePendingReply(): String {
    val encrypted = prefs.getString("pending_reply", null) ?: error("待发送记录不存在")
    check(replyDraftKeys().size < 10) { "已保存 10 条草稿，请先查看并删除不再需要的草稿；待发送内容仍保留" }
    val name = "reply_draft_${UUID.randomUUID()}"
    // Move the original ciphertext atomically, including unreadable records. No plaintext or
    // pairing credentials are copied into a second store, and old drafts are never overwritten.
    if (!prefs.edit().putString(name, encrypted).remove("pending_reply").commit()) {
      // commit() also changes the in-memory map on failure; keep the original pending record.
      prefs.edit().putString("pending_reply", encrypted).remove(name).commit()
      error("草稿保存失败，待发送内容仍保留")
    }
    return name
  }
  fun load(): PairedConnection? {
    val saved = readSecret("credential") ?: return null
    val json = JSONObject(saved)
    return PairedConnection(json.getString("base"), json.getString("ws"), json.getString("token"), json.getString("device"), json.getString("desktop"))
  }
  fun clear() { check(prefs.edit().remove("credential").commit()) }
}
