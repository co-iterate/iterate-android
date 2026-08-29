package com.kexin94yyds.iterate.mobile

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

object IosParityColors {
  val Background = Color(0xFFFAFAFB)
  val Footer = Color(0xFFF7F8FA)
  val Surface = Color(0xFFF8FAFC)
  val SurfaceBorder = Color(0xFFE5E7EB)
  val FocusBorder = Color(0xFFBFD7FF)
  val Text = Color(0xFF1F2937)
  val TextSecondary = Color(0xFF7B8494)
  val IconCircle = Color(0xFFF1F3F7)
  val Connected = Color(0xFF10B981)
  val Warning = Color(0xFFF59E0B)
  val PrimaryButton = Color(0xFF000000)
}

private val IosParityColorScheme = lightColorScheme(
  primary = IosParityColors.PrimaryButton,
  onPrimary = Color.White,
  surface = IosParityColors.Background,
  onSurface = IosParityColors.Text,
  surfaceVariant = IosParityColors.Surface,
  onSurfaceVariant = IosParityColors.TextSecondary,
  outline = IosParityColors.SurfaceBorder,
)

@Composable
fun AndroidMobileTheme(content: @Composable () -> Unit) {
  MaterialTheme(
    colorScheme = IosParityColorScheme,
    typography = Typography(),
    content = content,
  )
}
