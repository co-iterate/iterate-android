package com.kexin94yyds.iterate

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import com.kexin94yyds.iterate.mobile.AndroidMobileWorkbenchApp
import com.kexin94yyds.iterate.mobile.BridgeViewModel
import com.kexin94yyds.iterate.mobile.PairingStore
import android.content.Intent

class MainActivity : ComponentActivity() {
  private val bridgeViewModel by lazy { BridgeViewModel(PairingStore(this)) }

  override fun onCreate(savedInstanceState: Bundle?) {
    enableEdgeToEdge()
    super.onCreate(savedInstanceState)
    setContent {
      AndroidMobileWorkbenchApp(activity = this, viewModel = bridgeViewModel)
    }
    consumePairingIntent(intent)
  }

  override fun onNewIntent(intent: Intent) {
    super.onNewIntent(intent)
    setIntent(intent)
    consumePairingIntent(intent)
  }

  private fun consumePairingIntent(source: Intent?) {
    val payload = source?.getStringExtra(MobilePairingPayloadExtra) ?: return
    source.removeExtra(MobilePairingPayloadExtra)
    bridgeViewModel.importPairing(payload)
  }
}

internal const val MobilePairingPayloadExtra = "android_pairing_payload"
