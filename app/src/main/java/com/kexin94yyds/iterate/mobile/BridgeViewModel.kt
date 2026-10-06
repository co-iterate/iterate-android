package com.kexin94yyds.iterate.mobile

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.UUID
import org.json.JSONObject
import java.nio.charset.StandardCharsets

class BridgeViewModel(
  private val store: PairingStore,
  private val bridgeClient: BridgeClient = BridgeClient(),
) : ViewModel() {
  var state by mutableStateOf(WorkbenchUiState())
    private set
  private var pairing: SavedPairing? = store.load()
  private var connectionJob: Job? = null
  private var templateRefreshJob: Job? = null
  private var activeTemplateSyncReason: String? = null
  private var imageJob: Job? = null
  private var imageGeneration: Long = 0
  var previewImage by mutableStateOf<Bitmap?>(null)
    private set
  var previewSvg by mutableStateOf<String?>(null)
    private set
  var imageLoading by mutableStateOf(false)
    private set
  var imageError by mutableStateOf<String?>(null)
    private set

  init {
    if (pairing != null) {
      state = state.copy(paired = true,currentDeviceId=pairing?.deviceId)
      connect()
    } else {
      state = state.copy(connectionState = BridgeConnectionState.Offline)
    }
  }

  fun showHome() { state = state.copy(route = WorkbenchRoute.Home) }
  fun showConversation() { state = state.copy(route = WorkbenchRoute.Conversation) }
  fun setUserInput(value: String) {
    if (state.request == null || state.closedDraftKey!=null || state.sending || (state.request?.origin==RequestOrigin.Native&&state.drafts[state.request?.requestId to state.request?.projectPath]?.deliveryUnknown==true)) return
    state = state.copy(userInput = value)
  }
  fun insertQuickTemplate(template: QuickTemplate) { if(state.closedDraftKey==null&&!state.sending&&(state.request?.origin!=RequestOrigin.Native||state.drafts[state.request?.requestId to state.request?.projectPath]?.deliveryUnknown!=true))state = state.insertQuickTemplate(template) }

  fun refreshQuickTemplates() {
    if (state.templateRefreshing) return
    if (state.connectionState != BridgeConnectionState.Connected) {
      state = state.copy(templateRefreshing = false, templateNotice = "连接电脑后才能更新快捷模板")
      return
    }
    val previousReason = activeTemplateSyncReason
    val syncReason = "android_template_refresh:${UUID.randomUUID()}"
    activeTemplateSyncReason = syncReason
    state = state.copy(templateRefreshing = true, templateNotice = null)
    if (!bridgeClient.requestQuickTemplateSync(syncReason)) {
      activeTemplateSyncReason = previousReason
      state = state.copy(templateRefreshing = false, templateNotice = "更新请求未发出，请重试")
      return
    }
    templateRefreshJob?.cancel()
    templateRefreshJob = viewModelScope.launch {
      delay(8_000)
      if (state.templateRefreshing) state = state.copy(templateRefreshing = false, templateNotice = "更新超时，请重试")
    }
  }
  fun setPairingInput(value: String) { state = state.copy(pairingInput = value) }
  fun selectRequest(request: MobileRequest) {
    if (!state.requests.contains(request)) return
    closeImage()
    state = state.selectActiveRequest(request)
    state.timelineRouteFor(request)?.let { bridgeClient.requestTimeline(it.first, it.second) }
  }
  fun moveTimeline(position: Int) { state = state.moveTimeline(position) }
  fun selectNativeHistory(session: NativeHistorySession) {
    if (session !in state.nativeHistorySessions) return
    state = state.selectNativeHistory(session)
    if (state.connectionState == BridgeConnectionState.Connected)
      bridgeClient.requestTimeline(session.routeId, session.projectPath)
  }

  fun openImage(image: MobileImage) {
    val currentPairing = pairing ?: return
    val request = state.request ?: return
    if (image !in request.images) return
    val requestId = request.requestId
    val projectPath = request.projectPath
    imageJob?.cancel()
    val generation = ++imageGeneration
    previewImage = null
    previewSvg = null
    imageError = null
    imageLoading = true
    imageJob = viewModelScope.launch {
      try {
        val bytes = bridgeClient.loadImage(currentPairing, image.url)
        val svg = withContext(Dispatchers.Default) {
          val prefix = String(bytes, 0, minOf(bytes.size, 4096), StandardCharsets.UTF_8)
          if (Regex("<svg(?:\\s|>)", RegexOption.IGNORE_CASE).containsMatchIn(prefix)) {
            String(bytes, StandardCharsets.UTF_8)
          } else null
        }
        if (svg != null) {
          if (generation == imageGeneration && pairing == currentPairing && state.request?.requestId == requestId &&
            state.request?.projectPath == projectPath) previewSvg = svg
          return@launch
        }
        val bitmap = withContext(Dispatchers.Default) {
          val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
          BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
          if (bounds.outWidth <= 0 || bounds.outHeight <= 0) throw IllegalArgumentException("此图片格式暂不支持")
          var sample = 1
          while (bounds.outWidth / sample > 2048 || bounds.outHeight / sample > 2048) sample *= 2
          BitmapFactory.decodeByteArray(bytes, 0, bytes.size,
            BitmapFactory.Options().apply { inSampleSize = sample })
            ?: throw IllegalArgumentException("图片无法解码")
        }
        if (generation == imageGeneration && pairing == currentPairing && state.request?.requestId == requestId &&
          state.request?.projectPath == projectPath) previewImage = bitmap
      } catch (cancelled: CancellationException) {
        throw cancelled
      } catch (error: Exception) {
        if (generation == imageGeneration) imageError = error.message ?: "图片无法打开"
      } finally {
        if (generation == imageGeneration) imageLoading = false
      }
    }
  }

  fun closeImage() {
    imageGeneration++
    imageJob?.cancel()
    imageJob = null
    previewImage = null
    previewSvg = null
    imageLoading = false
    imageError = null
  }

  fun toggleOption(option: String) {
    if (state.closedDraftKey!=null || state.sending || (state.request?.origin==RequestOrigin.Native&&state.drafts[state.request?.requestId to state.request?.projectPath]?.deliveryUnknown==true) || state.request?.predefinedOptions?.contains(option) != true) return
    val next = state.selectedOptions.toMutableSet()
    if (!next.add(option)) next.remove(option)
    state = state.copy(selectedOptions = next)
  }

  fun importPairing(raw: String) {
    if (state.pairingBusy) return
    state = state.copy(pairingBusy = true, bridgeError = null, actionNotice = null)
    viewModelScope.launch {
      try {
        val payload = AndroidPairingPayload.parse(raw)
        val claimed = bridgeClient.claim(payload, store.deviceId())
        store.save(claimed)
        pairing = claimed
        state = state.copy(paired = true, pairingBusy = false, pairingInput = "", bridgeError = null, route = WorkbenchRoute.Home, currentDeviceId=claimed.deviceId,
          nativeHistorySessions=emptyList(), timelines=emptyMap(), viewedTimelineRoute=null)
        connect()
      } catch (error: Exception) {
        state = state.copy(pairingBusy = false, bridgeError = error.message ?: "配对失败")
      }
    }
  }

  fun forgetPairing() {
    closeImage()
    templateRefreshJob?.cancel()
    activeTemplateSyncReason = null
    connectionJob?.cancel()
    pairing = null
    store.clear()
    state = state.clearRemoteRequests(BridgeConnectionState.Offline).copy(route=WorkbenchRoute.Home,paired=false,currentDeviceId=null,
      nativeHistorySessions=emptyList(), timelines=emptyMap(), viewedTimelineRoute=null)
  }

  fun sendSubmit() { sendAction("submit") }
  fun sendContinue() { sendAction("continue") }
  fun sendGoal() { sendAction("goal") }
  fun setVoiceState(voiceState: VoiceInputState) { state = state.copy(voiceState = voiceState) }

  fun acceptVoiceTranscript(transcript: String) {
    if (state.request == null || state.closedDraftKey!=null || state.sending || (state.request?.origin==RequestOrigin.Native&&state.drafts[state.request?.requestId to state.request?.projectPath]?.deliveryUnknown==true)) {
      state = state.copy(voiceState = VoiceInputState.Idle)
      return
    }
    val cleanTranscript = transcript.trim()
    if (cleanTranscript.isEmpty()) {
      state = state.copy(voiceState = VoiceInputState.Idle)
      return
    }
    val nextInput = listOf(state.userInput, cleanTranscript)
      .filter { it.isNotBlank() }
      .joinToString(separator = "\n")
    state = state.copy(userInput = nextInput, voiceState = VoiceInputState.Idle)
  }

  fun toggleNotifications() { state = state.copy(notificationsEnabled = !state.notificationsEnabled) }
  fun toggleTheme() { state = state.copy(lightAppearance = !state.lightAppearance) }

  fun openNewChat() {
    if (state.request?.origin == RequestOrigin.Mirror || state.closedDraftKey?.let { state.drafts[it]?.origin } == RequestOrigin.Mirror) { state = state.copy(actionNotice = "跨设备请求仅支持文字和选项"); return }
    val current = pairing ?: return
    viewModelScope.launch {
      if (!bridgeClient.openCodexChat(current, state.request?.projectPath)) {
        state = state.copy(actionNotice = "未能在电脑上打开新会话")
      }
    }
  }

  fun selectClosedDraft(key:Pair<String,String>){state=state.selectClosedDraft(key)}
  fun queryOriginalReply(key:Pair<String,String> = state.closedDraftKey ?: (state.request?.requestId.orEmpty() to state.request?.projectPath.orEmpty())) {
    val reason=state.queryDisabledReason(key)
    if(reason!=null){state=state.copy(queryNotices=state.queryNotices+(key to reason));return}
    val original=state.drafts[key]?.unconfirmedAction ?: return
    val current=pairing ?: return
    val payload=if(original.origin==RequestOrigin.Native)BridgeJsonParser.buildNativeQuery(original.payload)else original.payload
    state=state.copy(queryPendingKey=key,queryNotices=state.queryNotices+(key to "查询处理中"))
    viewModelScope.launch {
      val receipt=bridgeClient.sendAction(current,payload,key.first,key.second,original.clientActionId,original.action,original.origin)
      if(pairing!=current||state.queryPendingKey!=key)return@launch
      val notice=when{receipt.delivered->when(receipt.resultKind){"saved"->"电脑已保存";"cli_received"->"CLI 已接收";"mac_accepted"->"Mac 已接收原回复";"mirror_closed"->"手机已隐藏该镜像，Mac 请求继续等待";else->"电脑已收到原回复"};receipt.authoritativeRejection->"原回复未执行";else->receipt.error ?: "结果未知"}
      val confirmed=receipt.delivered||receipt.authoritativeRejection
      val closed=key in state.closedRequestKeys
      var next=state.copy(queryPendingKey=null,queryNotices=state.queryNotices+(key to notice),queryConfirmedKeys=if(confirmed)state.queryConfirmedKeys+key else state.queryConfirmedKeys)
      if(receipt.delivered && original.origin==RequestOrigin.Mirror) next=next.copy(terminalMirrorRequestIds=next.terminalMirrorRequestIds+key.first)
      if(!closed&&confirmed){
        if(receipt.delivered)next=next.deliveredRequest(key.first,key.second,receipt.resultKind)
        else {
          val draft=next.drafts[key]
          if(draft!=null)next=next.copy(drafts=next.drafts+(key to draft.copy(deliveryUnknown=false,unconfirmedAction=null)),actionNotice=notice)
        }
      }
      state=next
    }
  }
  fun closedDraftCopy():String? {
    val key=state.closedDraftKey ?: return null
    if(key !in state.queryConfirmedKeys)return null
    val draft=state.drafts[key] ?: return null
    val options=draft.requestSnapshot?.predefinedOptions?.filter{it in draft.selectedOptions} ?: draft.selectedOptions.toList()
    return listOf(options.joinToString("；").takeIf{it.isNotEmpty()}?.let{"选中的选项: $it"},draft.text.takeIf{it.isNotEmpty()}).filterNotNull().joinToString("\n\n")
  }

  private fun connect() {
    connectionJob?.cancel()
    val current = pairing ?: return
    connectionJob = viewModelScope.launch {
      while (isActive && pairing == current) {
        activeTemplateSyncReason = null
        state = state.clearRemoteRequests(BridgeConnectionState.Connecting)
        try {
          bridgeClient.requests(current).collect { event ->
            when (event) {
              is BridgeEvent.Connected -> {
                activeTemplateSyncReason = event.templateSyncReason
                state = state.copy(connectionState = BridgeConnectionState.Connected, bridgeError = null)
                state.viewedTimelineRoute?.let { bridgeClient.requestTimeline(it.first, it.second) }
              }
              is BridgeEvent.QuickTemplates -> {
                if (event.snapshot.syncReason == activeTemplateSyncReason) {
                  templateRefreshJob?.cancel()
                  state = state.applyQuickTemplateSnapshot(event.snapshot, activeTemplateSyncReason)
                }
              }
              is BridgeEvent.Request -> {
                val request = event.request
                if (request.requestId.isNullOrBlank() || (request.origin != RequestOrigin.Mirror && request.projectPath.isNullOrBlank()) || request.projectPath == "main_page") return@collect
                state = state.receiveRequest(request)
                state.timelineRouteFor(request)?.let { route ->
                  if (state.timelines[route] == null)
                    bridgeClient.requestTimeline(route.first, route.second)
                }
              }
              is BridgeEvent.Timeline -> {
                state = state.applyTimeline(event.update)
              }
              is BridgeEvent.NativeHistories -> {
                val oldRoute = state.viewedTimelineRoute
                state = state.copy(nativeHistorySessions = event.sessions)
                val active = state.request
                if (active != null && !state.historyBrowsing) {
                  val route = state.timelineRouteFor(active)
                  if (route != oldRoute) {
                    state = state.copy(viewedTimelineRoute = route)
                    route?.let { bridgeClient.requestTimeline(it.first, it.second) }
                  }
                }
              }
              is BridgeEvent.RequestClosed -> {
                if (state.request?.requestId == event.requestId && state.request?.projectPath == event.projectPath) closeImage()
                state = state.closeRequest(event.requestId, event.projectPath)
              }
              is BridgeEvent.ActionResult -> {
                val pending=state.pendingAction
                if(pending!=null&&pending.origin==RequestOrigin.Native&&pending.originalDeviceId==current.deviceId){
                  val receipt=BridgeJsonParser.parseActionReceipt(event.text,pending.requestId,pending.projectPath,pending.clientActionId,pending.action,pending.origin)
                  if(receipt?.delivered==true)state=state.deliveredRequest(pending.requestId,pending.projectPath,receipt.resultKind)
                  else if(receipt?.authoritativeRejection==true)state=state.actionFailed(pending.requestId,pending.projectPath,receipt)
                }
                for((key,draft)in state.drafts.toMap()){
                  val original=draft.unconfirmedAction ?: continue
                  if(original.origin!=RequestOrigin.Native||original.originalDeviceId!=current.deviceId)continue
                  val receipt=BridgeJsonParser.parseActionReceipt(event.text,key.first,key.second,original.clientActionId,original.action,original.origin) ?: continue
                  if(receipt.delivered||receipt.authoritativeRejection){
                    val notice=if(receipt.authoritativeRejection)"原回复未执行" else if(receipt.resultKind=="saved")"电脑已保存" else "CLI 已接收"
                    state=state.copy(queryNotices=state.queryNotices+(key to notice),queryConfirmedKeys=state.queryConfirmedKeys+key)
                    if(key !in state.closedRequestKeys){
                      if(receipt.delivered)state=state.deliveredRequest(key.first,key.second,receipt.resultKind)
                      else state=state.copy(drafts=state.drafts+(key to draft.copy(deliveryUnknown=false,unconfirmedAction=null)),actionNotice=notice)
                    }
                  }
                }
              }
              is BridgeEvent.Disconnected -> {
                state = state.clearRemoteRequests(BridgeConnectionState.Offline, event.reason)
              }
            }
          }
        } catch (cancelled: CancellationException) {
          throw cancelled
        } catch (_: Exception) {
          state = state.clearRemoteRequests(BridgeConnectionState.Offline, "网络连接中断")
        }
        if (isActive && pairing == current) delay(3_000)
      }
    }
  }

  private fun sendAction(action: String) {
    val currentPairing = pairing ?: return
    val request = state.request ?: return
    val requestId = request.requestId?.takeIf { it.isNotBlank() } ?: return
    val projectPath = if (request.origin == RequestOrigin.Mirror) "" else request.projectPath?.takeIf { it.isNotBlank() } ?: return
    if (state.connectionState != BridgeConnectionState.Connected || state.sending) return
    if(state.closedDraftKey!=null)return
    if(request.origin==RequestOrigin.Native&&action!="submit"){state=state.copy(actionNotice="CLI 提问仅支持文字和选项回答");return}
    if(request.origin==RequestOrigin.Mirror&&action !in listOf("submit", "close_mirror")){state=state.copy(actionNotice="跨设备请求仅支持文字和选项回答");return}
    val unconfirmed = state.drafts[requestId to projectPath]?.unconfirmedAction
    if(unconfirmed?.origin==RequestOrigin.Native){queryOriginalReply(requestId to projectPath);return}
    if (unconfirmed != null && (unconfirmed.action != action || unconfirmed.text != state.userInput ||
        unconfirmed.selectedOptions != state.selectedOptions)) {
      state = state.copy(actionNotice = "上一条回复状态未知；请先用原消息重试确认或核对电脑上的原窗口")
      return
    }
    val actionId = unconfirmed?.clientActionId ?: UUID.randomUUID().toString()
    val submittedInput = state.userInput
    val payload = unconfirmed?.payload ?: if (request.origin == RequestOrigin.Mirror) BridgeJsonParser.buildMirrorAction(
      action, requestId, submittedInput, state.selectedOptions.toList(), actionId,
    ) else BridgeJsonParser.buildMcpAction(
      action = action,
      projectPath = projectPath,
      requestId = requestId,
      userInput = submittedInput,
      selectedOptions = state.selectedOptions.toList(),
      clientActionId = actionId,
    )
    state = state.beginAction(requestId, projectPath, actionId, action, payload,currentPairing.deviceId)
    viewModelScope.launch {
      val receipt = bridgeClient.sendAction(currentPairing, payload, requestId, projectPath, actionId, action,request.origin)
      val pending = state.pendingAction
      if (pairing != currentPairing || pending?.matchesReceipt(requestId, projectPath, actionId) != true) return@launch
      if (receipt.delivered) {
        if (state.request?.requestId == requestId && state.request?.projectPath == projectPath) closeImage()
        state = state.deliveredRequest(requestId, projectPath,receipt.resultKind)
      } else {
        state = state.actionFailed(requestId, projectPath, receipt)
      }
    }
  }
}
