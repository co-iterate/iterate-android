package com.kexin94yyds.iterate.mobile

import org.junit.Assert.*
import org.junit.Test

class ImmediateTabCloseTest {
  @Test fun everyRequestKindClosesBeforeReceiptWithoutLosingPendingReply() {
    RequestOrigin.values().forEach { origin ->
      val project = if (origin == RequestOrigin.Mirror) "" else "E:/fixture"
      val current = MobileRequest("current", project, "fixture", "question", null,
        listOf("yes"), origin = origin, timelineRouteId = "timeline-current")
      val other = MobileRequest("other", "E:/other", "other", "other question", null, emptyList())
      val otherKey = "other" to "E:/other"
      val otherDraft = RequestDraft("other draft", emptySet())
      val before = WorkbenchUiState(
        request = current, requests = listOf(current, other), userInput = "my reply",
        selectedOptions = setOf("yes"), drafts = mapOf(otherKey to otherDraft),
        viewedTimelineRoute = "timeline-current" to project, historyBrowsing = true,
      )

      // No network or deliveredRequest call has happened at this point.
      val pending = before.beginAction("current", project, "action-fixture", "submit", "payload", "phone-fixture")
      assertNull("$origin current card", pending.request)
      assertEquals("$origin tabs", listOf(other), pending.requests)
      assertNull(pending.viewedTimelineRoute)
      assertFalse(pending.historyBrowsing)
      assertEquals("", pending.userInput)
      assertTrue(pending.selectedOptions.isEmpty())
      assertTrue(pending.sending)
      assertEquals(current, pending.pendingAction?.requestSnapshot)
      assertEquals("my reply", pending.pendingAction?.text)
      assertEquals(setOf("yes"), pending.pendingAction?.selectedOptions)
      assertEquals("action-fixture", pending.pendingAction?.clientActionId)
      assertEquals("payload", pending.pendingAction?.payload)
      assertEquals(origin, pending.pendingAction?.origin)
      assertEquals("phone-fixture", pending.pendingAction?.originalDeviceId)
      assertEquals(otherDraft, pending.drafts[otherKey])
      assertEquals(pending, pending.receiveRequest(current))

      val viewingOther = pending.selectActiveRequest(other)
      val delivered = viewingOther.deliveredRequest("current", project)
      assertEquals(listOf(other), delivered.requests)
      assertEquals(other, delivered.request)
      assertEquals("other draft", delivered.userInput)
      assertNull(delivered.pendingAction)
    }
  }

  @Test fun unknownReplyStillPreservesNativeDraftAndOriginalActionForQuery() {
    val current = MobileRequest("native", "E:/fixture", "fixture", "question", null,
      listOf("yes"), origin = RequestOrigin.Native)
    val pending = WorkbenchUiState(request = current, requests = listOf(current),
      userInput = "keep my reply", selectedOptions = setOf("yes"))
      .beginAction("native", "E:/fixture", "original-action", "submit", "original-payload", "phone-fixture")
    assertTrue(pending.requests.isEmpty())
    val uncertain = pending.actionFailed("native", "E:/fixture", ActionReceipt(false, "timeout", true))
    val draft = requireNotNull(uncertain.drafts["native" to "E:/fixture"])
    assertEquals("keep my reply", draft.text)
    assertEquals("original-action", draft.unconfirmedAction?.clientActionId)
    assertEquals("original-payload", draft.unconfirmedAction?.payload)
    assertEquals(RequestOrigin.Native, draft.origin)
    assertTrue(draft.deliveryUnknown)
    assertFalse(uncertain.sending)
  }
}
