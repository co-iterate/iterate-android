package com.kexin94yyds.iterate.mobile

enum class WorkbenchRoute {
  Conversation,
  Home,
}

enum class BridgeConnectionState {
  Connecting,
  Connected,
  Offline,
}

enum class VoiceInputState {
  Idle,
  Listening,
  PermissionDenied,
  Error,
}

data class MobileRequest(
  val requestId: String?,
  val projectPath: String?,
  val projectName: String,
  val message: String,
  val browserAiResponse: String?,
  val predefinedOptions: List<String>,
)

data class WorkbenchUiState(
  val route: WorkbenchRoute = WorkbenchRoute.Conversation,
  val connectionState: BridgeConnectionState = BridgeConnectionState.Connecting,
  val request: MobileRequest? = null,
  val userInput: String = "",
  val selectedOptions: Set<String> = emptySet(),
  val voiceState: VoiceInputState = VoiceInputState.Idle,
  val notificationsEnabled: Boolean = true,
  val lightAppearance: Boolean = true,
  val bridgeError: String? = null,
) {
  val projectTitle: String
    get() = request?.projectName?.ifBlank { "iterate" } ?: "Agents-Anywhere..."

  val requestStatusText: String
    get() = if (request == null) "正在等待指令" else "等待中"

  val connectionLabel: String
    get() = when (connectionState) {
      BridgeConnectionState.Connected -> "已连接"
      BridgeConnectionState.Connecting -> "连接中"
      BridgeConnectionState.Offline -> "离线"
    }
}
