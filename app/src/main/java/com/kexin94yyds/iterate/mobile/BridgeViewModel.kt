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
      state = state.copy(paired = true)
      connect()
    } else {
      state = state.copy(connectionState = BridgeConnectionState.Offline)
    }
  }

  fun showHome() { state = state.copy(route = WorkbenchRoute.Home) }
  fun showConversation() { state = state.copy(route = WorkbenchRoute.Conversation) }
  fun setUserInput(value: String) {
    if (state.request == null) return
    state = state.copy(userInput = value)
  }
  fun insertQuickTemplate(template: QuickTemplate) { state = state.insertQuickTemplate(template) }

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
    if (state.request?.predefinedOptions?.contains(option) != true) return
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
        state = state.copy(paired = true, pairingBusy = false, pairingInput = "", bridgeError = null, route = WorkbenchRoute.Home, drafts = emptyMap())
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
    state = WorkbenchUiState(route = WorkbenchRoute.Home, connectionState = BridgeConnectionState.Offline)
  }

  fun sendSubmit() { sendAction("submit") }
  fun sendContinue() { sendAction("continue") }
  fun sendGoal() { sendAction("goal") }
  fun setVoiceState(voiceState: VoiceInputState) { state = state.copy(voiceState = voiceState) }

  fun acceptVoiceTranscript(transcript: String) {
    if (state.request == null) {
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
    val current = pairing ?: return
    viewModelScope.launch {
      if (!bridgeClient.openCodexChat(current, state.request?.projectPath)) {
        state = state.copy(actionNotice = "未能在电脑上打开新会话")
      }
    }
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
              }
              is BridgeEvent.QuickTemplates -> {
                if (event.snapshot.syncReason == activeTemplateSyncReason) {
                  templateRefreshJob?.cancel()
                  state = state.applyQuickTemplateSnapshot(event.snapshot, activeTemplateSyncReason)
                }
              }
              is BridgeEvent.Request -> {
                val request = event.request
                if (request.requestId.isNullOrBlank() || request.projectPath.isNullOrBlank() || request.projectPath == "main_page") return@collect
                state = state.receiveRequest(request)
              }
              is BridgeEvent.RequestClosed -> {
                if (state.request?.requestId == event.requestId && state.request?.projectPath == event.projectPath) closeImage()
                state = state.closeRequest(event.requestId, event.projectPath)
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
    val projectPath = request.projectPath?.takeIf { it.isNotBlank() } ?: return
    if (state.connectionState != BridgeConnectionState.Connected || state.sending) return
    val unconfirmed = state.drafts[requestId to projectPath]?.unconfirmedAction
    if (unconfirmed != null && (unconfirmed.action != action || unconfirmed.text != state.userInput ||
        unconfirmed.selectedOptions != state.selectedOptions)) {
      state = state.copy(actionNotice = "上一条回复状态未知；请先用原消息重试确认或核对电脑上的原窗口")
      return
    }
    val actionId = unconfirmed?.clientActionId ?: UUID.randomUUID().toString()
    val submittedInput = state.userInput
    val payload = unconfirmed?.payload ?: BridgeJsonParser.buildMcpAction(
      action = action,
      projectPath = projectPath,
      requestId = requestId,
      userInput = submittedInput,
      selectedOptions = state.selectedOptions.toList(),
      clientActionId = actionId,
    )
    state = state.beginAction(requestId, projectPath, actionId, action, payload)
    viewModelScope.launch {
      val receipt = bridgeClient.sendAction(currentPairing, payload, requestId, projectPath, actionId, action)
      val pending = state.pendingAction
      if (pairing != currentPairing || pending?.matchesReceipt(requestId, projectPath, actionId) != true) return@launch
      if (receipt.delivered) {
        if (state.request?.requestId == requestId && state.request?.projectPath == projectPath) closeImage()
        state = state.deliveredRequest(requestId, projectPath)
      } else {
        state = state.actionFailed(requestId, projectPath, receipt)
      }
    }
  }
}
