package com.kexin94yyds.iterate.mobile

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material3.Button
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

@Composable
fun ConnectionScreen(
  state: WorkbenchUiState,
  onBackToConversation: () -> Unit,
  onPairingInput: (String) -> Unit,
  onPair: () -> Unit,
  onForget: () -> Unit,
  onSelectRequest: (MobileRequest) -> Unit,
) {
  Column(
    modifier = Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp),
    verticalArrangement = Arrangement.spacedBy(12.dp),
  ) {
    Text("iterate · Android")
    Text(if (state.paired) "电脑连接：${state.connectionLabel}" else "请用手机扫码电脑上的 Android 配对码")
    state.bridgeError?.let { Text(it) }
    state.actionNotice?.let { Text(it) }
    if (!state.paired) {
      Text("手机相机识别二维码后打开 iterate；也可粘贴完整配对链接。")
      OutlinedTextField(
        value = state.pairingInput,
        onValueChange = onPairingInput,
        label = { Text("配对链接") },
        modifier = Modifier.fillMaxWidth(),
      )
      Button(
        onClick = onPair,
        enabled = !state.pairingBusy && state.pairingInput.isNotBlank(),
      ) { Text(if (state.pairingBusy) "正在配对" else "连接电脑") }
    } else {
      Text("正式路线：8.129.82.226:8443")
      Text("等待请求：${state.requests.size}")
      state.requests.forEach { request ->
        Column(
          modifier = Modifier.fillMaxWidth().clickable { onSelectRequest(request) }.padding(vertical = 10.dp),
        ) {
          Text(request.conversationTitle)
          Text(request.message, maxLines = 2)
        }
      }
      val closedDrafts = state.drafts.filterKeys { it in state.closedRequestKeys }
      if (closedDrafts.isNotEmpty()) {
        Text("已关闭请求的未确认草稿（仅保存在本次运行中）")
        closedDrafts.forEach { (key, draft) ->
          Text("${key.second} · ${key.first}")
          SelectionContainer {
            Text(listOf(draft.text, draft.selectedOptions.joinToString("、"))
              .filter { it.isNotBlank() }
              .joinToString("\n")
              .ifBlank { "无文字内容" })
          }
        }
      }
      Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        OutlinedButton(onClick = onBackToConversation) { Text("返回回复") }
        OutlinedButton(onClick = onForget) { Text("移除此手机配对") }
      }
    }
  }
}
