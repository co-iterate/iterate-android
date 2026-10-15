package com.kexin94yyds.iterate.mobile

import com.kexin94yyds.iterate.R
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.ArrowDropDown
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.CheckBox
import androidx.compose.material.icons.filled.CheckBoxOutlineBlank
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
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
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
  onProjectClick: () -> Unit,
  requestCount: Int,
  request: MobileRequest? = null,
) {
  Column(
    modifier = Modifier
      .fillMaxWidth()
      .background(IosParityColors.Background)
      .border(width = 0.5.dp, color = computerPlatformColor(request?.sourceComputerPlatform))
      .padding(horizontal = 12.dp, vertical = 10.dp),
  ) {
    Row(verticalAlignment = Alignment.CenterVertically) {
      Image(
        painter = painterResource(R.drawable.iterate_logo),
        contentDescription = "iterate",
        modifier = Modifier.size(30.dp),
      )
      Spacer(Modifier.width(10.dp))
      Column(modifier = Modifier.weight(1f).clickable(onClick = onProjectClick)) {
        Text(
          text = "$title  ▾" + if (requestCount > 1) "  $requestCount" else "",
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
        icon = if (lightAppearance) Icons.Default.DarkMode else Icons.Default.LightMode,
        label = "Theme",
        action = onThemeClick,
      )
    }
    Row(verticalAlignment = Alignment.CenterVertically) {
      Text(
        text = "● $connectionLabel",
        fontSize = 12.sp,
        color = if (connectionState == BridgeConnectionState.Connected) IosParityColors.Connected else IosParityColors.Warning,
        modifier = Modifier.weight(1f),
      )
      HeaderIconButton(
        icon = if (notificationsEnabled) Icons.Default.Notifications else Icons.Default.NotificationsOff,
        label = "Notifications",
        action = onNotificationClick,
      )
      HeaderIconButton(Icons.Default.Add, "New chat", onNewChatClick)
    }
  }
}

@Composable
fun HeaderIconButton(icon: ImageVector, label: String, action: () -> Unit) {
  Box(
    modifier = Modifier
      .padding(start = 6.dp)
      .size(48.dp)
      .clip(CircleShape)
      .background(IosParityColors.IconCircle)
      .clickable(onClick = action),
    contentAlignment = Alignment.Center,
  ) {
    Icon(icon, contentDescription = label, tint = IosParityColors.Text, modifier = Modifier.size(22.dp))
  }
}

@Composable
internal fun computerPlatformColor(platform: SourceComputerPlatform?): Color = when (platform) {
  SourceComputerPlatform.Windows -> Color(0xFF2563EB)
  SourceComputerPlatform.Mac -> Color(0xFF8B5CF6)
  null -> IosParityColors.SurfaceBorder
}

internal fun requestKindColor(origin: RequestOrigin): Color =
  when (origin) {
    RequestOrigin.Native -> Color(0xFFF59E0B)
    RequestOrigin.Mcp -> Color(0xFF2563EB)
    RequestOrigin.Mirror -> Color(0xFF8B5CF6)
  }

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun MessageCard(request: MobileRequest, onImageClick: (MobileImage) -> Unit) {
  Surface(
    modifier = Modifier.fillMaxWidth(),
    shape = RoundedCornerShape(12.dp),
    color = IosParityColors.Surface,
    border = BorderStroke(1.dp, requestKindColor(request.origin)),
  ) {
    Column(modifier = Modifier.padding(16.dp)) {
      if (request.isMarkdown) {
        val visibleMessage = BridgeJsonParser.messageWithoutImages(request.message)
        MarkdownMessage(visibleMessage.ifBlank { "这条请求包含图片" })
      } else {
        Text(request.message, fontSize = 16.sp, lineHeight = 22.sp, color = IosParityColors.Text)
      }
      request.images.forEachIndexed { index, image ->
        Spacer(Modifier.height(6.dp))
        Button(
          onClick = { onImageClick(image) },
          modifier = Modifier.fillMaxWidth(),
          colors = ButtonDefaults.buttonColors(
            containerColor = IosParityColors.Background,
            contentColor = IosParityColors.Text,
          ),
          shape = RoundedCornerShape(8.dp),
        ) {
          Text("查看图片${if (request.images.size > 1) " ${index + 1}" else ""} · ${image.alt}")
        }
      }
      Spacer(Modifier.height(8.dp))
      if (!request.browserAiResponse.isNullOrBlank()) {
        CodeBlock(text = request.browserAiResponse)
        Spacer(Modifier.height(14.dp))
      }
    }
  }
}

@Composable
fun CodeBlock(text: String) {
  Surface(
    modifier = Modifier.fillMaxWidth(),
    shape = RoundedCornerShape(12.dp),
    color = IosParityColors.Background,
    border = BorderStroke(1.dp, IosParityColors.SurfaceBorder),
  ) {
    Box {
      Text(
        text = text,
        fontFamily = FontFamily.Monospace,
        fontSize = 15.sp,
        lineHeight = 21.sp,
        color = IosParityColors.Text,
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
  quickTemplates: List<QuickTemplate>,
  templateRefreshing: Boolean,
  templateNotice: String?,
  onValueChange: (String) -> Unit,
  onOptionClick: (String) -> Unit,
  onInsertTemplate: (QuickTemplate) -> Unit,
  onRefreshTemplates: () -> Unit,
  readOnly: Boolean = false,
) {
  var templatesExpanded by remember { mutableStateOf(false) }
  Spacer(Modifier.height(8.dp))
  OutlinedTextField(
    value = value,
    onValueChange = onValueChange,
    modifier = Modifier.fillMaxWidth(),
    minLines = 3,
    readOnly = readOnly,
    placeholder = { Text("输入回复...") },
  )
  if (predefinedOptions.isNotEmpty()) {
    Spacer(Modifier.height(6.dp))
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
      predefinedOptions.forEach { option ->
        SmallActionButton(
          text = option,
          selected = selectedOptions.contains(option),
          enabled = !readOnly,
          onClick = { if(!readOnly)onOptionClick(option) },
        )
      }
    }
  }
  Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
    TextButton(onClick = { templatesExpanded = !templatesExpanded }, modifier = Modifier.weight(1f)) {
      Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Icon(
          imageVector = Icons.Filled.ArrowDropDown,
          contentDescription = if (templatesExpanded) "收起快捷模板" else "展开快捷模板",
          modifier = Modifier.size(20.dp).rotate(if (templatesExpanded) 0f else -90f),
          tint = IosParityColors.TextSecondary,
        )
        Spacer(Modifier.width(4.dp))
        Text("快捷模板 (${quickTemplates.size})", fontSize = 13.sp, color = IosParityColors.TextSecondary)
      }
    }
    TextButton(onClick = onRefreshTemplates, enabled = !templateRefreshing) {
      Text(if (templateRefreshing) "更新中…" else "更新")
    }
  }
  if (templatesExpanded && quickTemplates.isNotEmpty()) {
    FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
      quickTemplates.forEach { template ->
        Surface(
          shape = RoundedCornerShape(8.dp),
          color = IosParityColors.Background,
          border = BorderStroke(1.dp, IosParityColors.SurfaceBorder),
          modifier = Modifier.heightIn(min = 40.dp).clickable { if(!readOnly)onInsertTemplate(template) },
        ) {
          Text(template.name, fontSize = 14.sp, color = IosParityColors.Text,
            modifier = Modifier.padding(horizontal = 12.dp, vertical = 9.dp))
        }
      }
    }
  }
  if (templateNotice != null) Text(templateNotice, fontSize = 12.sp, color = IosParityColors.Warning)
}

@Composable
fun SmallActionButton(text: String, selected: Boolean = false, enabled: Boolean = true, onClick: () -> Unit = {}) {
  Surface(
    modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)
      .toggleable(value = selected, enabled = enabled, role = Role.Checkbox, onValueChange = { onClick() }),
    shape = RoundedCornerShape(8.dp),
    color = if (selected) IosParityColors.PrimaryButton else IosParityColors.Background,
    border = BorderStroke(1.dp, IosParityColors.SurfaceBorder),
  ) {
    Row(Modifier.padding(horizontal = 12.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
      Icon(
        imageVector = if (selected) Icons.Default.CheckBox else Icons.Default.CheckBoxOutlineBlank,
        contentDescription = null,
        tint = if (selected) IosParityColors.OnPrimaryButton else IosParityColors.Text,
        modifier = Modifier.size(20.dp),
      )
      Spacer(Modifier.width(8.dp))
      Text(
        text = text,
        fontSize = 14.sp,
        color = if (selected) IosParityColors.OnPrimaryButton else IosParityColors.Text,
      )
    }
  }
}

@Composable
fun FooterBar(
  voiceState: VoiceInputState,
  onVoiceClick: () -> Unit,
  onContinueClick: () -> Unit,
  onSubmitClick: () -> Unit,
  enabled: Boolean,
  modifier: Modifier = Modifier,
  continueEnabled: Boolean = enabled,
  submitLabel: String = "确认",
  continueLabel: String = "继续",
) {
  Box(modifier = modifier.fillMaxWidth()) {
    Column(
      modifier = Modifier
        .fillMaxWidth()
        .padding(top = 0.dp)
        .background(IosParityColors.Footer)
        .border(width = 0.5.dp, color = IosParityColors.SurfaceBorder)
        .padding(horizontal = 16.dp, vertical = 4.dp),
    ) {
      Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Button(
          modifier = Modifier
            .weight(1f)
            .height(40.dp),
          onClick = onContinueClick,
          enabled = continueEnabled,
          colors = ButtonDefaults.buttonColors(containerColor = IosParityColors.Background, contentColor = IosParityColors.Text),
          shape = RoundedCornerShape(8.dp),
        ) {
          Text(continueLabel, fontSize = 14.sp, fontWeight = FontWeight.Bold)
        }
        Button(
          modifier = Modifier
            .weight(1f)
            .height(40.dp),
          onClick = onSubmitClick,
          enabled = enabled,
          colors = ButtonDefaults.buttonColors(containerColor = IosParityColors.PrimaryButton, contentColor = IosParityColors.OnPrimaryButton),
          shape = RoundedCornerShape(8.dp),
        ) {
          Text(submitLabel, fontSize = 14.sp, fontWeight = FontWeight.Bold)
        }
      }
    }
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
      .size(56.dp)
      .clip(CircleShape)
      .background(IosParityColors.Footer)
      .border(1.dp, IosParityColors.SurfaceBorder, CircleShape)
      .clickable(onClick = onClick),
    contentAlignment = Alignment.Center,
  ) {
    Box(
      modifier = Modifier
        .size(56.dp)
        .clip(CircleShape)
        .background(IosParityColors.Background)
        .border(2.dp, borderColor, CircleShape),
      contentAlignment = Alignment.Center,
    ) {
      Icon(Icons.Default.Mic, contentDescription = "语音输入", tint = IosParityColors.TextSecondary, modifier = Modifier.size(30.dp))
    }
  }
}
