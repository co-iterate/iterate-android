package com.kexin94yyds.iterate.mobile

import org.json.JSONArray
import org.json.JSONObject

object BridgeJsonParser {
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
    if (root.optString("message_type") != "mcp_state") return null
    val payload = root.optJSONObject("payload") ?: return null
    if (!payload.has("request") || !payload.isNull("request") ||
        !payload.has("showMcpPopup") || payload.optBoolean("showMcpPopup", true)) return null
    val requestId = firstNonBlank(payload.optString("request_id"))
    val projectPath = firstNonBlank(payload.optString("project_path"))
    if (requestId == null || projectPath == null) return null
    return requestId to projectPath
  }

  fun parseRequest(text: String): MobileRequest? {
    val root = runCatching { JSONObject(text) }.getOrNull() ?: return null
    val messageType = root.optString("message_type")
    if (messageType != "mcp_state") return null

    val payload = root.optJSONObject("payload") ?: return null
    val request = payload.optJSONObject("request") ?: return null
    val message = request.optString("message")
    if (message.isBlank()) return null
    val isMarkdown = request.optBoolean("is_markdown", true)

    val requestId = firstNonBlank(
      request.optString("request_id"),
      request.optString("requestId"),
      request.optString("id"),
    )
    val projectPath = firstNonBlank(
      request.optString("project_path"),
      request.optString("projectPath"),
    )
    val projectName = projectPath
      ?.trimEnd('/', '\\')
      ?.substringAfterLast('/')
      ?.substringAfterLast('\\')
      ?.takeIf { it.isNotBlank() }
      ?: "iterate"

    return MobileRequest(
      requestId = requestId,
      projectPath = projectPath,
      projectName = projectName,
      message = message,
      browserAiResponse = firstNonBlank(
        request.optString("browser_ai_response"),
        request.optString("browserAiResponse"),
      ),
      predefinedOptions = request.optJSONArray("predefined_options").toStringList(),
      images = if (isMarkdown) parseMessageImages(message) else emptyList(),
      isMarkdown = isMarkdown,
      conversationTitle = firstNonBlank(
        request.optString("conversation_title"),
        request.optString("conversationTitle"),
      ) ?: "未命名弹窗",
    )
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

  fun parseActionReceipt(text: String, requestId: String, projectPath: String, actionId: String, action: String): ActionReceipt? {
    val root = runCatching { JSONObject(text) }.getOrNull() ?: return null
    if (root.optString("message_type") != "mcp_action_result") return null
    val payload = root.optJSONObject("payload") ?: return null
    if (payload.optString("request_id") != requestId ||
        payload.optString("project_path") != projectPath ||
        payload.optString("client_action_id") != actionId ||
        payload.optString("action") != action) return null
    return if (payload.optBoolean("delivered") && payload.optString("status") == "delivered") {
      ActionReceipt(true, null)
    } else if (payload.optString("status") == "pending") {
      ActionReceipt(false, "电脑尚未确认收到回复；可用原消息重试确认", true)
    } else {
      ActionReceipt(false, payload.optString("reason").ifBlank { "桌面未确认收到回复" })
    }
  }

  private fun firstNonBlank(vararg values: String?): String? {
    return values.firstOrNull { !it.isNullOrBlank() }?.trim()
  }

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
