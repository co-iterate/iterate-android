package com.kexin94yyds.iterate.mobile

import org.json.JSONArray
import org.json.JSONObject

object BridgeJsonParser {
  fun parseRequest(text: String): MobileRequest? {
    val root = runCatching { JSONObject(text) }.getOrNull() ?: return null
    val messageType = root.optString("message_type")
    if (messageType != "mcp_state" && messageType != "mcp_action") return null

    val payload = root.optJSONObject("payload") ?: return null
    val request = payload.optJSONObject("request") ?: return null
    val message = request.optString("message").trim()
    if (message.isEmpty()) return null

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
      ?.trimEnd('/')
      ?.substringAfterLast('/')
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
    )
  }

  fun buildMcpAction(
    action: String,
    projectPath: String?,
    requestId: String?,
    userInput: String,
    selectedOptions: List<String>,
  ): String {
    val payload = JSONObject()
      .put("action", action)
      .put("project_path", projectPath ?: "")

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
