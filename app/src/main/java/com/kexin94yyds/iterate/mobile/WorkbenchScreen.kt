package com.kexin94yyds.iterate.mobile

import android.graphics.Bitmap
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.clickable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Button
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.compose.ui.viewinterop.AndroidView

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun WorkbenchScreen(
  state: WorkbenchUiState,
  onHomeClick: () -> Unit,
  onNotificationClick: () -> Unit,
  onThemeClick: () -> Unit,
  onNewChatClick: () -> Unit,
  onSelectRequest: (MobileRequest) -> Unit,
  onUserInputChange: (String) -> Unit,
  onOptionClick: (String) -> Unit,
  onInsertTemplate: (QuickTemplate) -> Unit,
  onRefreshTemplates: () -> Unit,
  onContinueClick: () -> Unit,
  onSubmitClick: () -> Unit,
  onVoiceClick: () -> Unit,
  imagePreview: Bitmap?,
  imageSvg: String?,
  imageLoading: Boolean,
  imageError: String?,
  onImageClick: (MobileImage) -> Unit,
  onCloseImage: () -> Unit,
) {
  var showProjectPicker by remember { mutableStateOf(false) }
  val scrollState = rememberScrollState()
  LaunchedEffect(state.request?.requestId, state.request?.projectPath) {
    scrollState.scrollTo(0)
  }
  Box(
    modifier = Modifier
      .fillMaxSize()
      .background(IosParityColors.Background),
  ) {
    Column(
      modifier = Modifier
        .fillMaxSize()
        .imePadding()
        .verticalScroll(scrollState),
    ) {
      WorkbenchHeader(
        title = state.popupTitle,
        subtitle = state.requestStatusText,
        connectionLabel = state.connectionLabel,
        connectionState = state.connectionState,
        notificationsEnabled = state.notificationsEnabled,
        lightAppearance = state.lightAppearance,
        onHomeClick = onHomeClick,
        onNotificationClick = onNotificationClick,
        onThemeClick = onThemeClick,
        onNewChatClick = onNewChatClick,
        onProjectClick = { showProjectPicker = true },
        requestCount = state.requests.size,
      )
      RequestTabs(state.requests, state.request, onSelectRequest)
      Column(
        modifier = Modifier
          .padding(horizontal = 16.dp, vertical = 10.dp)
      ) {
        if (state.request != null) {
          state.actionNotice?.let {
            androidx.compose.material3.Text(it)
          }
          MessageCard(request = state.request, onImageClick = onImageClick)
          key(state.request.requestId, state.request.projectPath) {
            InputSection(
              value = state.userInput,
              predefinedOptions = state.request.predefinedOptions,
              selectedOptions = state.selectedOptions,
              quickTemplates = state.quickTemplates,
              templateRefreshing = state.templateRefreshing,
              templateNotice = state.templateNotice,
              onValueChange = onUserInputChange,
              onOptionClick = onOptionClick,
              onInsertTemplate = onInsertTemplate,
              onRefreshTemplates = onRefreshTemplates,
            )
          }
        }
      }
      if (state.request != null) {
        FooterBar(
          voiceState = state.voiceState,
          onVoiceClick = onVoiceClick,
          onContinueClick = onContinueClick,
          onSubmitClick = onSubmitClick,
          enabled = state.paired && state.connectionState == BridgeConnectionState.Connected && !state.sending,
        )
      }
    }
  }
  if (showProjectPicker) {
    ModalBottomSheet(onDismissRequest = { showProjectPicker = false }) {
      Column(
        modifier = Modifier
          .fillMaxWidth()
          .heightIn(max = 600.dp)
          .verticalScroll(rememberScrollState())
          .padding(horizontal = 16.dp, vertical = 8.dp),
      ) {
        Text("待回复弹窗", fontWeight = FontWeight.Bold, modifier = Modifier.padding(bottom = 12.dp))
        if (state.requests.isEmpty()) {
          Text("当前没有待处理请求", modifier = Modifier.padding(bottom = 24.dp))
        }
        val visibleRequests = listOfNotNull(state.request) + state.requests.filterNot { candidate ->
          candidate.requestId == state.request?.requestId && candidate.projectPath == state.request?.projectPath
        }
        visibleRequests.forEach { candidate ->
          val current = state.request?.requestId == candidate.requestId &&
            state.request?.projectPath == candidate.projectPath
          val pending = state.pendingAction?.requestId == candidate.requestId &&
            state.pendingAction?.projectPath == candidate.projectPath
          Column(
            modifier = Modifier
              .fillMaxWidth()
              .clickable {
                onSelectRequest(candidate)
                showProjectPicker = false
              }
              .padding(vertical = 12.dp, horizontal = 4.dp),
          ) {
            Text(candidate.conversationTitle, fontWeight = FontWeight.Bold)
            Text(candidate.message.lineSequence().firstOrNull().orEmpty().take(100), maxLines = 2)
            Text(candidate.projectPath.orEmpty(), color = IosParityColors.TextSecondary)
            Text(
              when {
                pending -> "送达待确认"
                current -> "当前请求"
                else -> "等待回复"
              },
              color = if (current) IosParityColors.Connected else IosParityColors.TextSecondary,
            )
          }
        }
      }
    }
  }
  if (imagePreview != null || imageSvg != null || imageLoading || imageError != null) {
    Dialog(
      onDismissRequest = onCloseImage,
      properties = DialogProperties(usePlatformDefaultWidth = false),
    ) {
      Column(
        modifier = Modifier
          .fillMaxSize()
          .background(IosParityColors.Background)
          .safeDrawingPadding()
          .padding(16.dp),
      ) {
        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
          Button(onClick = onCloseImage) { Text("关闭图片") }
        }
        Box(modifier = Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.Center) {
          when {
            imageLoading -> Text("正在加载图片…")
            imageError != null -> Text(imageError)
            imageSvg != null -> AndroidView(
              factory = { context ->
                WebView(context).apply {
                  settings.javaScriptEnabled = false
                  settings.domStorageEnabled = false
                  settings.allowFileAccess = false
                  settings.allowContentAccess = false
                  settings.blockNetworkLoads = true
                  webViewClient = object : WebViewClient() {
                    override fun shouldOverrideUrlLoading(view: WebView?, url: String?): Boolean = true
                  }
                }
              },
              update = {
                if (it.tag != imageSvg) {
                  it.tag = imageSvg
                  it.loadDataWithBaseURL(null, imageSvg, "image/svg+xml", "UTF-8", null)
                }
              },
              onRelease = { it.destroy() },
              modifier = Modifier.fillMaxSize(),
            )
            imagePreview != null -> Image(
              bitmap = imagePreview.asImageBitmap(),
              contentDescription = "请求中的图片",
              modifier = Modifier.fillMaxSize(),
              contentScale = ContentScale.Fit,
            )
          }
        }
      }
    }
  }
}

@Composable
private fun RequestTabs(
  requests: List<MobileRequest>,
  selected: MobileRequest?,
  onSelect: (MobileRequest) -> Unit,
) {
  if (requests.isEmpty()) return
  val listState = rememberLazyListState()
  LaunchedEffect(requests, selected?.requestId, selected?.projectPath) {
    val index = if (selected == null) -1 else requests.indexOfFirst {
      it.requestId == selected.requestId && it.projectPath == selected.projectPath
    }
    if (index >= 0) listState.animateScrollToItem(index)
  }
  LazyRow(
    modifier = Modifier.fillMaxWidth().background(IosParityColors.Footer),
    state = listState,
    contentPadding = PaddingValues(horizontal = 12.dp, vertical = 6.dp),
    horizontalArrangement = Arrangement.spacedBy(6.dp),
  ) {
    items(requests, key = { "${it.requestId}|${it.projectPath}" }) { request ->
      val active = selected != null && request.requestId == selected.requestId && request.projectPath == selected.projectPath
      Surface(
        modifier = Modifier
          .widthIn(min = 112.dp, max = 156.dp)
          .heightIn(min = 40.dp)
          .clickable { onSelect(request) },
        shape = RoundedCornerShape(8.dp),
        color = if (active) IosParityColors.PrimaryButton else IosParityColors.Surface,
        border = BorderStroke(1.dp, IosParityColors.SurfaceBorder),
      ) {
        Box(modifier = Modifier.padding(horizontal = 9.dp, vertical = 5.dp), contentAlignment = Alignment.CenterStart) {
          Text(
            request.conversationTitle,
            color = if (active) IosParityColors.OnPrimaryButton else IosParityColors.Text,
            fontWeight = FontWeight.Bold,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
          )
        }
      }
    }
  }
}
