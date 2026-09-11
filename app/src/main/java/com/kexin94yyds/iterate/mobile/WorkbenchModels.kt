package com.kexin94yyds.iterate.mobile

enum class WorkbenchRoute {
  Conversation,
  Home,
}

enum class BridgeConnectionState {
  Connecting,
  Connected,
  Offline,
  Unpaired,
  Retrying,
  WaitingNetwork,
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
  val inputPlaceholder: String? = null,
  val contextSummary: String? = null,
)

data class WorkbenchUiState(
  val route: WorkbenchRoute = WorkbenchRoute.Conversation,
  val connectionState: BridgeConnectionState = BridgeConnectionState.Unpaired,
  val request: MobileRequest? = null,
  val userInput: String = "",
  val selectedOptions: Set<String> = emptySet(),
  val voiceState: VoiceInputState = VoiceInputState.Idle,
  val notificationsEnabled: Boolean = true,
  val lightAppearance: Boolean = true,
  val bridgeError: String? = null,
  val images: List<DraftImage> = emptyList(),
  val pendingReply: Boolean = false,
) {
  val projectTitle: String
    get() = request?.projectName?.ifBlank { "iterate" } ?: "等待中"

  val requestStatusText: String
    get() = if (request == null) "正在等待指令" else "等待中"

  val connectionLabel: String
    get() = when (connectionState) {
      BridgeConnectionState.Connected -> "已连接"
      BridgeConnectionState.Connecting -> "连接中"
      BridgeConnectionState.Offline -> "离线"
      BridgeConnectionState.Unpaired -> "未配对"
      BridgeConnectionState.Retrying -> "重连中"
      BridgeConnectionState.WaitingNetwork -> "等待网络"
    }
}

data class DraftImage(val data: String, val filename: String, val mediaType: String = "image/jpeg")
data class ActiveProject(val path: String, val requestId: String, val name: String, val title: String)

sealed interface BridgeEvent {
  data class Connection(val state: BridgeConnectionState, val error: String? = null) : BridgeEvent
  data class RequestReceived(val request: MobileRequest) : BridgeEvent
}
