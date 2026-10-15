package com.kexin94yyds.iterate.mobile

import android.widget.TextView
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import io.noties.markwon.Markwon

/** CommonMark rendering without HTML or network image plugins; images keep their existing buttons. */
@Composable
internal fun MarkdownMessage(message: String) {
  val context = LocalContext.current
  val markwon = remember(context) { Markwon.create(context) }
  val rendered = remember(markwon, message) { markwon.toMarkdown(message) }
  val textColor = IosParityColors.Text.toArgb()
  val textSizePx = with(LocalDensity.current) { 16.sp.toPx() }
  val lineSpacingPx = with(LocalDensity.current) { 2.sp.toPx() }

  AndroidView(
    modifier = Modifier.fillMaxWidth(),
    factory = { TextView(it).apply { includeFontPadding = false } },
    update = { view ->
      view.setTextColor(textColor)
      view.setLinkTextColor(textColor)
      view.setTextSize(android.util.TypedValue.COMPLEX_UNIT_PX, textSizePx)
      view.setLineSpacing(lineSpacingPx, 1f)
      markwon.setParsedMarkdown(view, rendered)
    },
  )
}
