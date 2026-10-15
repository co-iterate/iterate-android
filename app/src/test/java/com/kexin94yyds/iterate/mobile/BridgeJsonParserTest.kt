package com.kexin94yyds.iterate.mobile

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test
import org.json.JSONObject

class BridgeJsonParserTest {
  @Test
  fun markdownDefaultsToTrueAndExplicitFalsePreservesLiteralText() {
    val literal = "  **保留星号**\n![截图](https://example.com/image.png)\n  "
    val request = JSONObject().put("id", "markdown-flag").put("message", literal)
    fun parse() = BridgeJsonParser.parseRequest(JSONObject().put("message_type", "mcp_state")
      .put("payload", JSONObject().put("request", request)).toString())!!

    assertEquals(true, parse().isMarkdown)
    assertEquals(1, parse().images.size)
    request.put("is_markdown", false)
    assertEquals(false, parse().isMarkdown)
    assertEquals(literal, parse().message)
    assertEquals(emptyList<MobileImage>(), parse().images)
    request.put("is_markdown", true)
    assertEquals(true, parse().isMarkdown)
  }

  @Test
  fun keepsIndentationNeededForMarkdownCodeBlocks() {
    assertEquals("    code **literal**", BridgeJsonParser.messageWithoutImages("    code **literal**"))
  }

  @Test
  fun parsesDesktopNormalQuickTemplatesInOrderAndRefreshClearsDisabledList() {
    val state = """{"message_type":"mcp_state","payload":{"sync_response":true,"sync_reason":"android_connect:initial-1","customPrompts":{"enabled":true,"prompts":[{"id":"later","name":"稍后","content":"后","sort_order":2,"type":"normal"},{"id":"conditional","name":"条件","content":"略","sort_order":0,"type":"conditional"},{"id":"first","name":"先","content":"先","sort_order":1},{"id":"clear","name":"清空","content":" ","sort_order":3}]}}}"""
    assertEquals("android_connect:initial-1", BridgeJsonParser.parseQuickTemplates(state)?.syncReason)
    assertEquals(listOf("first", "later", "clear"), BridgeJsonParser.parseQuickTemplates(state)?.templates?.map { it.id })
    val disabled = """{"message_type":"mcp_state","payload":{"sync_response":true,"sync_reason":"android_template_refresh:manual-2","customPrompts":{"enabled":false,"prompts":[{"id":"old","name":"旧","content":"旧"}]}}}"""
    assertEquals(emptyList<QuickTemplate>(), BridgeJsonParser.parseQuickTemplates(disabled)?.templates)
    assertNull(BridgeJsonParser.parseQuickTemplates(state.replace("\"sync_response\":true,", "")))
    assertNull(BridgeJsonParser.parseQuickTemplates(state.replace("\"sync_reason\":\"android_connect:initial-1\",", "")))
    assertNull(BridgeJsonParser.parseQuickTemplates("""{"message_type":"mcp_state","payload":{"request":{}}}"""))
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
    assertEquals("未命名弹窗", request?.conversationTitle)
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

  @Test
  fun keepsEachPopupTitleIndependentOfItsProjectAndMessage() {
    fun popup(id: String, title: String) = JSONObject().put("message_type", "mcp_state")
      .put("payload", JSONObject().put("request", JSONObject()
        .put("id", id)
        .put("project_path", "E:\\Github\\iterate-desktop")
        .put("conversation_title", title)
        .put("message", "这段正文不是标题")))
      .toString()

    val first = BridgeJsonParser.parseRequest(popup("first", "登录问题"))!!
    val second = BridgeJsonParser.parseRequest(popup("second", "构建结果"))!!
    assertEquals("登录问题", first.conversationTitle)
    assertEquals("构建结果", second.conversationTitle)
    assertEquals("登录问题", WorkbenchUiState(request = first, requests = listOf(first, second)).popupTitle)
    assertEquals("构建结果", WorkbenchUiState(request = second, requests = listOf(first, second)).popupTitle)
    assertEquals("未命名弹窗", BridgeJsonParser.parseRequest(popup("third", "  "))?.conversationTitle)
  }

  @Test
  fun acceptsOnlyReceiptForExactRequestProjectAndAction() {
    val matching = """{"message_type":"mcp_action_result","payload":{"request_id":"req-1","project_path":"E:\\A","client_action_id":"send-1","action":"submit","status":"delivered","delivered":true}}"""
    assertEquals(true, BridgeJsonParser.parseActionReceipt(matching, "req-1", "E:\\A", "send-1", "submit")?.delivered)
    assertNull(BridgeJsonParser.parseActionReceipt(matching, "req-2", "E:\\A", "send-1", "submit"))
    assertNull(BridgeJsonParser.parseActionReceipt(matching, "req-1", "E:\\B", "send-1", "submit"))
    assertNull(BridgeJsonParser.parseActionReceipt(matching, "req-1", "E:\\A", "send-2", "submit"))
    assertNull(BridgeJsonParser.parseActionReceipt(matching, "req-1", "E:\\A", "send-1", "goal"))
    val rejected = """{"message_type":"mcp_action_result","payload":{"request_id":"req-1","project_path":"E:\\A","client_action_id":"send-1","action":"submit","status":"rejected","delivered":false,"reason":"stale_request"}}"""
    assertEquals("stale_request", BridgeJsonParser.parseActionReceipt(rejected, "req-1", "E:\\A", "send-1", "submit")?.error)
    val pending = """{"message_type":"mcp_action_result","payload":{"request_id":"req-1","project_path":"E:\\A","client_action_id":"send-1","action":"submit","status":"pending","delivered":false,"reason":"source_confirmation_pending"}}"""
    val pendingReceipt = BridgeJsonParser.parseActionReceipt(pending, "req-1", "E:\\A", "send-1", "submit")
    assertEquals(true, pendingReceipt?.deliveryUnknown)
    assertEquals(false, pendingReceipt?.delivered)
  }

  @Test
  fun closesOnlyWhenStateNamesExactRequestAndProject() {
    val targeted = """{"message_type":"mcp_state","payload":{"request":null,"showMcpPopup":false,"request_id":"req-a","project_path":"E:\\A"}}"""
    val global = """{"message_type":"mcp_state","payload":{"request":null,"showMcpPopup":false}}"""
    val wrongShape = """{"message_type":"mcp_state","payload":{"request":{"id":"req-a"},"showMcpPopup":false,"request_id":"req-a","project_path":"E:\\A"}}"""
    assertEquals("req-a" to "E:\\A", BridgeJsonParser.parseClosedRequest(targeted))
    assertNull(BridgeJsonParser.parseClosedRequest(global))
    assertNull(BridgeJsonParser.parseClosedRequest(wrongShape))
    assertNull(BridgeJsonParser.parseClosedRequest("""{"message_type":"mcp_state","payload":{"request":null,"showMcpPopup":false,"request_id":"req-a"}}"""))
  }

  @Test
  fun findsRegisteredBridgeImageWithoutShowingItsMarkdownAddress() {
    val imageId = "img_0123456789abcdef0123456789abcdef"
    val message = "请看图\n![截图](/image?id=$imageId)\n然后回复"
    val json = JSONObject().put("message_type", "mcp_state")
      .put("payload", JSONObject().put("request", JSONObject()
        .put("id", "req-image")
        .put("project_path", "E:\\Github\\iterate-desktop")
        .put("message", message)))
      .toString()
    val request = BridgeJsonParser.parseRequest(json)
    assertEquals(listOf(MobileImage("/image?id=$imageId", "截图")), request?.images)
    assertEquals("请看图\n\n然后回复", BridgeJsonParser.messageWithoutImages(message))
    assertEquals(emptyList<MobileImage>(), BridgeJsonParser.parseMessageImages("![私有路径](/image?path=C:/secret.png)"))
  }

  @Test
  fun jsonNullOptionalRequestMetadataUsesDefaultsAndOriginalRoute() {
    val state = """{"message_type":"mcp_state","payload":{"source":null,"timeline_route_id":null,"conversation_id":null,"request":{"id":"req-null","message":"  null\n正文  ","project_path":"E:\\A","conversation_title":null,"codex_thread_id":null,"codex_thread_provenance":null,"browser_ai_response":null,"timeline_route_id":null,"metadata":{"codex_thread_id":null},"predefined_options":["null","继续"]}}}"""
    val request = BridgeJsonParser.parseRequest(state)!!
    assertEquals("req-null", request.requestId)
    assertEquals("req-null", request.timelineRouteId)
    assertEquals("未命名弹窗", request.conversationTitle)
    assertEquals(RequestOrigin.Mcp, request.origin)
    assertNull(request.codexThreadId)
    assertNull(request.codexThreadProvenance)
    assertNull(request.browserAiResponse)
    assertNull(request.conversationId)
    assertEquals("  null\n正文  ", request.message)
    assertEquals(listOf("null", "继续"), request.predefinedOptions)
  }

  @Test
  fun jsonNullPreferredFieldAllowsExistingAliasAndMetadataFallback() {
    val state = """{"message_type":"mcp_state","payload":{"timeline_route_id":null,"request":{"request_id":null,"requestId":null,"id":"req-alias","message":"正文","project_path":null,"projectPath":"E:\\A","conversation_title":null,"conversationTitle":"有效标题","browser_ai_response":null,"browserAiResponse":"有效补充","codex_thread_id":null,"codexThreadId":null,"metadata":{"codex_thread_id":"real-thread"},"timeline_route_id":"real-route"}}}"""
    val request = BridgeJsonParser.parseRequest(state)!!
    assertEquals("req-alias", request.requestId)
    assertEquals("E:\\A", request.projectPath)
    assertEquals("有效标题", request.conversationTitle)
    assertEquals("有效补充", request.browserAiResponse)
    assertEquals("real-thread", request.codexThreadId)
    assertEquals("real-route", request.timelineRouteId)
  }

  @Test
  fun literalNullStringsArePreservedInMetadataAndIdentities() {
    val state = """{"message_type":"mcp_state","payload":{"timeline_route_id":"null","conversation_id":"null","request":{"id":"null","project_path":"null","message":"null","conversation_title":"null","codex_thread_id":"null","codex_thread_provenance":"null","browser_ai_response":"null","predefined_options":["null"]}}}"""
    val request = BridgeJsonParser.parseRequest(state)!!
    assertEquals("null", request.requestId)
    assertEquals("null", request.projectPath)
    assertEquals("null", request.conversationTitle)
    assertEquals("null", request.timelineRouteId)
    assertEquals("null", request.conversationId)
    assertEquals("null", request.codexThreadId)
    assertEquals("null", request.codexThreadProvenance)
    assertEquals("null", request.browserAiResponse)
    assertEquals("null", request.message)
    assertEquals(listOf("null"), request.predefinedOptions)
  }

  @Test
  fun nullCloseIdentityCannotTargetAQuestionButLiteralStringStillCan() {
    val state = """{"message_type":"mcp_state","payload":{"request":null,"showMcpPopup":false,"request_id":null,"project_path":"E:\\A"}}"""
    assertNull(BridgeJsonParser.parseClosedRequest(state))
    assertNull(BridgeJsonParser.parseClosedRequest(state.replace("\"request_id\":null", "\"request_id\":\"req-a\"").replace("\"project_path\":\"E:\\\\A\"", "\"project_path\":null")))
    assertEquals("null" to "E:\\A", BridgeJsonParser.parseClosedRequest(state.replace("\"request_id\":null", "\"request_id\":\"null\"")))
  }

  @Test
  fun nullTimelineIdentityFallsBackAndMissingRequiredIdentityIsRejected() {
    val state = """{"message_type":"mcp_state","payload":{"timeline_route_id":null,"request_id":"req-a","project_path":null,"conversation_id":"conversation-a","request":{"project_path":"E:\\A","timeline_route_id":null},"timelineNodes":[{"id":"node-a","parent_id":null,"node_type":"user","content":"null","metadata":{"run_id":null}},{"id":null,"node_type":"assistant","content":"ignore"}]}}"""
    val update = BridgeJsonParser.parseTimeline(state)!!
    assertEquals("req-a", update.routeId)
    assertEquals("E:\\A", update.projectPath)
    assertEquals(1, update.nodes.size)
    assertNull(update.nodes.single().parentId)
    assertNull(update.nodes.single().eventId)
    assertEquals("null", update.nodes.single().content)
    assertNull(BridgeJsonParser.parseTimeline(state.replace("\"conversation_id\":\"conversation-a\"", "\"conversation_id\":null")))
    assertNull(BridgeJsonParser.parseTimeline(state.replace("\"request_id\":\"req-a\"", "\"request_id\":null")))
  }

  @Test
  fun nullSourceDoesNotInventNativeTrustOrReplaceLiteralSource() {
    val state = """{"message_type":"mcp_state","payload":{"source":null,"request":{"id":"native-codex:a","source":"codex_native","message":"正文","codex_thread_id":"native-cli:a"}}}"""
    assertEquals(RequestOrigin.Native, BridgeJsonParser.parseRequest(state)?.origin)
    assertNull(BridgeJsonParser.parseRequest(state.replace("\"source\":\"codex_native\"", "\"source\":null")))
    assertNull(BridgeJsonParser.parseRequest(state.replace("\"source\":null", "\"source\":\"null\"")))
    assertNull(BridgeJsonParser.parseRequest(state.replace("native-codex:a", "ordinary-a")))
    val timeline = """{"message_type":"timeline_sync_snapshot","payload":{"source":null,"timeline_route_id":"native-cli:a","project_path":"E:\\A","conversation_id":"conversation-a","timelineNodes":[]}}"""
    assertNull(BridgeJsonParser.parseTimeline(timeline))
  }
}
