package com.kexin94yyds.iterate

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.content.ContextCompat
import com.kexin94yyds.iterate.mobile.*

class MainActivity : ComponentActivity() {
  private var payload by mutableStateOf("")
  override fun onCreate(savedInstanceState: Bundle?) {
    enableEdgeToEdge(); super.onCreate(savedInstanceState)
    acceptIntent(intent)
    setContent { AndroidMobileWorkbenchApp(activity = this, pairingPayload = payload) }
  }
  override fun onNewIntent(intent: Intent) { super.onNewIntent(intent); setIntent(intent); acceptIntent(intent) }
  private fun acceptIntent(intent: Intent?) {
    intent?.getStringExtra(MobilePairingPayloadExtra)?.let { payload = it; intent.removeExtra(MobilePairingPayloadExtra) }
    val id = intent?.getStringExtra("notification_request_id")
    val path = intent?.getStringExtra("notification_project_path")
    if (id != null && path != null) ConnectionManager.get(this).selectRoute(ActiveProject(path, id, "", ""))
  }
  override fun onStart() {
    super.onStart(); ConnectionManager.get(this).setVisible(true)
    if (getSharedPreferences("mobile_preferences", MODE_PRIVATE).getBoolean("continuous", false))
      ContextCompat.startForegroundService(this, Intent(this, ConnectionService::class.java))
  }
  override fun onStop() { ConnectionManager.get(this).setVisible(false); super.onStop() }
}
internal const val MobilePairingPayloadExtra = "android_pairing_payload"
