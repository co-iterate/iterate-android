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
  val images: List<MobileImage> = emptyList(),
  val conversationTitle: String = "未命名弹窗",
  val isMarkdown: Boolean = true,
)

data class MobileImage(val url: String, val alt: String)

data class QuickTemplate(val id: String, val name: String, val content: String, val sortOrder: Int)

data class QuickTemplateSnapshot(val syncReason: String, val templates: List<QuickTemplate>)

data class ActionReceipt(
  val delivered: Boolean,
  val error: String?,
  val deliveryUnknown: Boolean = false,
)

data class RequestDraft(
  val text: String,
  val selectedOptions: Set<String>,
  val deliveryUnknown: Boolean = false,
  val unconfirmedAction: UnconfirmedAction? = null,
)

data class UnconfirmedAction(
  val action: String,
  val clientActionId: String,
  val payload: String,
  val text: String,
  val selectedOptions: Set<String>,
)

data class PendingAction(
  val requestId: String,
  val projectPath: String,
  val clientActionId: String,
  val action: String,
  val payload: String,
  val text: String,
  val selectedOptions: Set<String>,
  val requestSnapshot: MobileRequest? = null,
  val closeObserved: Boolean = false,
)

private typealias RequestKey = Pair<String, String>

private fun PendingAction.key(): RequestKey = requestId to projectPath

internal fun PendingAction.matchesReceipt(requestId: String, projectPath: String, clientActionId: String): Boolean =
  this.requestId == requestId && this.projectPath == projectPath && this.clientActionId == clientActionId

private fun MobileRequest.key(): RequestKey? {
  val id = requestId?.takeIf { it.isNotBlank() } ?: return null
  val path = projectPath?.takeIf { it.isNotBlank() } ?: return null
  return id to path
}

private fun validOptions(selected: Set<String>, request: MobileRequest): Set<String> =
  selected.filterTo(mutableSetOf()) { it in request.predefinedOptions }

data class WorkbenchUiState(
  val route: WorkbenchRoute = WorkbenchRoute.Conversation,
  val connectionState: BridgeConnectionState = BridgeConnectionState.Connecting,
  val request: MobileRequest? = null,
  val requests: List<MobileRequest> = emptyList(),
  val drafts: Map<Pair<String, String>, RequestDraft> = emptyMap(),
  val closedRequestKeys: Set<Pair<String, String>> = emptySet(),
  val pendingAction: PendingAction? = null,
  val keepConversationCollapsed: Boolean = false,
  val paired: Boolean = false,
  val pairingBusy: Boolean = false,
  val pairingInput: String = "",
  val sending: Boolean = false,
  val actionNotice: String? = null,
  val quickTemplates: List<QuickTemplate> = emptyList(),
  val templateRefreshing: Boolean = false,
  val templateNotice: String? = null,
  val userInput: String = "",
  val selectedOptions: Set<String> = emptySet(),
  val voiceState: VoiceInputState = VoiceInputState.Idle,
  val notificationsEnabled: Boolean = true,
  val lightAppearance: Boolean = true,
  val bridgeError: String? = null,
) {
  val popupTitle: String
    get() = request?.conversationTitle ?: "待回复"

  val requestStatusText: String
    get() = when {
      !paired -> "请扫描电脑上的 Android 配对码"
      sending -> if (requests.isEmpty()) "正在等待送达确认" else "正在等待送达确认 · ${requests.size} 条待回复"
      request == null && requests.isNotEmpty() -> "${requests.size} 条待回复 · 点 tab 查看"
      request == null -> "暂无待回复请求"
      requests.size > 1 -> "${requests.size} 条待回复 · 点标题切换"
      else -> "待回复 · 点标题查看"
    }

  val connectionLabel: String
    get() = when (connectionState) {
      BridgeConnectionState.Connected -> "已连接"
      BridgeConnectionState.Connecting -> "连接中"
      BridgeConnectionState.Offline -> "离线"
    }
}

internal fun WorkbenchUiState.insertQuickTemplate(template: QuickTemplate): WorkbenchUiState {
  if (request == null || template !in quickTemplates) return this
  if (template.content.isBlank()) return copy(userInput = "")
  val separator = if (userInput.isEmpty() || userInput.endsWith('\n') || userInput.endsWith(' ') ||
    template.content.startsWith('\n') || template.content.startsWith(' ')) "" else "\n"
  return copy(userInput = userInput + separator + template.content)
}

internal fun WorkbenchUiState.applyQuickTemplateSnapshot(
  snapshot: QuickTemplateSnapshot,
  expectedSyncReason: String?,
): WorkbenchUiState {
  if (snapshot.syncReason != expectedSyncReason) return this
  return copy(quickTemplates = snapshot.templates, templateRefreshing = false, templateNotice = null)
}

private fun WorkbenchUiState.rememberCurrentDraft(): Map<RequestKey, RequestDraft> {
  val key = request?.key() ?: return drafts
  val previous = drafts[key]
  return drafts + (key to RequestDraft(
    text = userInput,
    selectedOptions = selectedOptions,
    deliveryUnknown = pendingAction?.key() == key || previous?.deliveryUnknown == true,
    unconfirmedAction = pendingAction?.takeIf { it.key() == key }?.let {
      UnconfirmedAction(it.action, it.clientActionId, it.payload, it.text, it.selectedOptions)
    } ?: previous?.unconfirmedAction,
  ))
}

internal fun WorkbenchUiState.selectActiveRequest(target: MobileRequest): WorkbenchUiState {
  val key = target.key() ?: return this
  if (request?.key() == key) return copy(
    request = target,
    selectedOptions = validOptions(selectedOptions, target),
    keepConversationCollapsed = false,
    route = WorkbenchRoute.Conversation,
  )
  val saved = rememberCurrentDraft()
  val draft = saved[key]
  return copy(
    request = target,
    drafts = saved,
    userInput = draft?.text.orEmpty(),
    selectedOptions = validOptions(draft?.selectedOptions.orEmpty(), target),
    actionNotice = if (draft?.deliveryUnknown == true) "上一条回复是否送达未知；请先核对电脑上的原窗口" else null,
    keepConversationCollapsed = false,
    route = WorkbenchRoute.Conversation,
  )
}

internal fun WorkbenchUiState.receiveRequest(incoming: MobileRequest): WorkbenchUiState {
  val key = incoming.key() ?: return this
  if (pendingAction?.key() == key) return this
  if (key in closedRequestKeys) return this
  val revisedDrafts = drafts[key]?.let { draft ->
    drafts + (key to draft.copy(selectedOptions = validOptions(draft.selectedOptions, incoming)))
  } ?: drafts
  val updated = copy(
    requests = requests.filterNot { it.key() == key } + incoming,
    drafts = revisedDrafts,
  )
  val selected = request
  if (selected == null) {
    if (keepConversationCollapsed) return updated
    val draft = revisedDrafts[key]
    return updated.copy(
      request = incoming,
      userInput = draft?.text.orEmpty(),
      selectedOptions = draft?.selectedOptions.orEmpty(),
      actionNotice = if (draft?.deliveryUnknown == true) "上一条回复是否送达未知；请先核对电脑上的原窗口" else null,
    )
  }
  return if (selected.key() == key) updated.copy(
    request = incoming,
    selectedOptions = validOptions(selectedOptions, incoming),
  ) else updated
}

internal fun WorkbenchUiState.beginAction(requestId: String, projectPath: String, clientActionId: String,
  action: String = "submit", payload: String = ""): WorkbenchUiState {
  val key = requestId to projectPath
  return copy(
    route = WorkbenchRoute.Conversation,
    keepConversationCollapsed = true,
    request = null,
    requests = requests.filterNot { it.key() == key },
    drafts = rememberCurrentDraft(),
    userInput = "",
    selectedOptions = emptySet(),
    sending = true,
    pendingAction = PendingAction(requestId, projectPath, clientActionId, action, payload, userInput, selectedOptions,
      requestSnapshot = request?.takeIf { it.key() == (requestId to projectPath) }),
    actionNotice = null,
  )
}

internal fun WorkbenchUiState.closeRequest(requestId: String, projectPath: String): WorkbenchUiState {
  val key = requestId to projectPath
  val remaining = requests.filterNot { it.key() == key }
  val selectedWasClosed = request?.key() == key
  val closeIsPending = pendingAction?.let {
    it.requestId == requestId && it.projectPath == projectPath
  } == true
  val keptDrafts = if (closeIsPending) rememberCurrentDraft()
    else if (drafts[key]?.deliveryUnknown == true) drafts else drafts - key
  val next = if (selectedWasClosed) remaining.firstOrNull() else request
  val nextDraft = next?.key()?.let(keptDrafts::get)
  return copy(
    requests = remaining,
    request = next,
    drafts = keptDrafts,
    closedRequestKeys = closedRequestKeys + key,
    pendingAction = if (closeIsPending) pendingAction?.copy(closeObserved = true) else pendingAction,
    userInput = if (selectedWasClosed) nextDraft?.text.orEmpty() else userInput,
    selectedOptions = if (selectedWasClosed) nextDraft?.selectedOptions.orEmpty() else selectedOptions,
    actionNotice = if (closeIsPending) "电脑上的请求已关闭，正在等待送达确认" else if (selectedWasClosed) "电脑上的请求已关闭" else actionNotice,
  )
}

internal fun WorkbenchUiState.deliveredRequest(requestId: String, projectPath: String): WorkbenchUiState {
  val key = requestId to projectPath
  val remaining = requests.filterNot { it.key() == key }
  val selectedWasDelivered = request?.key() == key
  val keptDrafts = drafts - key
  val next = if (selectedWasDelivered) remaining.firstOrNull() else request
  val nextDraft = next?.key()?.let(keptDrafts::get)
  return copy(
    route = WorkbenchRoute.Conversation,
    requests = remaining,
    request = next,
    drafts = keptDrafts,
    userInput = if (selectedWasDelivered) nextDraft?.text.orEmpty() else userInput,
    selectedOptions = if (selectedWasDelivered) nextDraft?.selectedOptions.orEmpty() else selectedOptions,
    sending = false,
    pendingAction = null,
    closedRequestKeys = closedRequestKeys + key,
    actionNotice = "电脑已收到这条回复",
  )
}

internal fun WorkbenchUiState.actionFailed(
  requestId: String,
  projectPath: String,
  receipt: ActionReceipt,
): WorkbenchUiState {
  val key = requestId to projectPath
  val savedDrafts = rememberCurrentDraft()
  val existing = savedDrafts[key]
  val pending = pendingAction?.takeIf { it.key() == key }
  val target = requests.firstOrNull { it.key() == key } ?: pending?.requestSnapshot
    ?: request?.takeIf { it.key() == key }
  val originalText = pending?.text ?: if (request?.key() == key) userInput else existing?.text.orEmpty()
  val originalOptions = pending?.selectedOptions ?: if (request?.key() == key) selectedOptions else existing?.selectedOptions.orEmpty()
  val updatedDrafts = savedDrafts + (key to RequestDraft(
    text = originalText,
    selectedOptions = originalOptions,
    deliveryUnknown = receipt.deliveryUnknown || existing?.deliveryUnknown == true,
    unconfirmedAction = if (receipt.deliveryUnknown) pending?.let {
      UnconfirmedAction(it.action, it.clientActionId, it.payload, it.text, it.selectedOptions)
    } else existing?.unconfirmedAction,
  ))
  val closeObserved = pendingAction?.closeObserved == true
  val notice = if (closeObserved) {
    "电脑上的请求已关闭，回复${if (receipt.deliveryUnknown) "送达状态未知" else "未被确认"}；请核对原窗口"
  } else receipt.error ?: "回复未送达"
  return copy(
    route = if (target != null) WorkbenchRoute.Conversation else route,
    keepConversationCollapsed = false,
    request = target ?: request,
    requests = if (target != null && requests.none { it.key() == key }) listOf(target) + requests else requests,
    sending = false,
    pendingAction = null,
    drafts = updatedDrafts,
    closedRequestKeys = closedRequestKeys - key,
    userInput = if (target != null) originalText else userInput,
    selectedOptions = if (target != null) validOptions(originalOptions, target) else selectedOptions,
    actionNotice = notice,
  )
}

internal fun WorkbenchUiState.clearRemoteRequests(
  connection: BridgeConnectionState,
  error: String? = null,
): WorkbenchUiState = copy(
  connectionState = connection,
  bridgeError = error,
  templateRefreshing = false,
  request = null,
  requests = emptyList(),
  drafts = rememberCurrentDraft().let { saved ->
    pendingAction?.let { pending ->
      val key = pending.key()
      saved + (key to RequestDraft(pending.text, pending.selectedOptions, true,
        UnconfirmedAction(pending.action, pending.clientActionId, pending.payload, pending.text, pending.selectedOptions)))
    } ?: saved
  },
  userInput = "",
  selectedOptions = emptySet(),
  // The receive socket is independent of the action socket. Keep the action
  // in flight until its own exact ACK (or timeout) settles it.
  sending = sending && pendingAction != null,
  actionNotice = if (sending && pendingAction != null) "接收连接断开，正在等待手机回复送达确认" else actionNotice,
)
