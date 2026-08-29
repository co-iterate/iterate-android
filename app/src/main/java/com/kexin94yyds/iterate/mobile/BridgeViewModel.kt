package com.kexin94yyds.iterate.mobile

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

class BridgeViewModel(
  private val bridgeClient: BridgeClient = BridgeClient(),
) : ViewModel() {
  var state by mutableStateOf(WorkbenchUiState())
    private set

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

  private fun connect() {
    viewModelScope.launch {
      retryBridgeVersion()
      bridgeClient.requests().collect { result ->
        result
          .onSuccess { request ->
            state = state.copy(
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
    )
    viewModelScope.launch {
      bridgeClient.sendAction(payload)
      if (action == "submit") {
        state = state.copy(userInput = "", selectedOptions = emptySet())
      }
    }
  }
}
