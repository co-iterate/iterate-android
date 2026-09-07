package com.kexin94yyds.iterate.mobile

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.relocation.BringIntoViewRequester
import androidx.compose.foundation.relocation.bringIntoViewRequester
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.ime
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun InputSection(
  value: String,
  placeholder: String,
  predefinedOptions: List<String>,
  selectedOptions: Set<String>,
  onValueChange: (String) -> Unit,
  onOptionClick: (String) -> Unit,
) {
  val colors = WorkbenchTheme.colors
  var focused by remember { mutableStateOf(false) }
  val bringIntoView = remember { BringIntoViewRequester() }
  val imeBottom = WindowInsets.ime.getBottom(LocalDensity.current)
  LaunchedEffect(focused, imeBottom) {
    if (focused && imeBottom > 0) {
      withFrameNanos { }
      bringIntoView.bringIntoView()
    }
  }
  Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
    BasicTextField(
      value = value,
      onValueChange = onValueChange,
      textStyle = TextStyle(fontSize = 14.sp, lineHeight = 22.sp, color = colors.text),
      cursorBrush = SolidColor(colors.accent),
      minLines = 5,
      maxLines = 7,
      modifier = Modifier
        .testTag("reply_editor")
        .fillMaxWidth()
        .bringIntoViewRequester(bringIntoView)
        .onFocusChanged { focused = it.isFocused }
        .clip(RoundedCornerShape(10.dp))
        .background(colors.secondaryBackground)
        .border(1.dp, if (focused) colors.accent.copy(alpha = 0.6f) else colors.border, RoundedCornerShape(10.dp))
        .padding(16.dp),
      decorationBox = { innerTextField ->
        androidx.compose.foundation.layout.Box {
          if (value.isEmpty()) {
            Text(placeholder, fontSize = 14.sp, lineHeight = 22.sp, color = colors.secondaryText)
          }
          innerTextField()
        }
      },
    )
    if (predefinedOptions.isNotEmpty()) {
      Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text("预定义选项", fontSize = 10.sp, fontWeight = FontWeight.Bold,
          letterSpacing = 1.sp, color = colors.secondaryText,
          modifier = Modifier.padding(bottom = 2.dp))
        predefinedOptions.forEach { option ->
          val selected = option in selectedOptions
          Row(
            modifier = Modifier
              .fillMaxWidth()
              .clip(RoundedCornerShape(6.dp))
              .background(if (selected) colors.accent.copy(alpha = 0.12f) else colors.card)
              .border(1.dp, if (selected) colors.accent else colors.border, RoundedCornerShape(6.dp))
              .toggleable(value = selected, role = Role.Checkbox, onValueChange = { onOptionClick(option) })
              .heightIn(min = 48.dp)
              .padding(horizontal = 12.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
          ) {
            Text(option, fontSize = 14.sp, lineHeight = 21.sp, color = colors.text, modifier = Modifier.weight(1f))
            if (selected) {
              Icon(Icons.Default.Check, contentDescription = null, tint = colors.accent, modifier = Modifier.size(16.dp))
            }
          }
        }
      }
    }
  }
}

@Composable
fun InlineVoiceInput(voiceState: VoiceInputState, onClick: () -> Unit) {
  val colors = WorkbenchTheme.colors
  Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
    Text(if (voiceState == VoiceInputState.Listening) "再次点击以完成" else "点击开始语音输入",
      color = colors.secondaryText, fontSize = 12.sp)
    MicrophoneButton(voiceState, onClick)
  }
}

@Composable
fun MicrophoneButton(voiceState: VoiceInputState, onClick: () -> Unit, modifier: Modifier = Modifier) {
  val colors = WorkbenchTheme.colors
  val listening = voiceState == VoiceInputState.Listening
  IconButton(onClick = onClick, modifier = modifier.size(56.dp)) {
    Icon(
      imageVector = if (listening) Icons.Default.Stop else Icons.Default.Mic,
      contentDescription = if (listening) "停止语音输入" else "开始语音输入",
      tint = if (listening) colors.text else colors.secondaryText,
      modifier = Modifier.size(26.dp),
    )
  }
}

@Composable
fun VoiceStatus(voiceState: VoiceInputState) {
  val text = when (voiceState) {
    VoiceInputState.PermissionDenied -> "需要麦克风权限。允许后，再次点击语音按钮。"
    VoiceInputState.Error -> "暂时无法识别语音，请重试或输入文字。"
    VoiceInputState.Listening -> "正在聆听，点击麦克风结束。"
    VoiceInputState.Idle -> return
  }
  Text(text, fontSize = 12.sp, color = WorkbenchTheme.colors.secondaryText)
}
