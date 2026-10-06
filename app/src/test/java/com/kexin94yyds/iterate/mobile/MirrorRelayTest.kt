package com.kexin94yyds.iterate.mobile

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class MirrorRelayTest {
  @Test fun continueIsExactTextSubmitAndNeverReplacesAnUnknownReply() {
    val request = BridgeJsonParser.parseRequest(mirrorState().toString())!!
    val ready = WorkbenchUiState().receiveRequest(request).copy(
      paired = true, connectionState = BridgeConnectionState.Connected,
      userInput = "old draft", selectedOptions = setOf("old option"),
    )
    assertTrue(ready.canSendContinue)
    val prepared = ready.prepareContinueReply()!!
    assertEquals("按最佳实践规范继续", prepared.userInput)
    assertTrue(prepared.selectedOptions.isEmpty())
    val payload = JSONObject(BridgeJsonParser.buildMirrorAction("submit", id, prepared.userInput,
      prepared.selectedOptions.toList(), "continue-id")).getJSONObject("payload")
    assertEquals("submit", payload.getString("action"))
    assertEquals("按最佳实践规范继续", payload.getString("user_input"))
    val unknown = ready.beginAction(id, "", "old-id", "submit", "old-payload")
      .actionFailed(id, "", ActionReceipt(false, "unknown", true))
    assertFalse(unknown.canSendContinue)
    assertNull(unknown.prepareContinueReply())
    assertNull(ready.copy(sending = true).prepareContinueReply())
    assertNull(ready.copy(connectionState = BridgeConnectionState.Offline).prepareContinueReply())
    assertNull(ready.copy(request = request.copy(origin = RequestOrigin.Native)).prepareContinueReply())
    assertNull(ready.closeRequest(id, "").prepareContinueReply())
  }

  private val id = "cross-mirror:" + "a".repeat(64)
  private fun mirrorState(): JSONObject = JSONObject().put("message_type", "cross_device_mirror_state")
    .put("payload", JSONObject().put("mirror_id", id).put("request_id", id).put("source", "cross_device_mirror")
      .put("request", JSONObject().put("id", id).put("message", "Mac 原文")
        .put("predefined_options", org.json.JSONArray(listOf("  原样选项  ")))))

  @Test fun mirrorHasNoLocalProjectTimelineOrImagesAndCannotMasqueradeAsOrdinaryRequest() {
    val json = mirrorState()
    val request = BridgeJsonParser.parseRequest(json.toString())!!
    assertEquals(RequestOrigin.Mirror, request.origin)
    assertEquals("", request.projectPath)
    assertEquals(listOf("  原样选项  "), request.predefinedOptions)
    assertTrue(request.images.isEmpty())
    assertNull(WorkbenchUiState().timelineRouteFor(request))
    json.put("message_type", "mcp_state")
    assertNull(BridgeJsonParser.parseRequest(json.toString()))
    json.put("message_type", "cross_device_mirror_state")
    json.getJSONObject("payload").getJSONObject("request").put("project_path", "C:/unrelated")
    assertNull(BridgeJsonParser.parseRequest(json.toString()))
  }

  @Test fun mirrorReceiptConfirmsMacAcceptanceOnlyAndMatchesExactIdentityAndAction() {
    val payload = JSONObject().put("mirror_id", id).put("request_id", id).put("source", "cross_device_mirror")
      .put("client_action_id", "action-1").put("action", "submit").put("status", "accepted")
      .put("result_kind", "mac_accepted").put("source_consumed", false)
    val root = JSONObject().put("message_type", "cross_device_mirror_action_result").put("payload", payload)
    fun receipt() = BridgeJsonParser.parseActionReceipt(root.toString(), id, "", "action-1", "submit", RequestOrigin.Mirror)
    assertEquals("mac_accepted", receipt()!!.resultKind)
    assertTrue(receipt()!!.delivered)
    payload.put("client_action_id", "other")
    assertNull(receipt())
    payload.put("client_action_id", "action-1").put("status", "pending")
    assertTrue(receipt()!!.deliveryUnknown)
    root.put("message_type", "mcp_action_result")
    assertNull(receipt())
    val action = JSONObject(BridgeJsonParser.buildMirrorAction("submit", id, "文字", emptyList(), "action-1"))
    assertFalse(action.getJSONObject("payload").has("project_path"))
  }

  @Test fun sourceDisappearanceRetainsDraftAndVerifiedMirrorCanResumeWithSameIdentity() {
    val request = BridgeJsonParser.parseRequest(mirrorState().toString())!!
    var state = WorkbenchUiState().receiveRequest(request)
      .copy(userInput = "未发出的草稿", selectedOptions = setOf("  原样选项  "))
    state = state.closeRequest(id, "")
    assertEquals("未发出的草稿", state.drafts[id to ""]!!.text)
    assertFalse(state.drafts[id to ""]!!.deliveryUnknown)
    state = state.receiveRequest(request)
    assertEquals(id, state.request!!.requestId)
    assertEquals("未发出的草稿", state.userInput)
    assertEquals("Mac 已接收这条回复", state.deliveredRequest(id, "", "mac_accepted").actionNotice)
  }

  @Test fun ordinaryPathlessRequestRemainsUnroutable() {
    val ordinary = MobileRequest("ordinary", null, "iterate", "文本", null, emptyList())
    assertTrue(WorkbenchUiState().receiveRequest(ordinary).requests.isEmpty())
  }

  @Test fun closedUncertainMirrorKeepsItsExactDisplayIdentityWithoutReplacingOtherProject() {
    val request = BridgeJsonParser.parseRequest(mirrorState().toString())!!
    val other = MobileRequest("ordinary", "C:/existing", "existing", "本地问题", null, emptyList())
    val key = id to ""
    val closed = WorkbenchUiState()
      .receiveRequest(request).copy(userInput = "原草稿")
      .beginAction(id, "", "action-1", "submit", "original-payload")
      .closeRequest(id, "")
      .actionFailed(id, "", ActionReceipt(false, "待确认", true))
      .receiveRequest(other).selectClosedDraft(key)
    assertEquals(key, closed.closedDraftKey)
    assertEquals(RequestOrigin.Mirror, closed.drafts[key]!!.origin)
    assertEquals(key, closed.drafts[key]!!.requestSnapshot!!.let { it.requestId to it.projectPath })
    assertEquals("原草稿", closed.drafts[key]!!.text)
    val selectedOrdinary = closed.selectActiveRequest(other)
    assertNull(selectedOrdinary.closedDraftKey)
    assertEquals(RequestOrigin.Mcp, selectedOrdinary.request!!.origin)
    assertEquals("C:/existing", selectedOrdinary.request!!.projectPath)
  }

  @Test fun acceptedOrHiddenMirrorCannotBeReopenedByDelayedStateAcrossReplyConnections() {
    val request = BridgeJsonParser.parseRequest(mirrorState().toString())!!
    val other = MobileRequest("ordinary", "C:/existing", "existing", "另一问题", null, emptyList())
    for (kind in listOf("mac_accepted", "mirror_closed")) {
      val pending = WorkbenchUiState().receiveRequest(request).copy(userInput = "原回复")
        .beginAction(id, "", "action-1", "submit", "payload")
        .receiveRequest(other)
      val completed = pending.deliveredRequest(id, "", kind)
      assertEquals(completed, completed.receiveRequest(request))
      assertEquals(completed.clearRemoteRequests(BridgeConnectionState.Offline),
        completed.clearRemoteRequests(BridgeConnectionState.Offline).receiveRequest(request))
      assertEquals(listOf(other), completed.requests)
      assertNull(completed.drafts[id to ""])
      assertEquals(if (kind == "mac_accepted") "Mac 已接收这条回复" else "手机已隐藏该镜像，Mac 请求继续等待", completed.actionNotice)
    }
  }
}
