package com.kexin94yyds.iterate.mobile

import android.Manifest
import android.app.Activity
import android.widget.Toast
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier

@Composable
fun AndroidMobileWorkbenchApp(
  activity: Activity?,
  viewModel: BridgeViewModel,
) {
  var voiceRequestKey by remember(activity) { mutableStateOf<Pair<String?, String?>?>(null) }
  val voiceController = remember(activity) {
    activity?.let {
      VoiceInputController(
        activity = it,
        onState = { voiceState ->
          viewModel.setVoiceState(voiceState)
          if (voiceState != VoiceInputState.Listening) voiceRequestKey = null
        },
        onTranscript = { transcript ->
          val current = viewModel.state.request
          if (voiceRequestKey != null && current != null && current.requestId == voiceRequestKey?.first &&
            current.projectPath == voiceRequestKey?.second) {
            viewModel.acceptVoiceTranscript(transcript)
          }
        },
      )
    }
  }
  val permissionLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
    voiceController?.onPermissionResult(granted)
  }

  val state = viewModel.state
  DisposableEffect(voiceController, state.request?.requestId, state.request?.projectPath, state.route) {
    onDispose {
      voiceController?.cancel()
    }
  }

  AndroidMobileTheme(lightAppearance = state.lightAppearance) {
    Box(Modifier.fillMaxSize().background(IosParityColors.Background).safeDrawingPadding()) {
      when (if (state.paired) state.route else WorkbenchRoute.Home) {
      WorkbenchRoute.Conversation -> WorkbenchScreen(
        state = state,
        onHomeClick = { viewModel.showHome() },
        onNotificationClick = { viewModel.toggleNotifications() },
        onThemeClick = { viewModel.toggleTheme() },
        onNewChatClick = { viewModel.openNewChat() },
        onSelectRequest = viewModel::selectRequest,
        onUserInputChange = viewModel::setUserInput,
        onOptionClick = viewModel::toggleOption,
        onInsertTemplate = viewModel::insertQuickTemplate,
        onRefreshTemplates = viewModel::refreshQuickTemplates,
        onContinueClick = viewModel::sendContinue,
        onSubmitClick = viewModel::sendSubmit,
        onVoiceClick = {
          val current = viewModel.state.request
          if (current == null) {
            activity?.let { Toast.makeText(it, "请先选择一条请求", Toast.LENGTH_SHORT).show() }
          } else if (state.voiceState == VoiceInputState.Listening) {
            voiceController?.stop()
          } else {
            voiceRequestKey = current.requestId to current.projectPath
            voiceController?.start {
              permissionLauncher.launch(Manifest.permission.RECORD_AUDIO)
            } ?: viewModel.setVoiceState(VoiceInputState.Error)
          }
        },
        imagePreview = viewModel.previewImage,
        imageSvg = viewModel.previewSvg,
        imageLoading = viewModel.imageLoading,
        imageError = viewModel.imageError,
        onImageClick = viewModel::openImage,
        onCloseImage = viewModel::closeImage,
      )
      WorkbenchRoute.Home -> ConnectionScreen(
        state = state,
        onBackToConversation = { viewModel.showConversation() },
        onPairingInput = viewModel::setPairingInput,
        onPair = { viewModel.importPairing(viewModel.state.pairingInput) },
        onForget = viewModel::forgetPairing,
        onSelectRequest = viewModel::selectRequest,
      )
      }
    }
  }
}
