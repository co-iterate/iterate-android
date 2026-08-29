package com.kexin94yyds.iterate.mobile

import android.app.Activity
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.remember

@Composable
fun AndroidMobileWorkbenchApp(
  activity: Activity?,
  viewModel: BridgeViewModel = remember { BridgeViewModel() },
) {
  val voiceController = remember(activity) {
    activity?.let {
      VoiceInputController(
        activity = it,
        onState = viewModel::setVoiceState,
        onTranscript = viewModel::acceptVoiceTranscript,
      )
    }
  }

  DisposableEffect(voiceController) {
    onDispose {
      voiceController?.stop()
    }
  }

  AndroidMobileTheme {
    val state = viewModel.state
    when (state.route) {
      WorkbenchRoute.Conversation -> WorkbenchScreen(
        state = state,
        onHomeClick = { viewModel.showHome() },
        onNotificationClick = { viewModel.toggleNotifications() },
        onThemeClick = { viewModel.toggleTheme() },
        onNewChatClick = { viewModel.openNewChat() },
        onUserInputChange = viewModel::setUserInput,
        onOptionClick = viewModel::toggleOption,
        onGoalClick = viewModel::sendGoal,
        onSubmitClick = viewModel::sendSubmit,
        onVoiceClick = {
          if (state.voiceState == VoiceInputState.Listening) {
            voiceController?.stop()
          } else {
            voiceController?.start() ?: viewModel.setVoiceState(VoiceInputState.Error)
          }
        },
      )
      WorkbenchRoute.Home -> MobileWebViewScreen(
        onBackToConversation = { viewModel.showConversation() },
      )
    }
  }
}
