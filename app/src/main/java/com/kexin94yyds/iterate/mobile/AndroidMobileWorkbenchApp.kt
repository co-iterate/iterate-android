package com.kexin94yyds.iterate.mobile

import android.app.Activity
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.remember
import androidx.lifecycle.viewmodel.compose.viewModel as composeViewModel

@Composable
fun AndroidMobileWorkbenchApp(
  activity: Activity?,
  viewModel: BridgeViewModel = composeViewModel(),
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

  val state = viewModel.state
  WorkbenchSystemBars(activity, state.lightAppearance)
  AndroidMobileTheme(lightAppearance = state.lightAppearance) {
    when (state.route) {
      WorkbenchRoute.Conversation -> WorkbenchScreen(
        state = state,
        onImagesChange = viewModel::setImages,
        onProjectSelect = viewModel::selectProject,
        onHomeClick = { viewModel.showHome() },
        onNotificationClick = { viewModel.toggleNotifications() },
        onThemeClick = { viewModel.toggleTheme() },
        onNewChatClick = { viewModel.openNewChat() },
        onUserInputChange = viewModel::setUserInput,
        onOptionClick = viewModel::toggleOption,
        onGoalClick = {
          voiceController?.stop()
          viewModel.sendGoal()
        },
        onSubmitClick = {
          voiceController?.stop()
          viewModel.sendSubmit()
        },
        onRetryClick = viewModel::reconnect,
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
