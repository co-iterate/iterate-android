package com.kexin94yyds.iterate.mobile

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.ime
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithCache
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

@Composable
fun FooterBar(
  voiceState: VoiceInputState,
  actionsEnabled: Boolean,
  onVoiceClick: () -> Unit,
  onGoalClick: () -> Unit,
  onSubmitClick: () -> Unit,
) {
  val colors = WorkbenchTheme.colors
  val keyboardVisible = WindowInsets.ime.getBottom(LocalDensity.current) > 0
  Column(
    modifier = Modifier
      .testTag("workbench_footer")
      .fillMaxWidth()
      .drawWithCache {
        val top = if (keyboardVisible) 0f else 78.dp.toPx()
        val radius = 66.dp.toPx()
        val edge = Path().apply {
          moveTo(0f, top)
          if (!keyboardVisible) {
            lineTo(size.width / 2 - radius, top)
            arcTo(Rect(size.width / 2 - radius, top - radius, size.width / 2 + radius, top + radius), 180f, 180f, false)
          }
          lineTo(size.width, top)
        }
        val surface = Path().apply {
          addPath(edge)
          lineTo(size.width, size.height)
          lineTo(0f, size.height)
          close()
        }
        onDrawBehind {
          drawPath(surface, colors.secondaryBackground)
          drawPath(edge, colors.border.copy(alpha = 0.65f), style = Stroke(0.75.dp.toPx()))
        }
      },
    horizontalAlignment = Alignment.CenterHorizontally,
  ) {
    if (!keyboardVisible) {
      Box(Modifier.fillMaxWidth().height(78.dp), contentAlignment = Alignment.BottomCenter) {
        MicrophoneButton(voiceState, onVoiceClick)
      }
    }
    Row(
      modifier = Modifier.fillMaxWidth().padding(16.dp),
      horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
      FooterAction("∞", "目标", actionsEnabled, onGoalClick, Modifier.weight(1f).testTag("goal_action"))
      FooterAction("确认", "确认", actionsEnabled, onSubmitClick, Modifier.weight(1f).testTag("confirm_action"))
    }
  }
}

@Composable
private fun FooterAction(
  title: String,
  accessibilityLabel: String,
  enabled: Boolean,
  onClick: () -> Unit,
  modifier: Modifier,
) {
  val colors = WorkbenchTheme.colors
  Surface(
    onClick = onClick,
    enabled = enabled,
    modifier = modifier.semantics { contentDescription = accessibilityLabel },
    color = colors.background,
    shape = RoundedCornerShape(8.dp),
    border = BorderStroke(0.75.dp, colors.border),
    shadowElevation = 1.dp,
  ) {
    Box(Modifier.heightIn(min = 48.dp).padding(horizontal = 12.dp, vertical = 10.dp), contentAlignment = Alignment.Center) {
      if (title == "∞") {
        InfinityMark(pointSize = 22f, color = colors.text.copy(alpha = if (enabled) 1f else 0.38f))
      } else {
        Text(title, fontSize = 14.sp, fontWeight = FontWeight.SemiBold,
          color = colors.text.copy(alpha = if (enabled) 1f else 0.38f))
      }
    }
  }
}
