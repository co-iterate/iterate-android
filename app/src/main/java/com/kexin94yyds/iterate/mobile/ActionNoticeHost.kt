package com.kexin94yyds.iterate.mobile

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SnackbarDuration
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.withTimeoutOrNull

@Composable
internal fun ActionNoticeHost(
  notice: String?,
  onConsumed: (String) -> Unit,
  modifier: Modifier = Modifier,
) {
  val host = remember { SnackbarHostState() }
  LaunchedEffect(notice) {
    if (notice == null) return@LaunchedEffect
    actionNoticeForDisplay(notice)?.let { message ->
      withTimeoutOrNull(3_000) {
        host.showSnackbar(message, duration = SnackbarDuration.Indefinite)
      }
    }
    onConsumed(notice)
  }
  SnackbarHost(hostState = host, modifier = modifier) { data ->
    Surface(
      shape = RoundedCornerShape(12.dp),
      color = IosParityColors.Surface,
      border = BorderStroke(0.5.dp, IosParityColors.SurfaceBorder),
      shadowElevation = 2.dp,
    ) {
      Text(
        text = data.visuals.message,
        modifier = Modifier.padding(horizontal = 14.dp, vertical = 10.dp),
        color = IosParityColors.TextSecondary,
        style = MaterialTheme.typography.bodyMedium,
      )
    }
  }
}
