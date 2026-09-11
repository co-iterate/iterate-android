package com.kexin94yyds.iterate.mobile

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import com.kexin94yyds.iterate.BuildConfig
import kotlinx.coroutines.launch

@Composable
fun ConnectionSettings(initialPayload: String = "", onBack: () -> Unit) {
  val context = LocalContext.current
  val manager = remember { ConnectionManager.get(context) }
  val snapshot by manager.state.collectAsState()
  val preferences = remember { context.getSharedPreferences("mobile_preferences", Context.MODE_PRIVATE) }
  var content by remember { mutableStateOf(initialPayload) }
  var busy by remember { mutableStateOf(false) }
  var error by remember { mutableStateOf<String?>(null) }
  var continuous by remember { mutableStateOf(preferences.getBoolean("continuous", false)) }
  val scope = rememberCoroutineScope()
  val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
    if (!granted) error = "通知未开启，可在系统设置中允许电脑消息提醒"
  }
  LaunchedEffect(initialPayload) { if (initialPayload.isNotBlank()) content = initialPayload }
  Column(Modifier.fillMaxSize().safeDrawingPadding().verticalScroll(rememberScrollState()).imePadding().padding(24.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
    Text("连接电脑", style = MaterialTheme.typography.headlineSmall)
    Text(manager.paired?.let { "已配对：${it.desktopName}" } ?: "在电脑 iterate 中打开手机连接，复制配对链接到这里。")
    Text(WorkbenchUiState(connectionState = snapshot.state).connectionLabel)
    OutlinedTextField(value = content, onValueChange = { content = it }, label = { Text("配对链接") }, modifier = Modifier.fillMaxWidth().testTag("pairing-link"), minLines = 2, maxLines = 4)
    Button(enabled = !busy && content.isNotBlank(), onClick = {
      busy = true; error = null
      scope.launch {
        try {
          val offer = PairingParser.parse(content, allowDebugLoopback = BuildConfig.DEBUG)
          val connection = PairingRepository().claim(offer, DeviceCredentialStore(context).deviceId, "${Build.MANUFACTURER} ${Build.MODEL}")
          manager.install(connection); content = ""
          if (Build.VERSION.SDK_INT >= 33) permission.launch(Manifest.permission.POST_NOTIFICATIONS)
        } catch (_: kotlinx.coroutines.CancellationException) { throw kotlinx.coroutines.CancellationException() }
        catch (failure: Exception) { error = when (failure) {
          is java.io.IOException -> "无法连接电脑，请检查网络后重试"
          else -> failure.message?.takeIf { it.length < 120 && !it.contains("http") } ?: "配对内容无效，请重新复制电脑上的链接"
        } } finally { busy = false }
      }
    }, modifier = Modifier.testTag("pairing-connect")) { Text(if (busy) "配对中…" else "配对") }
    error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
    HorizontalDivider()
    Text("持续会话", style = MaterialTheme.typography.titleMedium)
    Text("开启后，在后台继续接收电脑消息，系统会显示常驻通知。可从通知中停止。")
    Switch(checked = continuous, enabled = manager.paired != null, onCheckedChange = { enabled ->
      preferences.edit().putBoolean("continuous", enabled).apply()
      continuous = enabled
      if (enabled) {
        if (Build.VERSION.SDK_INT >= 33) permission.launch(Manifest.permission.POST_NOTIFICATIONS)
        try { ContextCompat.startForegroundService(context, Intent(context, ConnectionService::class.java)) }
        catch (_: Exception) { continuous = false; preferences.edit().putBoolean("continuous", false).apply(); error = "持续会话未能启动，请回到应用重试" }
      } else {
        context.stopService(Intent(context, ConnectionService::class.java)); manager.setContinuous(false)
      }
    }, modifier = Modifier.testTag("continuous-session"))
    Text("锁屏省电或系统停止应用可能暂停接收。重新打开应用会恢复连接；厂商推送尚未配置。", style = MaterialTheme.typography.bodySmall)
    if (snapshot.pendingReply) {
      Text(snapshot.replyStatus ?: "有一条待确认回复")
      TextButton(onClick = { manager.discardPendingReply() }) { Text("放弃待发送回复") }
    }
    TextButton(onClick = { manager.reconnect() }, enabled = manager.paired != null) { Text("重新连接") }
    TextButton(onClick = {
      context.stopService(Intent(context, ConnectionService::class.java)); preferences.edit().putBoolean("continuous", false).apply(); continuous = false
      manager.forget()
    }, enabled = manager.paired != null) { Text("解除本机配对") }
    Button(onClick = onBack) { Text("返回消息") }
  }
}
