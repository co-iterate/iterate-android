package com.kexin94yyds.iterate.mobile

import org.json.JSONArray
import org.json.JSONObject

object BridgeJsonParser {
  fun parseNativeHistorySessions(text: String): List<NativeHistorySession>? {
    val root = runCatching { JSONObject(text) }.getOrNull() ?: return null
    if (root.optString("message_type") != "native_history_sessions") return null
    val payload = root.optJSONObject("payload") ?: return null
    if (payload.optString("source") != "codex_native") return null
    val array = payload.optJSONArray("sessions") ?: return null
    return (0 until array.length()).mapNotNull { index ->
      val item = array.optJSONObject(index) ?: return@mapNotNull null
      val route = firstNonBlank(item.optString("routeId"))?.takeIf { it.startsWith("native-cli:") }
        ?: return@mapNotNull null
      NativeHistorySession(route, firstNonBlank(item.optString("projectPath")) ?: return@mapNotNull null,
        item.optString("title"), item.optString("launchId"), item.optString("threadId"))
    }
  }

  private val markdownImage = Regex("""!\[([^\]]*)]\(([^)\s]+)\)""")
  private val bridgeImage = Regex("""/image\?id=img_[a-fA-F0-9]{32}""")
  private fun supportedImageUrl(url: String): Boolean = bridgeImage.matches(url) || url.startsWith("https://")

  internal fun parseMessageImages(message: String): List<MobileImage> = markdownImage.findAll(message)
    .mapNotNull { match ->
      val url = match.groupValues[2]
      if (supportedImageUrl(url)) {
        MobileImage(url, match.groupValues[1].ifBlank { "图片" })
      } else null
    }
    .toList()

  internal fun messageWithoutImages(message: String): String = markdownImage.replace(message) { match ->
    if (supportedImageUrl(match.groupValues[2])) "" else match.value
  }.trim('\r', '\n')

  fun parseClosedRequest(text: String): Pair<String, String>? {
    val root = runCatching { JSONObject(text) }.getOrNull() ?: return null
    if (root.optString("message_type") == "cross_device_mirror_state") {
      val payload = root.optJSONObject("payload") ?: return null
      val id = mirrorIdentity(payload) ?: return null
      if (payload.opt("closed") != true || !payload.has("request") || !payload.isNull("request")) return null
      return id to ""
    }
    if (root.optString("message_type") != "mcp_state") return null
    val payload = root.optJSONObject("payload") ?: return null
    if (!payload.has("request") || !payload.isNull("request") ||
        !payload.has("showMcpPopup") || payload.optBoolean("showMcpPopup", true)) return null
    val requestId = firstNonBlank(payload.nullableString("request_id"))
    val projectPath = firstNonBlank(payload.nullableString("project_path"))
    if (requestId == null || projectPath == null) return null
    if(origin(payload,null,requestId)==null)return null
    return requestId to projectPath
  }

  fun parseRequest(text: String): MobileRequest? {
    val root = runCatching { JSONObject(text) }.getOrNull() ?: return null
    val messageType = root.optString("message_type")
    if (messageType == "cross_device_mirror_state") {
      val payload = root.optJSONObject("payload") ?: return null
      val id = mirrorIdentity(payload) ?: return null
      val request = payload.optJSONObject("request") ?: return null
      if (request.optString("id") != id || !request.nullableString("project_path").isNullOrBlank()
        || !request.nullableString("projectPath").isNullOrBlank()) return null
      val message = request.optString("message").takeIf { it.isNotBlank() } ?: return null
      return MobileRequest(requestId = id, projectPath = "", projectName = "跨设备文字",
        message = message, browserAiResponse = null, predefinedOptions = request.optJSONArray("predefined_options").toRawStringList(),
        conversationTitle = request.nullableString("conversation_title")?.takeIf { it.isNotBlank() } ?: "未命名会话",
        isMarkdown = request.optBoolean("is_markdown", true), origin = RequestOrigin.Mirror,
        sourceComputerId = firstNonBlank(payload.nullableString("origin_device_id")),
        sourceComputerName = firstNonBlank(payload.nullableString("origin_name")),
        sourceComputerPlatform = sourceComputerPlatform(payload))
    }
    if (messageType != "mcp_state") return null

    val payload = root.optJSONObject("payload") ?: return null
    val request = payload.optJSONObject("request") ?: return null
    val message = request.optString("message")
    if (message.isBlank()) return null
    val isMarkdown = request.optBoolean("is_markdown", true)

    val requestId = firstNonBlank(
      request.nullableString("request_id"),
      request.nullableString("requestId"),
      request.nullableString("id"),
    )
    val projectPath = firstNonBlank(
      request.nullableString("project_path"),
      request.nullableString("projectPath"),
    )
    val origin=origin(payload,request,requestId) ?: return null
    val projectName = projectPath
      ?.trimEnd('/', '\\')
      ?.substringAfterLast('/')
      ?.substringAfterLast('\\')
      ?.takeIf { it.isNotBlank() }
      ?: "iterate"

    return MobileRequest(
      requestId = requestId,
      origin = origin,
      projectPath = projectPath,
      projectName = projectName,
      message = message,
      browserAiResponse = firstNonBlank(
        request.nullableString("browser_ai_response"),
        request.nullableString("browserAiResponse"),
      ),
      predefinedOptions = if(origin==RequestOrigin.Native)request.optJSONArray("predefined_options").toRawStringList()else request.optJSONArray("predefined_options").toStringList(),
      images = if (isMarkdown) parseMessageImages(message) else emptyList(),
      isMarkdown = isMarkdown,
      conversationTitle = firstNonBlank(
        request.nullableString("conversation_title"),
        request.nullableString("conversationTitle"),
      ) ?: "未命名弹窗",
      timelineRouteId = firstNonBlank(
        payload.nullableString("timeline_route_id"), request.nullableString("timeline_route_id"),
        if (origin == RequestOrigin.Native) request.nullableString("codex_thread_id") else requestId,
      ),
      conversationId = firstNonBlank(payload.nullableString("conversation_id")),
      codexThreadId = firstNonBlank(request.nullableString("codex_thread_id"),
        request.nullableString("codexThreadId"), request.optJSONObject("metadata")?.nullableString("codex_thread_id")),
      codexThreadProvenance = firstNonBlank(request.nullableString("codex_thread_provenance")),
      sourceComputerId = firstNonBlank(payload.nullableString("origin_device_id")),
      sourceComputerName = firstNonBlank(payload.nullableString("origin_name")),
      sourceComputerPlatform = sourceComputerPlatform(payload),
    )
  }

  private fun sourceComputerPlatform(payload: JSONObject): SourceComputerPlatform? =
    when (payload.nullableString("origin_platform")?.trim()) {
      "windows" -> SourceComputerPlatform.Windows
      "macos" -> SourceComputerPlatform.Mac
      else -> null
    }

  fun parseTimeline(text: String): MobileTimelineUpdate? {
    val root = runCatching { JSONObject(text) }.getOrNull() ?: return null
    val type = root.optString("message_type")
    if (type != "mcp_state" && type != "timeline_sync_snapshot" && type != "timeline_sync_delta") return null
    val payload = root.optJSONObject("payload") ?: return null
    val request = payload.optJSONObject("request")
    val route = firstNonBlank(payload.nullableString("timeline_route_id"), request?.nullableString("timeline_route_id"),
      if (payload.optString("source") == "codex_native") request?.nullableString("codex_thread_id") else null,
      payload.nullableString("request_id")) ?: return null
    val source = firstNonBlank(payload.nullableString("source"), request?.nullableString("source"))
    if (route.startsWith("native-cli:") != (source == "codex_native")) return null
    val project = firstNonBlank(payload.nullableString("project_path"), request?.nullableString("project_path")) ?: return null
    val conversation = firstNonBlank(payload.nullableString("conversation_id")) ?: return null
    val array = payload.optJSONArray("timelineNodes")
    val one = payload.optJSONObject("timelineNode")
    if (array == null && one == null) return null
    val nodes = if (array != null) (0 until array.length()).mapNotNull { parseTimelineNode(array.optJSONObject(it)) }
      else listOfNotNull(parseTimelineNode(one))
    return MobileTimelineUpdate(route, project, conversation, nodes,
      type == "timeline_sync_snapshot" || (type == "mcp_state" && array != null))
  }

  private fun parseTimelineNode(node: JSONObject?): MobileTimelineNode? {
    node ?: return null
    val id = firstNonBlank(node.nullableString("id")) ?: return null
    val role = node.optString("node_type")
    if (role != "user" && role != "assistant") return null
    return MobileTimelineNode(id, firstNonBlank(node.nullableString("parent_id")), role,
      node.optString("content"), firstNonBlank(node.optJSONObject("metadata")?.nullableString("run_id")))
  }

  fun buildMcpAction(
    action: String,
    projectPath: String?,
    requestId: String?,
    userInput: String,
    selectedOptions: List<String>,
    clientActionId: String? = null,
  ): String {
    val payload = JSONObject()
      .put("action", action)
      .put("project_path", projectPath ?: "")

    if (!clientActionId.isNullOrBlank()) payload.put("client_action_id", clientActionId)
    if (!requestId.isNullOrBlank()) {
      payload.put("request_id", requestId)
    }
    if (userInput.isNotBlank()) {
      payload.put("user_input", userInput)
    }
    if (selectedOptions.isNotEmpty()) {
      payload.put("selected_options", JSONArray(selectedOptions))
    }

    return JSONObject()
      .put("message_type", "mcp_action")
      .put("payload", payload)
      .toString()
  }

  private fun mirrorIdentity(payload: JSONObject): String? {
    val id = payload.nullableString("mirror_id") ?: return null
    if (!id.matches(Regex("cross-mirror:[a-f0-9]{64}")) || payload.optString("request_id") != id
      || payload.optString("source") != "cross_device_mirror" || !payload.nullableString("project_path").isNullOrBlank()
      || !payload.nullableString("projectPath").isNullOrBlank()) return null
    return id
  }

  fun buildMirrorAction(action: String, mirrorId: String, userInput: String, selectedOptions: List<String>, actionId: String): String =
    JSONObject().put("message_type", "cross_device_mirror_action").put("payload", JSONObject()
      .put("mirror_id", mirrorId).put("request_id", mirrorId).put("client_action_id", actionId).put("action", action)
      .put("user_input", userInput).put("selected_options", JSONArray(selectedOptions))).toString()

  fun parseQuickTemplates(text: String): QuickTemplateSnapshot? {
    val root = runCatching { JSONObject(text) }.getOrNull() ?: return null
    if (root.optString("message_type") != "mcp_state") return null
    val payload = root.optJSONObject("payload") ?: return null
    if (!payload.optBoolean("sync_response", false)) return null
    val syncReason = payload.optString("sync_reason").takeIf { it.isNotBlank() } ?: return null
    val config = payload.optJSONObject("customPrompts") ?: return null
    val prompts = config.optJSONArray("prompts") ?: return null
    if (!config.optBoolean("enabled", true)) return QuickTemplateSnapshot(syncReason, emptyList())
    val templates = buildList {
      for (index in 0 until prompts.length()) {
        val prompt = prompts.optJSONObject(index) ?: continue
        val type = prompt.optString("type", "normal")
        if (type.isNotBlank() && type != "normal") continue
        val id = prompt.optString("id").trim()
        val name = prompt.optString("name").trim()
        if (id.isBlank() || name.isBlank()) continue
        add(QuickTemplate(id, name, prompt.optString("content"), prompt.optInt("sort_order", index + 1)))
      }
    }.sortedBy { it.sortOrder }
    return QuickTemplateSnapshot(syncReason, templates)
  }

  fun parseActionReceipt(text: String, requestId: String, projectPath: String, actionId: String, action: String, origin: RequestOrigin = RequestOrigin.Mcp): ActionReceipt? {
    val root = runCatching { JSONObject(text) }.getOrNull() ?: return null
    if (origin == RequestOrigin.Mirror) {
      if (root.optString("message_type") != "cross_device_mirror_action_result") return null
      val payload = root.optJSONObject("payload") ?: return null
      if (mirrorIdentity(payload) != requestId || projectPath.isNotEmpty()
        || payload.optString("client_action_id") != actionId || payload.optString("action") != action) return null
      val kind = payload.optString("result_kind")
      if (payload.optString("status") == "accepted" && kind == (if (action == "close_mirror") "mirror_closed" else "mac_accepted"))
        return ActionReceipt(true, null, resultKind = kind)
      if (payload.optString("status") == "pending") return ActionReceipt(false, "Mac 接收状态未知；请用原回复重试确认", true)
      if (payload.optString("status") == "rejected") return ActionReceipt(false, payload.optString("reason").ifBlank { "Mac 未确认接收" }, authoritativeRejection = true)
      return null
    }
    if (root.optString("message_type") != "mcp_action_result") return null
    val payload = root.optJSONObject("payload") ?: return null
    if (payload.optString("request_id") != requestId ||
        payload.optString("project_path") != projectPath ||
        payload.optString("client_action_id") != actionId ||
        payload.optString("action") != action) return null
    if(origin==RequestOrigin.Native){
      val authoritative=payload.opt("final_result")==true&&payload.optString("source")=="codex_native"
      val kind=payload.optString("result_kind")
      if(authoritative&&payload.optString("status")=="delivered"&&payload.opt("delivered")==true&&kind in listOf("saved","cli_received"))return ActionReceipt(true,null,resultKind=kind)
      if(authoritative&&payload.optString("status")=="rejected"&&payload.opt("delivered")==false)return ActionReceipt(false,"原回复未执行",authoritativeRejection=true)
      return ActionReceipt(false,if(payload.optString("status")=="pending")"处理中" else "结果未知；请查询原回复",true)
    }
    return if (payload.optBoolean("delivered") && payload.optString("status") == "delivered") {
      ActionReceipt(true, null)
    } else if (payload.optString("status") == "pending") {
      ActionReceipt(false, "电脑尚未确认收到回复；可用原消息重试确认", true)
    } else {
      ActionReceipt(false, payload.optString("reason").ifBlank { "桌面未确认收到回复" })
    }
  }

  private fun origin(payload:JSONObject,request:JSONObject?,id:String?):RequestOrigin? {
    if (id?.startsWith("cross-mirror:") == true || payload.optString("source") == "cross_device_mirror"
      || request?.optString("source") == "cross_device_mirror") return null
    val native=id?.startsWith("native-codex:")==true
    val source=payload.nullableString("source").orEmpty().ifBlank{request?.nullableString("source").orEmpty()}
    if(native!=(source=="codex_native"))return null
    return if(native)RequestOrigin.Native else RequestOrigin.Mcp
  }
  fun buildNativeQuery(original:String):String = JSONObject(original).apply {
    getJSONObject("payload").put("native_query",true)
  }.toString()

  // JSONObject.optString coerces JSON null to the literal "null". Only absent/null
  // identity and metadata fields are missing; a real string "null" stays a string.
  private fun JSONObject.nullableString(key: String): String? =
    if (!has(key) || isNull(key)) null else optString(key)

  private fun firstNonBlank(vararg values: String?): String? {
    return values.firstOrNull { !it.isNullOrBlank() }?.trim()
  }

  private fun JSONArray?.toRawStringList():List<String> = if(this==null)emptyList()else (0 until length()).mapNotNull{index->(opt(index) as? String)?.takeIf{it.isNotEmpty()}}

  private fun JSONArray?.toStringList(): List<String> {
    if (this == null) return emptyList()
    return buildList {
      for (index in 0 until length()) {
        val value = optString(index).trim()
        if (value.isNotEmpty()) add(value)
      }
    }
  }
}
