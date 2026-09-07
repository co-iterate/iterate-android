package com.kexin94yyds.iterate.mobile

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test
import org.json.JSONObject

class BridgeJsonParserTest {
  @Test
  fun imagePayloadRetainsRouteAndMediaContract() {
    val root = JSONObject(BridgeJsonParser.buildMcpAction("submit", "/project", "request-1", "draft", emptyList(), listOf(DraftImage("data:image/jpeg;base64,YQ==", "photo.jpg"))))
    val payload = root.getJSONObject("payload")
    assertEquals("request-1", payload.getString("request_id"))
    assertEquals("/project", payload.getString("project_path"))
    val image = payload.getJSONArray("images").getJSONObject(0)
    assertEquals("image/jpeg", image.getString("media_type"))
    assertEquals("data:image/jpeg;base64,YQ==", image.getString("data"))
  }

  @Test
  fun rootBoundaryDoesNotAllowSiblingPrefix() {
    assertEquals(true, isWithinRoot("/work/project/docs", "/work/project"))
    assertEquals(false, isWithinRoot("/work/project-secret", "/work/project"))
  }

  @Test
  fun preservesServerComposerHintAndRequestContext() {
    val request = BridgeJsonParser.parseRequest("""
      {"message_type":"mcp_state","payload":{"request":{
        "request_id":"real-request","message":"Please review this change.",
        "input_placeholder":"补充你的想法…","mcp_host_label":"Codex","task_display_name":"Android UI"
      }}}
    """.trimIndent())
    assertEquals("补充你的想法…", request?.inputPlaceholder)
    assertEquals("Codex · Android UI", request?.contextSummary)
  }

  @Test
  fun idleProjectDoesNotDisplayAnUnrelatedFixtureProject() {
    assertEquals("等待中", WorkbenchUiState().projectTitle)
  }

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
