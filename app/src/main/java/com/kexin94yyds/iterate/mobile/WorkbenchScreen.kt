package com.kexin94yyds.iterate.mobile

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.unit.dp

@Composable
fun WorkbenchScreen(
  state: WorkbenchUiState,
  onHomeClick: () -> Unit,
  onNotificationClick: () -> Unit,
  onThemeClick: () -> Unit,
  onNewChatClick: () -> Unit,
  onUserInputChange: (String) -> Unit,
  onOptionClick: (String) -> Unit,
  onGoalClick: () -> Unit,
  onSubmitClick: () -> Unit,
  onVoiceClick: () -> Unit,
  onRetryClick: () -> Unit = {},
  connectionLabel: String = state.connectionLabel,
  onImagesChange: (List<DraftImage>) -> Unit = {},
  onProjectSelect: (ActiveProject) -> Unit = {},
  preview: Boolean = false,
) {
  val colors = WorkbenchTheme.colors
  val clipboard = LocalClipboardManager.current
  WorkbenchTools(state, onImagesChange, onProjectSelect, onUserInputChange, preview) { openProjects, pickImage, pickPath ->
  Column(
    modifier = Modifier
      .fillMaxSize()
      .background(colors.background)
      .safeDrawingPadding()
      .imePadding(),
  ) {
    WorkbenchHeader(
      title = state.projectTitle,
      connectionLabel = connectionLabel,
      connectionState = state.connectionState,
      notificationsEnabled = state.notificationsEnabled,
      lightAppearance = state.lightAppearance,
      onHomeClick = onHomeClick,
      onNotificationClick = onNotificationClick,
      onThemeClick = onThemeClick,
      onNewChatClick = onNewChatClick,
      onProjectsClick = openProjects,
    )
    Column(
      modifier = Modifier
        .weight(1f)
        .verticalScroll(rememberScrollState())
        .padding(horizontal = 16.dp, vertical = 16.dp),
      verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
      val request = state.request
      if (request == null) {
        EmptyWorkbenchState(state.connectionState, onRetryClick)
      } else {
        MessageCard(
          request = request,
          onImage = pickImage,
          onPath = pickPath,
          onCopy = { clipboard.setText(AnnotatedString(request.message)) },
          onQuote = {
            onUserInputChange(listOf(state.userInput, request.message).filter { it.isNotBlank() }.joinToString("\n\n"))
          },
        )
      }
      DraftImages(state.images, onImagesChange)
      state.bridgeError?.let { androidx.compose.material3.Text(it, color = colors.secondaryText) }
      InputSection(
        value = state.userInput,
        placeholder = state.request?.inputPlaceholder ?: "请输入您的回复…",
        predefinedOptions = state.request?.predefinedOptions.orEmpty(),
        selectedOptions = state.selectedOptions,
        onValueChange = onUserInputChange,
        onOptionClick = onOptionClick,
      )
      if (state.request == null) {
        InlineVoiceInput(state.voiceState, onVoiceClick)
      }
      VoiceStatus(state.voiceState)
    }
    if (state.request != null) {
      FooterBar(
        voiceState = state.voiceState,
        actionsEnabled = state.connectionState == BridgeConnectionState.Connected,
        onVoiceClick = onVoiceClick,
        onGoalClick = onGoalClick,
        onSubmitClick = onSubmitClick,
      )
    }
  }
}

}
