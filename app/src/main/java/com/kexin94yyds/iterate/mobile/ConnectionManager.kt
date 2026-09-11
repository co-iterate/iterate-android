package com.kexin94yyds.iterate.mobile

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

class ConnectionManager private constructor(context: Context) {
  private val app = context.applicationContext
  private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
  private val store = DeviceCredentialStore(app)
  private val network = app.getSystemService(ConnectivityManager::class.java)
  private var job: Job? = null
  private var replyJob: Job? = null
  private var visible = false
  private var continuous = false
  private var route: ActiveProject? = null
  private var terminalFailure = false
  var client: BridgeClient? = null
    private set
  var paired: PairedConnection? = null
    private set
  data class Snapshot(val state: BridgeConnectionState = BridgeConnectionState.Unpaired, val request: MobileRequest? = null, val error: String? = null, val replyStatus: String? = null, val pendingReply: Boolean = false)
  private val mutable = MutableStateFlow(Snapshot())
  val state: StateFlow<Snapshot> = mutable
  private val callback = object : ConnectivityManager.NetworkCallback() {
    override fun onAvailable(value: Network) { scope.launch { ensureConnection() } }
    override fun onLost(value: Network) { scope.launch { if (!hasNetwork()) { stopSocket(); mutable.value = mutable.value.copy(state = BridgeConnectionState.WaitingNetwork) } } }
    override fun onCapabilitiesChanged(value: Network, capabilities: NetworkCapabilities) { scope.launch { ensureConnection() } }
  }
  init {
    runCatching { store.load() }.onSuccess { paired = it; client = it?.client() }
      .onFailure { mutable.value = Snapshot(error = "设备凭据无法读取，请重新配对") }
    if (runCatching { store.readSecret("pending_reply") }.getOrNull() != null) mutable.value = mutable.value.copy(pendingReply = true, replyStatus = "有待确认的回复，连接后继续发送")
    network.registerDefaultNetworkCallback(callback)
  }
  private fun hasNetwork(): Boolean = network.activeNetwork != null
  fun setVisible(value: Boolean) { visible = value; if (value) ensureConnection() else if (!continuous) stopSocket() }
  fun setContinuous(value: Boolean) { continuous = value; if (value) ensureConnection() else if (!visible) stopSocket() }
  fun selectRoute(project: ActiveProject): Boolean { route = project; return client?.syncProject(project) == true }
  fun reconnect() { terminalFailure = false; stopSocket(); ensureConnection() }
  fun install(connection: PairedConnection) {
    store.save(connection)
    stopSocket(); route = null; paired = connection; client = connection.client(); terminalFailure = false
    mutable.value = mutable.value.copy(state = BridgeConnectionState.Connecting, request = null, error = null)
    ensureConnection()
  }
  fun forget() {
    stopSocket(); route = null; store.clear(); paired = null; client = null; terminalFailure = false
    mutable.value = mutable.value.copy(state = BridgeConnectionState.Unpaired, request = null, error = null)
  }
  private fun stopSocket() {
    job?.cancel(); job = null
    replyJob?.cancel(); replyJob = null
    if (paired != null) mutable.value = mutable.value.copy(state = BridgeConnectionState.Offline)
  }
  private fun ensureConnection() {
    if ((!visible && !continuous) || terminalFailure || job?.isActive == true) return
    val bridge = client ?: return
    if (!hasNetwork()) { mutable.value = mutable.value.copy(state = BridgeConnectionState.WaitingNetwork); return }
    job = scope.launch {
      bridge.events().collect { event ->
        when (event) {
          is BridgeEvent.Connection -> {
            mutable.value = mutable.value.copy(state = event.state, error = event.error)
            if (event.state == BridgeConnectionState.Connected) { route?.let { bridge.syncProject(it) }; flushReply() }

          }
          is BridgeEvent.RequestReceived -> {
            val previous = mutable.value.request
            mutable.value = mutable.value.copy(request = event.request)
            if (!visible && previous?.requestId != event.request.requestId) TaskNotifications.showTask(app, event.request)
          }
        }
      }
      terminalFailure = true
    }
  }
  fun queueReply(payload: org.json.JSONObject): Boolean {
    val identity = paired ?: return false
    if (mutable.value.pendingReply) return false
    val operation = java.util.UUID.randomUUID().toString()
    payload.put("operation_id", operation)
    val record = org.json.JSONObject().put("base", identity.baseUrl).put("identity", identityDigest(identity))
      .put("payload", payload)
    try { store.writeSecret("pending_reply", record.toString()) }
    catch (_: Exception) { mutable.value = mutable.value.copy(replyStatus = "无法保存回复，内容仍在输入框中"); return false }
    mutable.value = mutable.value.copy(pendingReply = true, replyStatus = "回复已保存，等待电脑确认")
    flushReply()
    return true
  }
  fun discardPendingReply() {
    replyJob?.cancel(); replyJob = null; store.removeSecret("pending_reply")
    mutable.value = mutable.value.copy(pendingReply = false, replyStatus = "已放弃待发送回复，输入内容保留")
  }
  private fun identityDigest(identity: PairedConnection): String = java.security.MessageDigest.getInstance("SHA-256")
    .digest((identity.deviceId + ":" + identity.token).toByteArray()).joinToString("") { "%02x".format(it) }
  private fun flushReply() {
    if (replyJob?.isActive == true || !mutable.value.pendingReply || mutable.value.state != BridgeConnectionState.Connected) return
    val identity = paired ?: return
    val bridge = client ?: return
    replyJob = scope.launch {
      try {
        val record = org.json.JSONObject(store.readSecret("pending_reply") ?: return@launch)
        if (record.optString("base") != identity.baseUrl || record.optString("identity") != identityDigest(identity)) {
          mutable.value = mutable.value.copy(replyStatus = "待发送回复属于之前的配对，未发送到新电脑")
          return@launch
        }
        val payload = record.getJSONObject("payload")
        var attempt = 0
        while (isActive) {
          try {
            val receipt = bridge.sendReply(payload)
            require(receipt.optString("operation_id") == payload.getString("operation_id"))
            when (receipt.optString("status")) {
              "delivered" -> {
                store.removeSecret("pending_reply")
                mutable.value = mutable.value.copy(pendingReply = false, replyStatus = "电脑已收到回复")
              }
              "rejected" -> mutable.value = mutable.value.copy(replyStatus = "电脑已拒绝回复，原请求可能已结束。请检查后放弃待发送回复")
              else -> mutable.value = mutable.value.copy(replyStatus = "电脑尚不能确认是否已处理，请检查电脑后再决定；不会重复执行")
            }
            return@launch
          } catch (cancelled: CancellationException) { throw cancelled }
          catch (_: BridgeClient.ReplyUnsupported) { mutable.value = mutable.value.copy(replyStatus = "电脑版本不支持回复确认，请更新电脑端；回复已保留"); return@launch }
          catch (_: BridgeClient.ReplyUnauthorized) { mutable.value = mutable.value.copy(replyStatus = "配对已失效，回复已保留"); return@launch }
          catch (_: BridgeClient.ReplyRejected) { mutable.value = mutable.value.copy(replyStatus = "电脑拒绝了这次回复，请检查原请求；回复已保留"); return@launch }
          catch (_: java.io.IOException) {
            mutable.value = mutable.value.copy(replyStatus = "尚未收到电脑确认，将自动重试同一回复")
            delay(minOf(30_000L, 1_000L shl attempt.coerceAtMost(5))); attempt++
          }
        }
      } catch (cancelled: CancellationException) { throw cancelled }
      catch (_: Exception) { mutable.value = mutable.value.copy(replyStatus = "待发送回复无法读取或确认，请保留内容并检查电脑") }
    }
  }
  companion object {
    @Volatile private var instance: ConnectionManager? = null
    fun get(context: Context): ConnectionManager = instance ?: synchronized(this) {
      instance ?: ConnectionManager(context).also { instance = it }
    }
  }
}
