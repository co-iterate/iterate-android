package com.kexin94yyds.iterate

import android.app.Activity
import android.content.Intent
import android.os.Bundle

class PairingActivity : Activity() {
  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    forwardPairingIntent()
  }

  override fun onNewIntent(intent: Intent) {
    super.onNewIntent(intent)
    setIntent(intent)
    forwardPairingIntent()
  }

  private fun forwardPairingIntent() {
    val payload = intent
      ?.data
      ?.getQueryParameter("payload")
      ?.trim()
      ?.takeIf { it.isNotEmpty() }

    val mainIntent = Intent(this, MainActivity::class.java)
      .setAction(Intent.ACTION_MAIN)
      .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)

    payload?.let { mainIntent.putExtra(MobilePairingPayloadExtra, it) }
    startActivity(mainIntent)
    finish()
  }
}
