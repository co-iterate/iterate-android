package com.kexin94yyds.iterate.mobile

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Base64
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.ui.Alignment
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.ByteArrayOutputStream
import java.net.URLEncoder

internal fun isWithinRoot(path: String, root: String): Boolean =
  path == root || path.startsWith(root.trimEnd('/') + "/")

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun WorkbenchTools(
  state: WorkbenchUiState,
  onImagesChange: (List<DraftImage>) -> Unit,
  onProjectSelect: (ActiveProject) -> Unit,
  onUserInputChange: (String) -> Unit,
  preview: Boolean,
  content: @Composable (projects: () -> Unit, image: () -> Unit, path: () -> Unit) -> Unit,
) {
  val context = LocalContext.current
  val scope = rememberCoroutineScope()
  val client = remember { BridgeClient() }
  val latestState by rememberUpdatedState(state)
  var sheet by remember { mutableStateOf<String?>(null) }
  var directory by remember { mutableStateOf("") }
  var roots by remember { mutableStateOf<List<String>>(emptyList()) }
  var projects by remember { mutableStateOf<List<ActiveProject>>(emptyList()) }
  var files by remember { mutableStateOf<List<String>>(emptyList()) }
  var query by remember { mutableStateOf("") }
  var error by remember { mutableStateOf<String?>(null) }
  var loading by remember { mutableStateOf(false) }
  var revision by remember { mutableIntStateOf(0) }
  var imageError by remember { mutableStateOf<String?>(null) }
  var pathRoute by remember { mutableStateOf<Pair<String?, String?>?>(null) }
  var pickingRoute by remember { mutableStateOf<Pair<String?, String?>?>(null) }
  val picker = rememberLauncherForActivityResult(ActivityResultContracts.GetContent()) { uri ->
    val importedRoute = pickingRoute
    if (uri != null) scope.launch {
      runCatching {
        withContext(Dispatchers.IO) {
          val bytes = context.contentResolver.openInputStream(uri)?.use { stream ->
            val bytes = stream.readBytesLimited(20 * 1024 * 1024)
            bytes
          } ?: error("无法读取图片")
          val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
          BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
          require(bounds.outWidth > 0 && bounds.outHeight > 0) { "不支持此图片格式" }
          val options = BitmapFactory.Options().apply {
            inSampleSize = 1
            while (maxOf(bounds.outWidth, bounds.outHeight) / inSampleSize > 1600) inSampleSize *= 2
          }
          val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size, options) ?: error("图片解码失败")
          val output = ByteArrayOutputStream()
          bitmap.compress(Bitmap.CompressFormat.JPEG, 80, output)
          bitmap.recycle()
          DraftImage("data:image/jpeg;base64," + Base64.encodeToString(output.toByteArray(), Base64.NO_WRAP), "image_${System.currentTimeMillis()}.jpg")
        }
      }.onSuccess { image ->
        val current = latestState
        if (importedRoute != (current.request?.projectPath to current.request?.requestId)) imageError = "项目已切换，请在当前项目重新选择图片"
        else if (current.images.size >= 4) imageError = "每次最多添加 4 张图片"
        else onImagesChange(current.images + image)
      }.onFailure { imageError = it.message ?: "图片读取失败" }
    }
  }
  LaunchedEffect(sheet, directory, revision) {
    if (sheet == null) return@LaunchedEffect
    loading = true; error = null
    try {
      if (sheet == "projects") {
        projects = if (preview) listOf(
          ActiveProject("/preview/iterate", "ui-preview-only", "iterate · 预览", "安卓界面，与 iOS 对齐"),
          ActiveProject("/preview/notes", "ui-preview-notes", "notes · 预览", "整理今天的记录"),
        ) else {
          val data = client.readJson("/api/active-sessions").optJSONArray("sessions")
          (0 until (data?.length() ?: 0)).mapNotNull { i ->
            val item = data!!.getJSONObject(i)
            val path = item.optString("project_path")
            val id = item.optString("request_id")
            if (path.isBlank() || id.isBlank()) null else ActiveProject(path, id,
              item.optString("project_name").ifBlank { path.substringAfterLast('/') }, item.optString("title"))
          }
        }
      } else {
        if (directory.isEmpty()) {
          roots = if (preview) listOf("/preview") else {
            val data = client.readJson("/files/roots").optJSONArray("roots")
            (0 until (data?.length() ?: 0)).map { data!!.getString(it).trimEnd('/').ifEmpty { "/" } }
          }
          require(roots.isNotEmpty()) { "电脑尚未开放可浏览的目录" }
          directory = state.request?.projectPath?.takeIf { path -> roots.any { isWithinRoot(path, it) } } ?: roots.first()
        } else {
          require(roots.any { isWithinRoot(directory, it) }) { "目录超出允许范围" }
          files = if (preview) listOf("docs/", "README.md", "notes.md") else {
            val data = client.readJson("/files?project_path=${URLEncoder.encode(directory, "UTF-8")}&max_depth=0").optJSONArray("files")
            (0 until (data?.length() ?: 0)).map { data!!.getString(it) }
              .filter { it.trimEnd('/').isNotEmpty() && !it.startsWith('/') && it.trimEnd('/').split('/').none { part -> part == ".." || part == "." } }
          }
        }
      }
    } catch (cancelled: kotlinx.coroutines.CancellationException) { throw cancelled }
    catch (failure: Exception) { error = failure.message ?: "读取失败" }
    finally { loading = false }
  }
  fun insertPath(path: String) {
    if (pathRoute != (latestState.request?.projectPath to latestState.request?.requestId)) {
      error = "会话已变化，请关闭并重新选择路径"
      return
    }
    onUserInputChange(listOf(latestState.userInput, "@$path").filter { it.isNotBlank() }.joinToString(" "))
    sheet = null
  }
  content(
    { sheet = "projects"; query = ""; revision++ },
    { pickingRoute = state.request?.projectPath to state.request?.requestId; picker.launch("image/*") },
    { pathRoute = state.request?.projectPath to state.request?.requestId; directory = ""; files = emptyList(); query = ""; sheet = "paths"; revision++ },
  )
  imageError?.let { message -> AlertDialog(containerColor = WorkbenchTheme.colors.background, onDismissRequest = { imageError = null }, text = { Text(message) }, confirmButton = { TextButton(onClick = { imageError = null }) { Text("知道了") } }) }
  val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
  if (sheet != null) ModalBottomSheet(sheetState = sheetState, onDismissRequest = { sheet = null }, containerColor = WorkbenchTheme.colors.background) {
    Column(Modifier.fillMaxWidth()
      .then(if (sheet == "projects") Modifier.fillMaxHeight(0.94f).testTag("active_project_sheet") else Modifier.heightIn(max = 560.dp))
      .padding(horizontal = 20.dp)) {
      Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Text(if (sheet == "projects") "活跃项目" else "选择路径", fontSize = 18.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
        IconButton(onClick = { sheet = null }) {
          Icon(Icons.Default.Close, if (sheet == "projects") "关闭活跃项目" else "关闭路径选择", Modifier.size(19.dp), tint = WorkbenchTheme.colors.secondaryText)
        }
      }
      if (preview) Text("本地预览 · 以下为示例数据", fontSize = 11.sp, color = WorkbenchTheme.colors.secondaryText, modifier = Modifier.padding(bottom = 12.dp))
      Column(Modifier.fillMaxWidth().weight(1f, fill = sheet == "projects").verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(8.dp)) {
      if (sheet == "paths") OutlinedTextField(value = query, onValueChange = { query = it }, placeholder = { Text("搜索") }, singleLine = true, modifier = Modifier.fillMaxWidth())
      if (loading) LinearProgressIndicator(Modifier.fillMaxWidth())
      error?.let { Text(it, color = WorkbenchTheme.colors.error); TextButton(onClick = { revision++ }) { Text("重试") } }
      if (!loading && error == null && sheet == "projects") {
        if (projects.isEmpty()) Text("暂无活跃项目")
        projects.filter { query.isBlank() || "${it.name} ${it.title} ${it.path}".contains(query, true) }.forEach { project ->
          Column(Modifier.fillMaxWidth().clickable { onProjectSelect(project); sheet = null }.padding(vertical = 10.dp), verticalArrangement = Arrangement.spacedBy(5.dp)) {
            Text(project.name + if (project.path == state.request?.projectPath && project.requestId == state.request?.requestId) " · 当前" else "", fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
            if (project.title.isNotBlank()) Text(project.title, fontSize = 12.sp, lineHeight = 18.sp, maxLines = 2, overflow = TextOverflow.Ellipsis)
            Text(project.path, fontSize = 10.sp, maxLines = 1, overflow = TextOverflow.Ellipsis, color = WorkbenchTheme.colors.secondaryText)
          }
          HorizontalDivider(color = WorkbenchTheme.colors.border)
        }
      }
      if (sheet == "paths" && directory.isNotBlank()) {
        Text(directory, fontSize = 12.sp)
        Row {
          val parent = directory.substringBeforeLast('/', "").ifBlank { "/" }
          TextButton(enabled = roots.any { isWithinRoot(parent, it) } && parent != directory, onClick = { directory = parent; query = "" }) { Text("上一级") }
          TextButton(enabled = !loading && error == null, onClick = { insertPath(directory) }) { Text("使用当前目录") }
        }
        if (!loading && error == null) {
          if (files.isEmpty()) Text("此目录为空")
          files.filter { it.contains(query, true) }.forEach { file ->
            Text((if (file.endsWith('/')) "▸  " else "     ") + file, modifier = Modifier.fillMaxWidth().clickable {
              val fullPath = directory.trimEnd('/') + "/" + file.trimEnd('/')
              if (file.endsWith('/')) { directory = fullPath; query = "" } else insertPath(fullPath)
            }.padding(vertical = 16.dp), fontSize = 14.sp)
          }
        }
      }
      Spacer(Modifier.height(24.dp))
      }
    }
  }
}

private fun java.io.InputStream.readBytesLimited(limit: Int): ByteArray {
  val output = ByteArrayOutputStream()
  val buffer = ByteArray(8192)
  while (true) {
    val count = read(buffer)
    if (count < 0) break
    require(output.size() + count <= limit) { "请选择小于 20 MB 的图片" }
    output.write(buffer, 0, count)
  }
  return output.toByteArray()
}

@Composable
fun DraftImages(images: List<DraftImage>, onChange: (List<DraftImage>) -> Unit) {
  if (images.isEmpty()) return
  Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
    images.forEach { image ->
      val bitmap = remember(image.data) {
        val bytes = Base64.decode(image.data.substringAfter(','), Base64.DEFAULT)
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
      }
      Column {
        if (bitmap != null) Image(bitmap.asImageBitmap(), "待发送图片", Modifier.size(60.dp))
        TextButton(onClick = { onChange(images - image) }) { Text("移除", fontSize = 11.sp) }
      }
    }
  }
}
