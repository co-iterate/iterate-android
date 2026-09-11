package com.kexin94yyds.iterate.mobile

import android.app.*
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.ServiceCompat
import com.kexin94yyds.iterate.MainActivity
import kotlinx.coroutines.*

object TaskNotifications {
  const val SESSION = "continuous_session"
  const val TASKS = "desktop_tasks"
  fun channels(context: Context) {
    if (Build.VERSION.SDK_INT >= 26) context.getSystemService(NotificationManager::class.java).createNotificationChannels(listOf(
      NotificationChannel(SESSION, "持续会话", NotificationManager.IMPORTANCE_LOW),
      NotificationChannel(TASKS, "电脑消息", NotificationManager.IMPORTANCE_DEFAULT),
    ))
  }
  fun open(context: Context, request: MobileRequest? = null): PendingIntent = PendingIntent.getActivity(context,
    request?.requestId?.hashCode() ?: 0,
    Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
      .putExtra("notification_request_id", request?.requestId).putExtra("notification_project_path", request?.projectPath),
    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
  fun enabled(context: Context) = context.getSharedPreferences("mobile_preferences", Context.MODE_PRIVATE).getBoolean("notifications", true)
  fun showTask(context: Context, request: MobileRequest) {
    if (!enabled(context) || !NotificationManagerCompat.from(context).areNotificationsEnabled()) return
    val preferences = context.getSharedPreferences("mobile_preferences", Context.MODE_PRIVATE)
    val key = "${request.projectPath}:${request.requestId}"
    val seen = preferences.getStringSet("notified_requests", emptySet()).orEmpty()
    if (key in seen) return
    channels(context)
    val note = NotificationCompat.Builder(context, TASKS).setSmallIcon(android.R.drawable.ic_dialog_email)
      .setContentTitle("iterate · 新消息").setContentText("电脑有一条消息等待回复")
      .setContentIntent(open(context, request)).setAutoCancel(true).setOnlyAlertOnce(true)
      .setVisibility(NotificationCompat.VISIBILITY_PRIVATE).build()
    try {
      NotificationManagerCompat.from(context).notify(request.requestId?.hashCode() ?: 2, note)
      preferences.edit().putStringSet("notified_requests", (seen.toList().takeLast(199) + key).toSet()).apply()
    } catch (_: SecurityException) { }
  }
}

class ConnectionService : Service() {
  private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
  private var observer: Job? = null
  override fun onBind(intent: Intent?): IBinder? = null
  override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
    val prefs = getSharedPreferences("mobile_preferences", MODE_PRIVATE)
    if (intent?.action == STOP || !prefs.getBoolean("continuous", false)) {
      prefs.edit().putBoolean("continuous", false).apply()
      ConnectionManager.get(this).setContinuous(false)
      stopForeground(STOP_FOREGROUND_REMOVE); stopSelf()
      return START_NOT_STICKY
    }
    TaskNotifications.channels(this)
    val manager = ConnectionManager.get(this)
    if (manager.paired == null) { stopSelf(); return START_NOT_STICKY }
    showNotification(manager.state.value.state)
    manager.setContinuous(true)
    if (observer == null) observer = scope.launch { manager.state.collect { showNotification(it.state) } }
    return START_STICKY
  }
  private fun showNotification(state: BridgeConnectionState) {
    val stop = PendingIntent.getService(this, 1, Intent(this, ConnectionService::class.java).setAction(STOP), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    val text = when (state) {
      BridgeConnectionState.Connected -> "持续接收电脑消息"
      BridgeConnectionState.WaitingNetwork -> "等待网络恢复"
      BridgeConnectionState.Offline -> "连接已暂停，请打开应用检查"
      else -> "正在连接电脑"
    }
    val notification = NotificationCompat.Builder(this, TaskNotifications.SESSION).setSmallIcon(android.R.drawable.ic_dialog_email)
      .setContentTitle("iterate 持续会话").setContentText(text).setContentIntent(TaskNotifications.open(this))
      .setOngoing(true).setOnlyAlertOnce(true).addAction(0, "停止", stop).build()
    ServiceCompat.startForeground(this, 1, notification,
      if (Build.VERSION.SDK_INT >= 34) ServiceInfo.FOREGROUND_SERVICE_TYPE_REMOTE_MESSAGING else 0)
  }
  override fun onDestroy() { scope.cancel(); ConnectionManager.get(this).setContinuous(false); super.onDestroy() }
  companion object { const val STOP = "iterate.stop_continuous_session" }
}
