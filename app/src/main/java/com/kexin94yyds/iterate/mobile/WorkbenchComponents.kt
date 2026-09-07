package com.kexin94yyds.iterate.mobile

import androidx.compose.foundation.clickable
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.ui.semantics.Role
import androidx.compose.material.icons.filled.Image
import androidx.compose.material.icons.filled.FolderOpen
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.DarkMode
import androidx.compose.material.icons.filled.FormatQuote
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.LightMode
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.NotificationsOff
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

@Composable
fun WorkbenchHeader(
  title: String,
  connectionLabel: String,
  connectionState: BridgeConnectionState,
  notificationsEnabled: Boolean,
  lightAppearance: Boolean,
  onHomeClick: () -> Unit,
  onNotificationClick: () -> Unit,
  onThemeClick: () -> Unit,
  onNewChatClick: () -> Unit,
  onProjectsClick: () -> Unit = {},
) {
  val colors = WorkbenchTheme.colors
  Column {
    BoxWithConstraints(Modifier.fillMaxWidth().padding(horizontal = 7.dp, vertical = 6.dp)) {
      val wrapActions = maxWidth < 336.dp || LocalDensity.current.fontScale > 1.15f
      val actions: @Composable () -> Unit = {
        Row {
          HeaderIconButton(Icons.Default.Home, "打开首页", onHomeClick)
          HeaderIconButton(
            if (notificationsEnabled) Icons.Default.Notifications else Icons.Default.NotificationsOff,
            if (notificationsEnabled) "关闭通知" else "开启通知",
            onNotificationClick,
          )
          HeaderIconButton(
            if (lightAppearance) Icons.Default.DarkMode else Icons.Default.LightMode,
            if (lightAppearance) "切换到深色模式" else "切换到浅色模式",
            onThemeClick,
          )
          HeaderIconButton(Icons.Default.Add, "新建会话", onNewChatClick)
        }
      }
      if (wrapActions) {
        Column {
          ProjectIdentity(title, connectionLabel, connectionState, Modifier.fillMaxWidth().clickable(onClick = onProjectsClick))
          Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.CenterEnd) { actions() }
        }
      } else {
        Row(verticalAlignment = Alignment.CenterVertically) {
          ProjectIdentity(title, connectionLabel, connectionState, Modifier.weight(1f).clickable(onClick = onProjectsClick))
          actions()
        }
      }
    }
    HorizontalDivider(color = colors.border.copy(alpha = 0.7f), thickness = 0.5.dp)
  }
}

@Composable
private fun ProjectIdentity(
  title: String,
  connectionLabel: String,
  connectionState: BridgeConnectionState,
  modifier: Modifier = Modifier,
) {
  val colors = WorkbenchTheme.colors
  Row(modifier.heightIn(min = 48.dp), verticalAlignment = Alignment.CenterVertically) {
    Box(Modifier.size(width = 30.dp, height = 34.dp), contentAlignment = Alignment.CenterStart) {
      InfinityMark(pointSize = 20f, color = colors.text)
    }
    Spacer(Modifier.width(8.dp))
    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
      Row(verticalAlignment = Alignment.CenterVertically) {
        Text(title, fontSize = 14.sp, fontWeight = FontWeight.Bold, color = colors.text,
          maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
        Icon(Icons.Default.ExpandMore, contentDescription = null, tint = colors.secondaryText, modifier = Modifier.size(14.dp))
      }
      Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(5.dp),
        modifier = Modifier.semantics(mergeDescendants = true) { contentDescription = connectionLabel },
      ) {
        val statusColor = when (connectionState) {
          BridgeConnectionState.Connected -> colors.success
          BridgeConnectionState.Connecting -> colors.warning
          BridgeConnectionState.Offline -> colors.error
        }
        Box(Modifier.size(6.dp).clip(CircleShape).background(statusColor))
        Text(connectionLabel, fontSize = 11.sp, color = colors.secondaryText, maxLines = 1)
      }
    }
  }
}

@Composable
private fun HeaderIconButton(icon: ImageVector, label: String, action: () -> Unit) {
  val colors = WorkbenchTheme.colors
  IconButton(onClick = action, modifier = Modifier.size(48.dp)) {
    Box(
      Modifier
        .size(36.dp)
        .clip(CircleShape)
        .background(Brush.verticalGradient(listOf(colors.background, colors.card.copy(alpha = 0.75f))))
        .border(0.5.dp, colors.border.copy(alpha = 0.75f), CircleShape),
      contentAlignment = Alignment.Center,
    ) {
      Icon(icon, contentDescription = label, tint = colors.text, modifier = Modifier.size(18.dp))
    }
  }
}

@Composable
fun MessageCard(request: MobileRequest, onCopy: () -> Unit, onQuote: () -> Unit, onImage: () -> Unit = {}, onPath: () -> Unit = {}) {
  val colors = WorkbenchTheme.colors
  Surface(
    modifier = Modifier.fillMaxWidth(),
    shape = RoundedCornerShape(8.dp),
    color = colors.card,
    border = BorderStroke(1.dp, colors.accent.copy(alpha = 0.2f)),
  ) {
    Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
      request.contextSummary?.let { summary ->
        Text(summary, fontSize = 11.sp, lineHeight = 17.sp, color = colors.secondaryText)
      }
      SelectionContainer { RequestMarkdown(request.message) }
      request.browserAiResponse?.takeIf { it.isNotBlank() && it != request.message }?.let { response ->
        HorizontalDivider(color = colors.border)
        SelectionContainer { RequestMarkdown(response) }
      }
      HorizontalDivider(color = colors.border)
      Row(
        Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
        horizontalArrangement = Arrangement.spacedBy(5.dp),
      ) {
        RequestAction("上传图片", Icons.Default.Image, onImage)
        RequestAction("路径", Icons.Default.FolderOpen, onPath)
        RequestAction("复制原文", Icons.Default.ContentCopy, onCopy)
        RequestAction("引用原文", Icons.Default.FormatQuote, onQuote)
      }
    }
  }
}

@Composable
private fun RequestAction(label: String, icon: ImageVector, onClick: () -> Unit) {
  val colors = WorkbenchTheme.colors
  Box(
    Modifier.heightIn(min = 48.dp).clickable(role = Role.Button, onClick = onClick),
    contentAlignment = Alignment.Center,
  ) {
    Surface(
      shape = RoundedCornerShape(6.dp),
      color = colors.background,
      border = BorderStroke(0.5.dp, colors.border),
    ) {
      Row(
        Modifier.heightIn(min = 32.dp).padding(horizontal = 7.dp, vertical = 4.dp),
        horizontalArrangement = Arrangement.spacedBy(3.dp),
        verticalAlignment = Alignment.CenterVertically,
      ) {
        Icon(icon, contentDescription = null, tint = colors.secondaryText, modifier = Modifier.size(14.dp))
        Text(label, color = colors.text, fontSize = 11.sp)
      }
    }
  }
}

@Composable
fun EmptyWorkbenchState(connectionState: BridgeConnectionState, onRetry: () -> Unit) {
  val colors = WorkbenchTheme.colors
  val message = when (connectionState) {
    BridgeConnectionState.Connected -> "当前没有待处理的 MCP 请求"
    BridgeConnectionState.Connecting -> "正在连接电脑"
    BridgeConnectionState.Offline -> "电脑连接已断开"
  }
  Column(
    modifier = Modifier.fillMaxWidth().padding(vertical = 56.dp),
    horizontalAlignment = Alignment.CenterHorizontally,
    verticalArrangement = Arrangement.spacedBy(4.dp),
  ) {
    Text(message, fontSize = 13.sp, color = colors.secondaryText)
    TextButton(onClick = onRetry, enabled = connectionState != BridgeConnectionState.Connecting) {
      Text(
        if (connectionState == BridgeConnectionState.Connected) "重新尝试同步" else "重新连接",
        fontSize = 12.sp,
        color = if (connectionState == BridgeConnectionState.Connecting) colors.secondaryText else colors.accent,
      )
    }
  }
}
