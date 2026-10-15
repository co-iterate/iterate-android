package com.kexin94yyds.iterate.mobile

import android.graphics.Bitmap
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
import androidx.compose.foundation.layout.height
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
import androidx.compose.material3.ButtonDefaults
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
import androidx.compose.ui.graphics.Color
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
  onSelectClosedDraft: (Pair<String,String>) -> Unit,
  onQueryOriginalReply: () -> Unit,
  onCopyClosedDraft: () -> Unit,
  onSelectRequest: (MobileRequest) -> Unit,
  onSelectNativeHistory: (NativeHistorySession) -> Unit,
  onTimelineMove: (Int) -> Unit,
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
  val closed=state.closedDraftKey?.let {state.drafts[it]}
  val displayRequest=closed?.requestSnapshot ?: state.request
  val visibleTimeline = state.viewedTimeline?.takeIf { it.nodes.isNotEmpty() }
  val historyNode = if (state.historyBrowsing) visibleTimeline?.nodes?.getOrNull(visibleTimeline.position) else null
  val historyOrigins = (listOfNotNull(displayRequest) + state.requests)
    .filter { state.viewedTimelineRoute != null && state.timelineRouteFor(it) == state.viewedTimelineRoute }
    .map { it.origin }.distinct()
  val historyOrigin = when {
    historyOrigins.size == 1 -> historyOrigins.single()
    historyOrigins.isNotEmpty() -> null
    state.nativeHistorySessions.any { (it.routeId to it.projectPath) == state.viewedTimelineRoute } -> RequestOrigin.Native
    else -> null
  }
  val unknown=state.drafts[state.request?.requestId to state.request?.projectPath]?.deliveryUnknown==true
  val activeQueryKey=if(unknown&&state.request?.origin==RequestOrigin.Native)state.request?.let{it.requestId.orEmpty() to it.projectPath.orEmpty()} else null
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
        .imePadding(),
    ) {
      Column(
        modifier = Modifier
          .weight(1f)
          .fillMaxWidth()
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
        onNewChatClick = { if (displayRequest?.origin != RequestOrigin.Mirror) onNewChatClick() },
        onProjectClick = { if (displayRequest?.origin != RequestOrigin.Mirror) showProjectPicker = true },
        requestCount = state.requests.size,
        request = displayRequest,
      )
      RequestTabs(state.requests, state.request, onSelectRequest)
      visibleTimeline?.let { timeline ->
        val position = timeline.position.coerceIn(0, timeline.nodes.lastIndex)
        Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp)) {
          Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            listOf("最前" to 0, "上一条" to position - 1,
              "下一条" to position + 1, "最后" to timeline.nodes.lastIndex).forEachIndexed { index, step ->
              Button(
                onClick = { onTimelineMove(step.second) },
                enabled = !state.historyBrowsing || if (index < 2) position > 0 else position < timeline.nodes.lastIndex,
                modifier = Modifier.weight(1f).height(32.dp),
                contentPadding = PaddingValues(0.dp),
                colors = ButtonDefaults.buttonColors(
                  containerColor = IosParityColors.PrimaryButton,
                  contentColor = IosParityColors.OnPrimaryButton,
                  disabledContainerColor = IosParityColors.PrimaryButton.copy(alpha = 0.45f),
                ),
              ) { Text(step.first, maxLines = 1) }
            }
          }
        }
      }
      Column(
        modifier = Modifier
          .padding(horizontal = 16.dp, vertical = 10.dp)
      ) {
        if (historyNode != null) {
          Surface(
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(12.dp),
            color = IosParityColors.Surface,
            border = BorderStroke(1.dp, historyOrigin?.let { requestKindColor(it) } ?: IosParityColors.SurfaceBorder),
          ) {
            Column(Modifier.padding(16.dp)) {
              Text(if (historyNode.role == "user") "用户" else "助手",
                fontWeight = FontWeight.Bold, color = IosParityColors.Text)
              Text(historyNode.content, color = IosParityColors.Text)
            }
          }
        } else if (displayRequest != null) {
          MessageCard(request = displayRequest, onImageClick = onImageClick)
        }
        if (displayRequest != null) {
          state.closedDraftKey?.let {key->
            Text(state.queryNotices[key] ?: state.queryDisabledReason(key) ?: "请查询原回复；已关闭请求不会重新发送")
          }
          activeQueryKey?.let{key->Text(state.queryNotices[key] ?: state.queryDisabledReason(key) ?: "结果未知；请查询原回复")}
          if (historyNode != null && state.request != null && closed == null) {
            Text("回复当前待回复请求 · ${state.request.conversationTitle}",
              fontWeight = FontWeight.Bold, color = IosParityColors.Text)
          }
          key(displayRequest.requestId, displayRequest.projectPath) {
            InputSection(
              value = closed?.text ?: state.userInput,
              predefinedOptions = displayRequest.predefinedOptions,
              selectedOptions = closed?.selectedOptions ?: state.selectedOptions,
              quickTemplates = state.quickTemplates,
              templateRefreshing = state.templateRefreshing,
              templateNotice = state.templateNotice,
              onValueChange = onUserInputChange,
              onOptionClick = onOptionClick,
              onInsertTemplate = onInsertTemplate,
              onRefreshTemplates = onRefreshTemplates,
              readOnly = closed!=null || (unknown&&displayRequest.origin==RequestOrigin.Native) || state.sending,
            )
          }
        }
      }
      }
      if (displayRequest != null) {
        FooterBar(
          voiceState = state.voiceState,
          onVoiceClick = onVoiceClick,
          onContinueClick = if(closed!=null)onCopyClosedDraft else onContinueClick,
          onSubmitClick = if(closed!=null || (unknown&&displayRequest.origin==RequestOrigin.Native))onQueryOriginalReply else onSubmitClick,
          enabled = if(closed!=null)state.closedDraftKey?.let{state.queryDisabledReason(it)==null}==true else if(activeQueryKey!=null)state.queryDisabledReason(activeQueryKey)==null else state.paired && state.connectionState == BridgeConnectionState.Connected && !state.sending,
          continueEnabled = if(closed!=null)state.closedDraftKey in state.queryConfirmedKeys else state.canSendContinue,
          submitLabel = if(closed!=null||(unknown&&displayRequest.origin==RequestOrigin.Native))"查询原回复" else "确认",
          continueLabel = if(closed!=null)"复制草稿" else "继续",
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
        state.drafts.filter{(key,draft)->key in state.closedRequestKeys&&draft.unconfirmedAction!=null}.forEach{(key,draft)->
          Column(Modifier.fillMaxWidth().border(BorderStroke(1.dp, computerPlatformColor(draft.requestSnapshot?.sourceComputerPlatform)), RoundedCornerShape(8.dp)).clickable{onSelectClosedDraft(key);showProjectPicker=false}.padding(vertical=12.dp,horizontal=4.dp)){
            Text("已关闭·待核实",fontWeight=FontWeight.Bold)
            Text(draft.requestSnapshot?.message?.take(100).orEmpty(),maxLines=2)
            Text(key.second,color=IosParityColors.TextSecondary)
          }
        }
        visibleRequests.forEach { candidate ->
          val current = state.request?.requestId == candidate.requestId &&
            state.request?.projectPath == candidate.projectPath
          val pending = state.pendingAction?.requestId == candidate.requestId &&
            state.pendingAction?.projectPath == candidate.projectPath
          Column(
            modifier = Modifier
              .fillMaxWidth()
              .border(BorderStroke(1.dp, computerPlatformColor(candidate.sourceComputerPlatform)), RoundedCornerShape(8.dp))
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
        if (state.nativeHistorySessions.isNotEmpty()) {
          Text("CLI 历史", fontWeight = FontWeight.Bold, modifier = Modifier.padding(top = 12.dp, bottom = 4.dp))
          state.nativeHistorySessions.forEach { session ->
            Column(Modifier.fillMaxWidth().clickable {
              onSelectNativeHistory(session)
              showProjectPicker = false
            }.padding(vertical = 10.dp, horizontal = 4.dp)) {
              Text(session.title, fontWeight = FontWeight.Bold, maxLines = 2)
              Text("${session.projectPath} · ${session.threadId.take(8)} / ${session.launchId.take(8)}",
                color = IosParityColors.TextSecondary, maxLines = 2)
            }
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
      val native = request.origin == RequestOrigin.Native
      Surface(
        modifier = Modifier
          .widthIn(min = 112.dp, max = 156.dp)
          .heightIn(min = 40.dp)
          .clickable { onSelect(request) },
        shape = RoundedCornerShape(8.dp),
        color = when {
          native && active -> IosParityColors.Warning
          native -> IosParityColors.Warning.copy(alpha = 0.16f)
          active -> IosParityColors.PrimaryButton
          else -> IosParityColors.Surface
        },
        border = BorderStroke(1.dp, computerPlatformColor(request.sourceComputerPlatform)),
      ) {
        Column(modifier = Modifier.padding(horizontal = 9.dp, vertical = 5.dp)) {
          Text(
            request.conversationTitle,
            color = when {
              native && active -> Color(0xFF1F2937)
              active -> IosParityColors.OnPrimaryButton
              else -> IosParityColors.Text
            },
            fontWeight = FontWeight.Bold,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
          )
        }
      }
    }
  }
}
