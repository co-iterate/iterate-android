package com.kexin94yyds.iterate.mobile

private val routineSuccessNotices = setOf(
  "电脑已保存",
  "CLI 已接收",
  "CLI 已接受",
  "Mac 已接收这条回复",
  "Mac 已接收原回复",
  "电脑已收到这条回复",
  "电脑已收到原回复",
)

internal fun actionNoticeForDisplay(notice: String?): String? =
  notice?.takeIf { it.isNotBlank() && it !in routineSuccessNotices }

internal fun WorkbenchUiState.consumeActionNotice(notice: String): WorkbenchUiState =
  if (actionNotice == notice) copy(actionNotice = null) else this
