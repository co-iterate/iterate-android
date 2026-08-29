package com.kexin94yyds.iterate.mobile

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test
import org.json.JSONObject

class BridgeJsonParserTest {
  @Test
  fun parsesMcpStateRequest() {
    val json = """
      {
        "message_type": "mcp_state",
        "payload": {
          "request": {
            "id": "req-123",
            "project_path": "/Users/apple/Agents-Anywhere",
            "message": "做完了，可以不用继续轮询了。",
            "browser_ai_response": "最终 DMG:",
            "predefined_options": ["继续", "停止"]
          }
        }
      }
    """.trimIndent()

    val request = BridgeJsonParser.parseRequest(json)

    assertNotNull(request)
    assertEquals("req-123", request?.requestId)
    assertEquals("/Users/apple/Agents-Anywhere", request?.projectPath)
    assertEquals("Agents-Anywhere", request?.projectName)
    assertEquals("做完了，可以不用继续轮询了。", request?.message)
    assertEquals("最终 DMG:", request?.browserAiResponse)
    assertEquals(listOf("继续", "停止"), request?.predefinedOptions)
  }

  @Test
  fun ignoresMessagesWithoutRequest() {
    val json = """{"message_type":"heartbeat","payload":{}}"""

    assertNull(BridgeJsonParser.parseRequest(json))
  }

  @Test
  fun buildsSubmitActionPayload() {
    val json = BridgeJsonParser.buildMcpAction(
      action = "submit",
      projectPath = "/Users/apple/cunzhi",
      requestId = "req-456",
      userInput = "确认继续",
      selectedOptions = listOf("继续"),
    )

    val root = JSONObject(json)
    val payload = root.getJSONObject("payload")
    val selectedOptions = payload.getJSONArray("selected_options")

    assertEquals("mcp_action", root.getString("message_type"))
    assertEquals("submit", payload.getString("action"))
    assertEquals("/Users/apple/cunzhi", payload.getString("project_path"))
    assertEquals("req-456", payload.getString("request_id"))
    assertEquals("确认继续", payload.getString("user_input"))
    assertEquals(1, selectedOptions.length())
    assertEquals("继续", selectedOptions.getString(0))
  }
}
