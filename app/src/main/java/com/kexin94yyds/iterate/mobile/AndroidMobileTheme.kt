package com.kexin94yyds.iterate.mobile

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

private val lightScheme = lightColorScheme(
  primary = Color.Black,
  onPrimary = Color.White,
  background = Color.White,
  onBackground = Color(0xFF1F2937),
  surface = Color(0xFFF3F4F6),
  onSurface = Color(0xFF1F2937),
  surfaceVariant = Color(0xFFF9FAFB),
  onSurfaceVariant = Color(0xFF6B7280),
  outline = Color(0xFFE5E7EB),
  outlineVariant = Color(0xFFD1D5DB),
  secondary = Color(0xFF3B82F6),
  tertiary = Color(0xFF10B981),
)

private val darkScheme = darkColorScheme(
  primary = Color.White,
  onPrimary = Color.Black,
  background = Color.Black,
  onBackground = Color.White,
  surface = Color(0xFF1A1A1A),
  onSurface = Color.White,
  surfaceVariant = Color(0xFF111111),
  onSurfaceVariant = Color(0xFF9CA3AF),
  outline = Color(0xFF333333),
  outlineVariant = Color(0xFF444444),
  secondary = Color(0xFF3B82F6),
  tertiary = Color(0xFF10B981),
)

object IosParityColors {
  val Background: Color @Composable get() = MaterialTheme.colorScheme.background
  val Footer: Color @Composable get() = MaterialTheme.colorScheme.surfaceVariant
  val Surface: Color @Composable get() = MaterialTheme.colorScheme.surface
  val SurfaceBorder: Color @Composable get() = MaterialTheme.colorScheme.outline
  val FocusBorder: Color @Composable get() = MaterialTheme.colorScheme.outlineVariant
  val Text: Color @Composable get() = MaterialTheme.colorScheme.onBackground
  val TextSecondary: Color @Composable get() = MaterialTheme.colorScheme.onSurfaceVariant
  val IconCircle: Color @Composable get() = MaterialTheme.colorScheme.surfaceVariant
  val Connected = Color(0xFF10B981)
  val Warning = Color(0xFFF59E0B)
  val PrimaryButton: Color @Composable get() = MaterialTheme.colorScheme.primary
  val OnPrimaryButton: Color @Composable get() = MaterialTheme.colorScheme.onPrimary
}

@Composable
fun AndroidMobileTheme(lightAppearance: Boolean = true, content: @Composable () -> Unit) {
  MaterialTheme(
    colorScheme = if (lightAppearance) lightScheme else darkScheme,
    typography = Typography(),
    content = content,
  )
}
