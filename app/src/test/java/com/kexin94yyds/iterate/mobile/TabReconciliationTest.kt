package com.kexin94yyds.iterate.mobile

import org.junit.Assert.*
import org.junit.Test

class TabReconciliationTest {
  private fun request(id: String, origin: RequestOrigin = RequestOrigin.Mcp) = MobileRequest(
    id, if (origin == RequestOrigin.Mirror) "" else "E:/fixture", "fixture", "question $id", null,
    listOf("yes"), origin = origin, timelineRouteId = "timeline-$id",
  )

  @Test fun timeoutKeepsSubmittedTabClosedAcrossLateSnapshotsAndReconnectForEveryOrigin() {
    RequestOrigin.values().forEach { origin ->
      val sent = request("sent", origin)
      val key = sent.requestId!! to sent.projectPath!!
      val pending = WorkbenchUiState(request = sent, requests = listOf(sent),
        userInput = "original reply", selectedOptions = setOf("yes"))
        .beginAction(key.first, key.second, "original-action", "submit", "original-payload", "phone")
      val unknown = pending.actionFailed(key.first, key.second, ActionReceipt(false, "timeout", true))

      assertNull("$origin must stay collapsed", unknown.request)
      assertTrue("$origin must not flash in tabs", unknown.requests.isEmpty())
      assertTrue(unknown.keepConversationCollapsed)
      assertTrue(key in unknown.closedRequestKeys)
      val draft = requireNotNull(unknown.drafts[key])
      assertEquals("original reply", draft.text)
      assertEquals(setOf("yes"), draft.selectedOptions)
      assertEquals("original-action", draft.unconfirmedAction?.clientActionId)
      assertEquals("original-payload", draft.unconfirmedAction?.payload)
      assertEquals("phone", draft.originalDeviceId)
      assertTrue(draft.deliveryUnknown)
      assertFalse(unknown.sending)
      assertNull(unknown.pendingAction)
      assertEquals(unknown, unknown.receiveRequest(sent))
      val offline = unknown.clearRemoteRequests(BridgeConnectionState.Offline)
      assertEquals(offline, offline.receiveRequest(sent))
      assertEquals(key, unknown.selectClosedDraft(key).closedDraftKey)
      assertTrue(unknown.deliveredRequest(key.first, key.second).requests.isEmpty())
    }
  }

  @Test fun uncertainMirrorWithObservedCloseCannotReappearBeforeFinalReceipt() {
    val mirror = request("mirror", RequestOrigin.Mirror)
    val unknown = WorkbenchUiState().receiveRequest(mirror).copy(userInput = "reply")
      .beginAction("mirror", "", "action", "submit", "payload")
      .closeRequest("mirror", "")
      .actionFailed("mirror", "", ActionReceipt(false, "timeout", true))
    assertEquals(unknown, unknown.receiveRequest(mirror))
    val next = request("next-mirror", RequestOrigin.Mirror)
    assertEquals(listOf(next), unknown.receiveRequest(next).requests)
    assertNull(unknown.receiveRequest(next).request)
  }

  @Test fun lateFailureRestoresOnlyBackgroundTabWithoutReplacingCurrentEditor() {
    RequestOrigin.values().forEach { origin ->
      for (deliveryUnknown in listOf(false, true)) {
        val sent = request("sent", origin)
        val projectPath = requireNotNull(sent.projectPath)
        val other = request("other")
        val editing = WorkbenchUiState(request = sent, requests = listOf(sent, other), userInput = "sent reply")
          .beginAction("sent", projectPath, "action", "submit", "payload")
          .selectActiveRequest(other).copy(userInput = "editing other", selectedOptions = setOf("yes"))
        val failed = editing.actionFailed("sent", projectPath, ActionReceipt(false, "failure", deliveryUnknown))

        assertEquals("$origin unknown=$deliveryUnknown", other, failed.request)
        assertEquals("editing other", failed.userInput)
        assertEquals(setOf("yes"), failed.selectedOptions)
        assertEquals(editing.viewedTimelineRoute, failed.viewedTimelineRoute)
        assertEquals("sent reply", failed.drafts["sent" to sent.projectPath]?.text)
        if (deliveryUnknown) assertEquals(listOf(other), failed.requests)
        else {
          assertEquals(listOf(other, sent), failed.requests)
          assertEquals("sent reply", failed.selectActiveRequest(sent).userInput)
        }
      }
    }
  }

  @Test fun definiteFailureWithoutSelectionWaitsForExplicitTabClick() {
    val sent = request("sent")
    val failed = WorkbenchUiState().receiveRequest(sent).copy(userInput = "retry me")
      .beginAction("sent", "E:/fixture", "action", "submit", "payload")
      .actionFailed("sent", "E:/fixture", ActionReceipt(false, "not sent"))
    assertNull(failed.request)
    assertEquals(listOf(sent), failed.requests)
    assertTrue(failed.keepConversationCollapsed)
    assertNull(failed.receiveRequest(sent).request)
    assertEquals("retry me", failed.selectActiveRequest(sent).userInput)
  }

  @Test fun newTabsAndRepeatedUpdatesKeepSelectionDraftAndTabOrder() {
    val current = request("current")
    val other = request("other")
    val newTab = request("new")
    val before = WorkbenchUiState(request = current, requests = listOf(current, other),
      userInput = "in progress", selectedOptions = setOf("yes"), viewedTimelineRoute = "timeline-current" to "E:/fixture")
    val arrived = before.receiveRequest(newTab)
    assertEquals(listOf(current, other, newTab), arrived.requests)
    assertEquals(current, arrived.request)
    val refreshed = current.copy(message = "updated question")
    val updated = arrived.receiveRequest(refreshed)
    assertEquals(listOf(refreshed, other, newTab), updated.requests)
    assertEquals(refreshed, updated.request)
    assertEquals("in progress", updated.userInput)
    assertEquals(setOf("yes"), updated.selectedOptions)
    val background = other.copy(message = "updated background")
    assertEquals(listOf(refreshed, background, newTab), updated.receiveRequest(background).requests)
  }

  @Test fun arrivalAndReplayNeverSwitchTheHistoryBeingViewed() {
    val current = request("current")
    val incoming = request("incoming")
    val historyRoute = "native-cli:history" to "E:/history"
    for (selected in listOf(null, current)) {
      val browsing = WorkbenchUiState(request = selected, requests = listOfNotNull(selected),
        viewedTimelineRoute = historyRoute, historyBrowsing = true, userInput = "current draft")
      for (event in listOf(incoming, current.copy(message = "refreshed"))) {
        val updated = browsing.receiveRequest(event)
        assertEquals(historyRoute, updated.viewedTimelineRoute)
        assertTrue(updated.historyBrowsing)
        assertEquals(selected?.requestId, updated.request?.requestId)
        assertEquals("current draft", updated.userInput)
      }
    }
  }

  @Test fun backgroundArrivalKeepsClosedDraftViewAndCurrentEditor() {
    val sent = request("sent")
    val other = request("other")
    val key = "sent" to "E:/fixture"
    val reviewing = WorkbenchUiState().receiveRequest(sent).copy(userInput = "original reply")
      .beginAction(key.first, key.second, "action", "submit", "payload")
      .closeRequest(key.first, key.second)
      .actionFailed(key.first, key.second, ActionReceipt(false, "timeout", true))
      .selectClosedDraft(key)
    val updated = reviewing.receiveRequest(other)
    assertEquals(key, updated.closedDraftKey)
    assertNull(updated.request)
    assertEquals("original reply", updated.drafts[key]?.text)
    assertEquals(reviewing.viewedTimelineRoute, updated.viewedTimelineRoute)
  }

  @Test fun lateFailurePreservesHistoryAndClosedDraftReview() {
    val sent = request("sent")
    val historyRoute = "native-cli:history" to "E:/history"
    val pending = WorkbenchUiState().receiveRequest(sent).copy(userInput = "reply")
      .beginAction("sent", "E:/fixture", "action", "submit", "payload")
    for (deliveryUnknown in listOf(false, true)) {
      val browsing = pending.copy(viewedTimelineRoute = historyRoute, historyBrowsing = true)
      val failed = browsing.actionFailed("sent", "E:/fixture", ActionReceipt(false, "failure", deliveryUnknown))
      assertNull(failed.request)
      assertEquals(historyRoute, failed.viewedTimelineRoute)
      assertTrue(failed.historyBrowsing)
    }
    val closedKey = "previous" to "E:/fixture"
    val reviewing = pending.copy(closedDraftKey = closedKey)
    assertEquals(closedKey, reviewing.actionFailed("sent", "E:/fixture", ActionReceipt(false, "failure")).closedDraftKey)
  }

  @Test fun unknownReplyRemainsQueryableOnlyByTheOriginalPairedDevice() {
    RequestOrigin.values().forEach { origin ->
      val sent = request("sent", origin)
      val key = sent.requestId!! to sent.projectPath!!
      val unknown = WorkbenchUiState(paired = true, connectionState = BridgeConnectionState.Connected,
        currentDeviceId = "original-phone").receiveRequest(sent).copy(userInput = "reply")
        .beginAction(key.first, key.second, "action", "submit", "payload", "original-phone")
        .actionFailed(key.first, key.second, ActionReceipt(false, "timeout", true))
        .selectClosedDraft(key)
      assertEquals(key, unknown.closedDraftKey)
      assertNull(unknown.queryDisabledReason(key))
      assertEquals("请使用发送原回复的配对设备查询", unknown.copy(currentDeviceId = "another-phone").queryDisabledReason(key))
      assertEquals("连接电脑后才能查询原回复", unknown.copy(connectionState = BridgeConnectionState.Offline).queryDisabledReason(key))
    }
  }

  @Test fun newTabFromEveryOriginStaysBehindTheCurrentEditor() {
    val current = request("current")
    val editing = WorkbenchUiState().receiveRequest(current).copy(userInput = "typing", selectedOptions = setOf("yes"))
    RequestOrigin.values().forEach { origin ->
      val incoming = request("new-$origin", origin)
      assertEquals(editing.copy(requests = listOf(current, incoming)), editing.receiveRequest(incoming))
    }
  }
}
