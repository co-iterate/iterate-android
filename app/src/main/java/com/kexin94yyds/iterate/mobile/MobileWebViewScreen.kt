package com.kexin94yyds.iterate.mobile

import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Chat
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView

private const val MobileHomeUrl = "http://127.0.0.1:8080/mobile"

@Composable
fun MobileWebViewScreen(onBackToConversation: () -> Unit) {
  Column(modifier = Modifier.fillMaxSize()) {
    Row(
      modifier = Modifier
        .fillMaxWidth()
        .padding(start = 12.dp, end = 12.dp, top = 28.dp, bottom = 8.dp),
      verticalAlignment = Alignment.CenterVertically,
    ) {
      IconButton(onClick = onBackToConversation) {
        Icon(Icons.Default.Chat, contentDescription = "返回会话")
      }
      Text("iterate")
    }
    AndroidView(
      modifier = Modifier.fillMaxSize(),
      factory = { context ->
        WebView(context).apply {
          webViewClient = WebViewClient()
          settings.javaScriptEnabled = true
          settings.domStorageEnabled = true
          loadUrl(MobileHomeUrl)
        }
      },
      update = { webView ->
        if (webView.url != MobileHomeUrl) {
          webView.loadUrl(MobileHomeUrl)
        }
      },
    )
  }
}
