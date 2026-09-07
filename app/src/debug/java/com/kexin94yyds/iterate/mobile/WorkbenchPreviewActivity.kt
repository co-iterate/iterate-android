package com.kexin94yyds.iterate.mobile

import android.os.Bundle
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Density

/** Offline fixture host. This activity and its sample data are excluded from release builds. */
class WorkbenchPreviewActivity : ComponentActivity() {
  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    enableEdgeToEdge()
    val idle = intent.getStringExtra("scenario") == "idle"
    setContent {
      var state by remember {
        mutableStateOf(
          WorkbenchUiState(
            connectionState = BridgeConnectionState.Connected,
            request = if (idle) null else sampleRequest,
            lightAppearance = intent.getStringExtra("appearance") != "dark",
          ),
        )
      }
      val previewFeedback = {
        Toast.makeText(this, "界面预览，不会发送到电脑", Toast.LENGTH_SHORT).show()
        Unit
      }
      WorkbenchSystemBars(this, state.lightAppearance)
      AndroidMobileTheme(lightAppearance = state.lightAppearance) {
        val density = LocalDensity.current
        CompositionLocalProvider(LocalDensity provides Density(density.density, intent.getFloatExtra("font_scale", density.fontScale))) {
        WorkbenchScreen(
          state = state,
          preview = true,
          onImagesChange = { state = state.copy(images = it) },
          onProjectSelect = { project -> state = state.copy(request = sampleRequest.copy(projectPath = project.path, requestId = project.requestId, projectName = project.name, message = project.title), userInput = "", selectedOptions = emptySet(), images = emptyList()) },
          onHomeClick = previewFeedback,
          onNotificationClick = { state = state.copy(notificationsEnabled = !state.notificationsEnabled) },
          onThemeClick = { state = state.copy(lightAppearance = !state.lightAppearance) },
          onNewChatClick = previewFeedback,
          onUserInputChange = { state = state.copy(userInput = it) },
          onOptionClick = { option ->
            state = state.copy(
              selectedOptions = if (option in state.selectedOptions) state.selectedOptions - option
                else state.selectedOptions + option,
            )
          },
          onGoalClick = previewFeedback,
          onSubmitClick = previewFeedback,
          onVoiceClick = previewFeedback,
          onRetryClick = previewFeedback,
          connectionLabel = "本地预览",
        )
        }
      }
    }
  }

  companion object {
    val sampleRequest = MobileRequest(
      requestId = "ui-preview-only",
      projectPath = "/preview/iterate",
      projectName = "iterate · 预览",
      message = """
        ### 安卓界面，与 iOS 对齐

        更轻的工具栏、清晰的正文和完整的底部操作区。

        - 保留 **当前项目** 与连接状态
        - 回复、选项和语音各就其位
        - 浅色与深色使用同一套布局

        你希望接下来先看哪一部分？
      """.trimIndent(),
      browserAiResponse = null,
      predefinedOptions = listOf("看看深色模式", "试试回复和选项", "继续对齐细节"),
    )
  }
}
