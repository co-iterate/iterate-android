package com.kexin94yyds.iterate.mobile

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
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
) {
  Box(
    modifier = Modifier
      .fillMaxSize()
      .background(IosParityColors.Background),
  ) {
    Column(modifier = Modifier.fillMaxSize()) {
      WorkbenchHeader(
        title = state.projectTitle,
        subtitle = state.requestStatusText,
        connectionLabel = state.connectionLabel,
        connectionState = state.connectionState,
        notificationsEnabled = state.notificationsEnabled,
        lightAppearance = state.lightAppearance,
        onHomeClick = onHomeClick,
        onNotificationClick = onNotificationClick,
        onThemeClick = onThemeClick,
        onNewChatClick = onNewChatClick,
      )
      Column(
        modifier = Modifier
          .weight(1f)
          .verticalScroll(rememberScrollState())
          .padding(horizontal = 16.dp, vertical = 16.dp)
          .padding(bottom = 118.dp),
      ) {
        if (state.request == null) {
          EmptyWorkbenchCard(bridgeError = state.bridgeError)
        } else {
          MessageCard(request = state.request)
        }
        InputSection(
          value = state.userInput,
          predefinedOptions = state.request?.predefinedOptions.orEmpty(),
          selectedOptions = state.selectedOptions,
          onValueChange = onUserInputChange,
          onOptionClick = onOptionClick,
        )
      }
    }
    FooterBar(
      voiceState = state.voiceState,
      onVoiceClick = onVoiceClick,
      onGoalClick = onGoalClick,
      onSubmitClick = onSubmitClick,
      modifier = Modifier.align(Alignment.BottomCenter),
    )
  }
}
