package com.kexin94yyds.iterate.mobile

import android.content.Context
import android.graphics.Bitmap
import android.util.Base64
import androidx.activity.compose.setContent
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONObject
import org.json.JSONArray
import org.junit.Assert.*
import org.junit.*
import org.junit.runners.MethodSorters
import java.io.ByteArrayOutputStream
import java.io.File

/** Run a_stagePendingReply, force-stop the app, then run b_recoverAndArchiveAfterRestart. */
@FixMethodOrder(MethodSorters.NAME_ASCENDING)
class PendingReplyRestartTest {
  @get:Rule val compose = createAndroidComposeRule<WorkbenchPreviewActivity>()
  private val app get() = InstrumentationRegistry.getInstrumentation().targetContext
  private fun record(): String {
    val output = ByteArrayOutputStream()
    Bitmap.createBitmap(1, 1, Bitmap.Config.ARGB_8888).apply {
      compress(Bitmap.CompressFormat.PNG, 100, output); recycle()
    }
    return JSONObject().put("base", "https://previous-desktop.invalid").put("identity", "old-pairing-digest")
      .put("desktop", "Original fixture desktop")
      .put("payload", JSONObject().put("operation_id", "restart-operation-fixture")
        .put("request_id", "original-request").put("project_path", "/original/project")
        .put("user_input", "Preserve this reply after process death")
        .put("selected_options", JSONArray().put("Original option"))
        .put("images", JSONArray().put(JSONObject().put("filename", "restart.png")
          .put("data", "data:image/png;base64," + Base64.encodeToString(output.toByteArray(), Base64.NO_WRAP)))))
      .toString()
  }
  @Test fun a_stagePendingReply() {
    val store = DeviceCredentialStore(app)
    assertTrue("fixture requires an empty draft store", store.replyDraftKeys().isEmpty())
    store.clear()
    store.writeSecret("pending_reply", record())
    assertTrue(store.hasSecret("pending_reply"))
  }
  @Test fun b_recoverAndArchiveAfterRestart() {
    val store = DeviceCredentialStore(app)
    val original = store.readSecret("pending_reply")!!
    val manager = ConnectionManager.get(app)
    assertTrue(manager.state.value.pendingReply)
    try {
      compose.runOnUiThread {
        compose.activity.setContent { AndroidMobileTheme(lightAppearance = true) { ConnectionSettings(onBack = {}) } }
      }
      compose.onNodeWithTag("archive-pending-reply").performScrollTo().performClick()
      compose.waitUntil(5000) { !manager.state.value.pendingReply }
      compose.waitUntil(5000) { compose.onAllNodesWithTag("saved-reply-text").fetchSemanticsNodes().isNotEmpty() }
      compose.onNodeWithTag("saved-reply-text").performScrollTo().assertTextContains("Preserve this reply after process death", substring = true)
      compose.onNodeWithTag("saved-reply-text").assertTextContains("Original option", substring = true)
      compose.onNodeWithContentDescription("restart.png").assertExists()
      val freshStore = DeviceCredentialStore(app)
      assertFalse(freshStore.hasSecret("pending_reply"))
      val draft = freshStore.readReplyDraft(freshStore.replyDraftKeys().single())!!
      assertEquals(original, draft)
      assertEquals("old-pairing-digest", JSONObject(draft).getString("identity"))
      assertNull("archive never installs or forwards the previous identity", manager.paired)
      InstrumentationRegistry.getInstrumentation().uiAutomation.takeScreenshot()?.let { bitmap ->
        File(app.getExternalFilesDir(null), "retained-reply-draft.png").outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
        bitmap.recycle()
      }
    } finally {
      compose.runOnUiThread { store.replyDraftKeys().forEach { manager.deleteReplyDraft(it) }; manager.discardPendingReply() }
    }
  }
  @Test fun c_corruptCiphertextCanBeRetainedWithoutBeingOverwritten() {
    val prefs = app.getSharedPreferences("mobile_identity", Context.MODE_PRIVATE)
    val store = DeviceCredentialStore(app)
    prefs.edit().putString("pending_reply", "damaged-original-ciphertext").commit()
    val key = store.archivePendingReply()
    try {
      assertEquals("damaged-original-ciphertext", prefs.getString(key, null))
      assertFalse(store.hasSecret("pending_reply"))
      assertTrue(runCatching { store.readReplyDraft(key) }.isFailure)
    } finally { store.deleteReplyDraft(key) }
  }
  @Test fun d_fullDraftStoreKeepsThePendingReply() {
    val store = DeviceCredentialStore(app)
    assertTrue(store.replyDraftKeys().isEmpty())
    try {
      repeat(10) { store.writeSecret("pending_reply", record()); store.archivePendingReply() }
      val pending = record()
      store.writeSecret("pending_reply", pending)
      assertTrue(runCatching { store.archivePendingReply() }.isFailure)
      assertEquals(pending, store.readSecret("pending_reply"))
      assertEquals(10, store.replyDraftKeys().size)
    } finally { store.replyDraftKeys().forEach(store::deleteReplyDraft); store.removeSecret("pending_reply") }
  }
}
