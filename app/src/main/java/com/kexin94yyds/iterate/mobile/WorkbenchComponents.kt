package com.kexin94yyds.iterate.mobile

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.DarkMode
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.LightMode
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.NotificationsOff
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

@Composable
fun WorkbenchHeader(
  title: String,
  subtitle: String,
  connectionLabel: String,
  connectionState: BridgeConnectionState,
  notificationsEnabled: Boolean,
  lightAppearance: Boolean,
  onHomeClick: () -> Unit,
  onNotificationClick: () -> Unit,
  onThemeClick: () -> Unit,
  onNewChatClick: () -> Unit,
) {
  Row(
    modifier = Modifier
      .fillMaxWidth()
      .background(IosParityColors.Background)
      .border(width = 0.5.dp, color = IosParityColors.SurfaceBorder)
      .padding(start = 14.dp, end = 14.dp, top = 30.dp, bottom = 14.dp),
    verticalAlignment = Alignment.CenterVertically,
  ) {
    Text("∞", fontSize = 26.sp, fontWeight = FontWeight.Bold, color = IosParityColors.Text)
    Spacer(Modifier.width(14.dp))
    Column(modifier = Modifier.weight(1f)) {
      Text(
        text = title,
        fontSize = 17.sp,
        fontWeight = FontWeight.Bold,
        color = IosParityColors.Text,
        maxLines = 1,
        overflow = TextOverflow.Ellipsis,
      )
      Text(
        text = subtitle,
        fontSize = 12.sp,
        color = IosParityColors.TextSecondary,
        maxLines = 1,
        overflow = TextOverflow.Ellipsis,
      )
    }
    HeaderIconButton(Icons.Default.Home, "Home", onHomeClick)
    HeaderIconButton(
      icon = if (notificationsEnabled) Icons.Default.Notifications else Icons.Default.NotificationsOff,
      label = "Notifications",
      action = onNotificationClick,
    )
    HeaderIconButton(
      icon = if (lightAppearance) Icons.Default.DarkMode else Icons.Default.LightMode,
      label = "Theme",
      action = onThemeClick,
    )
    HeaderIconButton(Icons.Default.Add, "New chat", onNewChatClick)
    Spacer(Modifier.width(8.dp))
    Box(
      modifier = Modifier
        .size(9.dp)
        .clip(CircleShape)
        .background(
          if (connectionState == BridgeConnectionState.Connected) {
            IosParityColors.Connected
          } else {
            IosParityColors.TextSecondary
          },
        ),
    )
    Spacer(Modifier.width(4.dp))
    Text(
      text = connectionLabel,
      fontSize = 12.sp,
      color = IosParityColors.TextSecondary,
      maxLines = 1,
      overflow = TextOverflow.Ellipsis,
    )
  }
}

@Composable
fun HeaderIconButton(icon: ImageVector, label: String, action: () -> Unit) {
  Box(
    modifier = Modifier
      .padding(start = 6.dp)
      .size(42.dp)
      .clip(CircleShape)
      .background(IosParityColors.IconCircle)
      .clickable(onClick = action),
    contentAlignment = Alignment.Center,
  ) {
    Icon(icon, contentDescription = label, tint = IosParityColors.Text, modifier = Modifier.size(22.dp))
  }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun MessageCard(request: MobileRequest) {
  Surface(
    modifier = Modifier.fillMaxWidth(),
    shape = RoundedCornerShape(12.dp),
    color = IosParityColors.Surface,
    border = BorderStroke(1.dp, IosParityColors.FocusBorder),
  ) {
    Column(modifier = Modifier.padding(16.dp)) {
      Text(request.message, fontSize = 18.sp, lineHeight = 28.sp, color = IosParityColors.Text)
      Spacer(Modifier.height(14.dp))
      if (!request.browserAiResponse.isNullOrBlank()) {
        CodeBlock(text = request.browserAiResponse)
        Spacer(Modifier.height(14.dp))
      }
      Text("验证结果:", fontSize = 17.sp, color = IosParityColors.Text)
      Spacer(Modifier.height(10.dp))
      Text("• DMG notarization: Accepted", fontSize = 15.sp, lineHeight = 24.sp, color = IosParityColors.Text)
      Text("• stapler staple/validate: 通过", fontSize = 15.sp, lineHeight = 24.sp, color = IosParityColors.Text)
      Text("• codesign --verify: 通过", fontSize = 15.sp, lineHeight = 24.sp, color = IosParityColors.Text)
      Spacer(Modifier.height(16.dp))
      FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        SmallActionButton("上传图片")
        SmallActionButton("路径")
        SmallActionButton("复制原文")
        SmallActionButton("引用原文")
      }
    }
  }
}

@Composable
fun CodeBlock(text: String) {
  Surface(
    modifier = Modifier.fillMaxWidth(),
    shape = RoundedCornerShape(12.dp),
    color = Color.White,
    border = BorderStroke(1.dp, IosParityColors.SurfaceBorder),
  ) {
    Box {
      Text(
        text = text,
        fontFamily = FontFamily.Monospace,
        fontSize = 15.sp,
        lineHeight = 21.sp,
        color = Color.Black,
        modifier = Modifier.padding(14.dp),
      )
      Row(
        modifier = Modifier
          .align(Alignment.TopEnd)
          .padding(8.dp)
          .clip(RoundedCornerShape(8.dp))
          .background(IosParityColors.Background)
          .padding(horizontal = 10.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
      ) {
        Icon(Icons.Default.ContentCopy, contentDescription = "复制", tint = IosParityColors.TextSecondary, modifier = Modifier.size(18.dp))
        Spacer(Modifier.width(4.dp))
        Text("复制", fontSize = 13.sp, color = IosParityColors.TextSecondary, fontWeight = FontWeight.Bold)
      }
    }
  }
}

@Composable
fun EmptyWorkbenchCard(bridgeError: String?) {
  Surface(
    modifier = Modifier.fillMaxWidth(),
    shape = RoundedCornerShape(12.dp),
    color = IosParityColors.Surface,
    border = BorderStroke(1.dp, IosParityColors.SurfaceBorder),
  ) {
    Column(modifier = Modifier.padding(18.dp)) {
      Text("正在等待指令", fontSize = 18.sp, fontWeight = FontWeight.Bold, color = IosParityColors.Text)
      Spacer(Modifier.height(8.dp))
      val detail = bridgeError?.let { "Bridge: $it" } ?: "连接后这里会显示当前请求。"
      Text(detail, fontSize = 14.sp, color = IosParityColors.TextSecondary)
    }
  }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun InputSection(
  value: String,
  predefinedOptions: List<String>,
  selectedOptions: Set<String>,
  onValueChange: (String) -> Unit,
  onOptionClick: (String) -> Unit,
) {
  Spacer(Modifier.height(16.dp))
  OutlinedTextField(
    value = value,
    onValueChange = onValueChange,
    modifier = Modifier.fillMaxWidth(),
    minLines = 3,
    placeholder = { Text("输入回复...") },
  )
  if (predefinedOptions.isNotEmpty()) {
    Spacer(Modifier.height(10.dp))
    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
      predefinedOptions.forEach { option ->
        SmallActionButton(
          text = option,
          selected = selectedOptions.contains(option),
          onClick = { onOptionClick(option) },
        )
      }
    }
  }
}

@Composable
fun SmallActionButton(text: String, selected: Boolean = false, onClick: () -> Unit = {}) {
  Surface(
    modifier = Modifier.clickable(onClick = onClick),
    shape = RoundedCornerShape(8.dp),
    color = if (selected) Color.Black else Color.White,
    border = BorderStroke(1.dp, IosParityColors.SurfaceBorder),
  ) {
    Text(
      text = text,
      modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
      fontSize = 14.sp,
      color = if (selected) Color.White else IosParityColors.Text,
    )
  }
}

@Composable
fun FooterBar(
  voiceState: VoiceInputState,
  onVoiceClick: () -> Unit,
  onGoalClick: () -> Unit,
  onSubmitClick: () -> Unit,
  modifier: Modifier = Modifier,
) {
  Box(modifier = modifier.fillMaxWidth()) {
    Column(
      modifier = Modifier
        .fillMaxWidth()
        .padding(top = 38.dp)
        .background(IosParityColors.Footer)
        .border(width = 0.5.dp, color = IosParityColors.SurfaceBorder)
        .padding(horizontal = 16.dp, vertical = 16.dp),
    ) {
      Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Button(
          modifier = Modifier
            .weight(1f)
            .height(54.dp),
          onClick = onGoalClick,
          colors = ButtonDefaults.buttonColors(containerColor = Color.White, contentColor = IosParityColors.Text),
          shape = RoundedCornerShape(12.dp),
        ) {
          Text("∞", fontSize = 26.sp, fontWeight = FontWeight.Bold)
        }
        Button(
          modifier = Modifier
            .weight(1f)
            .height(54.dp),
          onClick = onSubmitClick,
          colors = ButtonDefaults.buttonColors(containerColor = Color.Black, contentColor = Color.White),
          shape = RoundedCornerShape(12.dp),
        ) {
          Text("确认", fontSize = 18.sp, fontWeight = FontWeight.Bold)
        }
      }
    }
    VoiceHalfCircleDock(
      voiceState = voiceState,
      onClick = onVoiceClick,
      modifier = Modifier
        .align(Alignment.TopCenter)
        .offset(y = 0.dp),
    )
  }
}

@Composable
fun VoiceHalfCircleDock(voiceState: VoiceInputState, onClick: () -> Unit, modifier: Modifier = Modifier) {
  val borderColor = when (voiceState) {
    VoiceInputState.Listening -> IosParityColors.Connected
    VoiceInputState.PermissionDenied, VoiceInputState.Error -> IosParityColors.Warning
    VoiceInputState.Idle -> IosParityColors.SurfaceBorder
  }
  Box(
    modifier = modifier
      .size(width = 118.dp, height = 76.dp)
      .clip(RoundedCornerShape(topStart = 76.dp, topEnd = 76.dp))
      .background(IosParityColors.Footer)
      .border(1.dp, IosParityColors.SurfaceBorder, RoundedCornerShape(topStart = 76.dp, topEnd = 76.dp))
      .clickable(onClick = onClick),
    contentAlignment = Alignment.Center,
  ) {
    Box(
      modifier = Modifier
        .size(56.dp)
        .clip(CircleShape)
        .background(Color.White)
        .border(2.dp, borderColor, CircleShape),
      contentAlignment = Alignment.Center,
    ) {
      Icon(Icons.Default.Mic, contentDescription = "语音输入", tint = IosParityColors.TextSecondary, modifier = Modifier.size(30.dp))
    }
  }
}
