package com.kexin94yyds.iterate.mobile

import org.junit.Assert.*
import org.junit.Test

class ActionNoticePolicyTest {
  @Test fun routineSuccessIsSilentButActionableFailuresRemainVisible() {
    listOf(null, "", "  ", "电脑已保存", "CLI 已接收", "CLI 已接受", "Mac 已接收这条回复",
      "Mac 已接收原回复", "电脑已收到这条回复", "电脑已收到原回复").forEach {
      assertNull(actionNoticeForDisplay(it))
    }
    listOf("原回复未执行", "送达状态未知；请核对原窗口", "未能在电脑上打开新会话",
      "手机已隐藏该镜像，Mac 请求继续等待").forEach {
      assertEquals(it, actionNoticeForDisplay(it))
    }
  }

  @Test fun consumingNoticeDoesNotEraseANewerNoticeOrUnconfirmedReply() {
    val request = MobileRequest("sent", "E:/fixture", "fixture", "question", null, emptyList())
    val unknown = WorkbenchUiState().receiveRequest(request).copy(userInput = "original reply")
      .beginAction("sent", "E:/fixture", "original-action", "submit", "original-payload", "phone")
      .actionFailed("sent", "E:/fixture", ActionReceipt(false, "delivery unknown", true))
    assertEquals(unknown, unknown.consumeActionNotice("older notice"))
    val consumed = unknown.consumeActionNotice("delivery unknown")
    assertEquals(unknown.copy(actionNotice = null), consumed)
    assertEquals("original reply", consumed.drafts["sent" to "E:/fixture"]?.text)
    assertEquals("original-action", consumed.drafts["sent" to "E:/fixture"]?.unconfirmedAction?.clientActionId)
    assertEquals("sent" to "E:/fixture", consumed.selectClosedDraft("sent" to "E:/fixture").closedDraftKey)
  }
}
