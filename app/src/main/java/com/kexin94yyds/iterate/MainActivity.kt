package com.kexin94yyds.iterate

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import com.kexin94yyds.iterate.mobile.AndroidMobileWorkbenchApp

class MainActivity : ComponentActivity() {
  override fun onCreate(savedInstanceState: Bundle?) {
    enableEdgeToEdge()
    super.onCreate(savedInstanceState)
    setContent {
      AndroidMobileWorkbenchApp(activity = this)
    }
  }
}

internal const val MobilePairingPayloadExtra = "android_pairing_payload"
