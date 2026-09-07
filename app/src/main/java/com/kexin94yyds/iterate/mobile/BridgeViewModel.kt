package com.kexin94yyds.iterate.mobile

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch

class BridgeViewModel(
  private val bridgeClient: BridgeClient = BridgeClient(),
) : ViewModel() {
  var state by mutableStateOf(WorkbenchUiState())
    private set

  private val drafts = mutableMapOf<Pair<String?, String?>, WorkbenchUiState>()
  private var selectedProject: ActiveProject? = null

  fun setImages(images: List<DraftImage>) { state = state.copy(images = images) }

  fun selectProject(project: ActiveProject) {
    if (!bridgeClient.syncProject(project)) {
      state = state.copy(bridgeError = "项目切换失败，请重新连接")
      return
    }
    val original = state
    state.request?.let { drafts[it.projectPath to it.requestId] = state }
    selectedProject = project
    state = state.copy(request = null, userInput = "", selectedOptions = emptySet(), images = emptyList())
    viewModelScope.launch {
      delay(10_000)
      if (selectedProject == project && state.request == null) {
        selectedProject = null
        state = original.copy(bridgeError = "未收到所选项目的请求，已保留原草稿，请重试")
      }
    }
  }

  private var connectionJob: Job? = null

  init {
    connect()
  }

  fun showHome() {
    state = state.copy(route = WorkbenchRoute.Home)
  }

  fun showConversation() {
    state = state.copy(route = WorkbenchRoute.Conversation)
  }

  fun setUserInput(value: String) {
    state = state.copy(userInput = value)
  }

  fun toggleOption(option: String) {
    val next = state.selectedOptions.toMutableSet()
    if (!next.add(option)) next.remove(option)
    state = state.copy(selectedOptions = next)
  }

  fun sendSubmit() {
    sendAction("submit")
  }

  fun sendGoal() {
    sendAction("goal")
  }

  fun setVoiceState(voiceState: VoiceInputState) {
    state = state.copy(voiceState = voiceState)
  }

  fun acceptVoiceTranscript(transcript: String) {
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

  fun toggleNotifications() {
    state = state.copy(notificationsEnabled = !state.notificationsEnabled)
  }

  fun toggleTheme() {
    state = state.copy(lightAppearance = !state.lightAppearance)
  }

  fun openNewChat() {
    viewModelScope.launch {
      bridgeClient.openCodexChat()
    }
  }

  fun reconnect() {
    connect()
  }

  private fun connect() {
    connectionJob?.cancel()
    state = state.copy(connectionState = BridgeConnectionState.Connecting, bridgeError = null)
    connectionJob = viewModelScope.launch {
      retryBridgeVersion()
      bridgeClient.requests().collect { result ->
        result
          .onSuccess { request ->
            val target = selectedProject
            if (target != null && (request.projectPath != target.path || request.requestId != target.requestId)) return@onSuccess
            selectedProject = null
            val previous = state.request
            if (previous != null && (previous.projectPath != request.projectPath || previous.requestId != request.requestId)) {
              drafts[previous.projectPath to previous.requestId] = state
            }
            val same = previous?.projectPath == request.projectPath && previous?.requestId == request.requestId
            val draft = if (same) state else drafts[request.projectPath to request.requestId]
            state = state.copy(
              userInput = draft?.userInput.orEmpty(), selectedOptions = draft?.selectedOptions.orEmpty(), images = draft?.images.orEmpty(),
              connectionState = BridgeConnectionState.Connected,
              request = request,
              bridgeError = null,
            )
          }
          .onFailure { error ->
            state = state.copy(
              connectionState = BridgeConnectionState.Offline,
              bridgeError = error.message,
            )
          }
      }
    }
  }

  private suspend fun retryBridgeVersion() {
    repeat(30) {
      val ok = runCatching { bridgeClient.checkVersion() }.isSuccess
      if (ok) {
        state = state.copy(connectionState = BridgeConnectionState.Connected, bridgeError = null)
        return
      }
      delay(500)
    }
    state = state.copy(connectionState = BridgeConnectionState.Offline, bridgeError = "bridge unavailable")
  }

  private fun sendAction(action: String) {
    val request = state.request
    val payload = BridgeJsonParser.buildMcpAction(
      action = action,
      projectPath = request?.projectPath,
      requestId = request?.requestId,
      userInput = state.userInput,
      selectedOptions = state.selectedOptions.toList(),
      images = state.images,
    )
    viewModelScope.launch {
      val sent = bridgeClient.sendAction(payload)
      state = state.copy(bridgeError = if (sent) "已交给连接发送，草稿保留至下一条请求" else "发送失败，草稿已保留")
    }
  }
}
