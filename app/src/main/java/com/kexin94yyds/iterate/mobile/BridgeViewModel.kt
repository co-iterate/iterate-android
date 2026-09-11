package com.kexin94yyds.iterate.mobile

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch

class BridgeViewModel(application: Application) : AndroidViewModel(application) {
  val manager = ConnectionManager.get(application)
  private val bridgeClient get() = manager.client
  private val preferences = application.getSharedPreferences("mobile_preferences", android.content.Context.MODE_PRIVATE)
  var state by mutableStateOf(WorkbenchUiState())
    private set

  private val drafts = mutableMapOf<Pair<String?, String?>, WorkbenchUiState>()
  private var selectedProject: ActiveProject? = null

  fun setImages(images: List<DraftImage>) { state = state.copy(images = images) }

  fun selectProject(project: ActiveProject) {
    if (!manager.selectRoute(project)) {
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

  init {
    state = state.copy(lightAppearance = preferences.getBoolean("light", true), notificationsEnabled = preferences.getBoolean("notifications", true))
    viewModelScope.launch {
      manager.state.collect { snapshot ->
        val request = snapshot.request
        if (request != null) {
          val target = selectedProject
          if (target == null || request.projectPath == target.path && request.requestId == target.requestId) {
            selectedProject = null
            val previous = state.request
            val same = previous?.projectPath == request.projectPath && previous?.requestId == request.requestId
            if (!same && previous != null) drafts[previous.projectPath to previous.requestId] = state
            val draft = if (same) state else drafts[request.projectPath to request.requestId]
            state = state.copy(request = request, userInput = draft?.userInput.orEmpty(), selectedOptions = draft?.selectedOptions.orEmpty(), images = draft?.images.orEmpty())
          }
        } else state = state.copy(request = null)
        state = state.copy(connectionState = snapshot.state, bridgeError = snapshot.replyStatus ?: snapshot.error, pendingReply = snapshot.pendingReply)
      }
    }
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
    preferences.edit().putBoolean("notifications", state.notificationsEnabled).apply()
  }

  fun toggleTheme() {
    state = state.copy(lightAppearance = !state.lightAppearance)
    preferences.edit().putBoolean("light", state.lightAppearance).apply()
  }

  fun openNewChat() {
    viewModelScope.launch {
      if (bridgeClient?.openCodexChat() != true) state = state.copy(bridgeError = "未能打开电脑任务，请检查连接")
    }
  }

  fun reconnect() { manager.reconnect() }

  private fun sendAction(action: String) {
    val request = state.request
    if (request?.requestId.isNullOrBlank() || request?.projectPath.isNullOrBlank()) {
      state = state.copy(bridgeError = "请先连接电脑并选择待回复的消息")
      return
    }
    val payload = BridgeJsonParser.buildMcpAction(
      action = action,
      projectPath = request?.projectPath,
      requestId = request?.requestId,
      userInput = state.userInput,
      selectedOptions = state.selectedOptions.toList(),
      images = state.images,
    )
    if (!manager.queueReply(org.json.JSONObject(payload).getJSONObject("payload"))) {
      state = state.copy(bridgeError = "已有待确认回复或尚未配对，内容已保留")
    }
  }
}
