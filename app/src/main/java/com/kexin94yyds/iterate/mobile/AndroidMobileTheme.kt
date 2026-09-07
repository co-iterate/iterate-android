package com.kexin94yyds.iterate.mobile

import android.app.Activity
import android.os.Build
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.enableEdgeToEdge
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp

@Immutable
data class WorkbenchColors(
  val background: Color,
  val secondaryBackground: Color,
  val card: Color,
  val text: Color,
  val secondaryText: Color,
  val border: Color,
  val active: Color,
  val onActive: Color,
  val accent: Color = Color(0xFF3B82F6),
  val success: Color = Color(0xFF10B981),
  val warning: Color = Color(0xFFF59E0B),
  val error: Color = Color(0xFFEF4444),
)

private val LightColors = WorkbenchColors(
  background = Color.White,
  secondaryBackground = Color(0xFFF9FAFB),
  card = Color(0xFFF3F4F6),
  text = Color(0xFF1F2937),
  secondaryText = Color(0xFF6B7280),
  border = Color(0xFFE5E7EB),
  active = Color.Black,
  onActive = Color.White,
)

private val DarkColors = WorkbenchColors(
  background = Color.Black,
  secondaryBackground = Color(0xFF111111),
  card = Color(0xFF1A1A1A),
  text = Color.White,
  secondaryText = Color(0xFF9CA3AF),
  border = Color(0xFF333333),
  active = Color.White,
  onActive = Color.Black,
)

private val LocalWorkbenchColors = staticCompositionLocalOf { LightColors }

object WorkbenchTheme {
  val colors: WorkbenchColors
    @Composable @ReadOnlyComposable get() = LocalWorkbenchColors.current
}

private val WorkbenchTypography = Typography(
  bodyLarge = TextStyle(fontSize = 14.sp, lineHeight = 22.sp),
  bodyMedium = TextStyle(fontSize = 14.sp, lineHeight = 22.sp),
  bodySmall = TextStyle(fontSize = 12.sp, lineHeight = 18.sp),
  titleMedium = TextStyle(fontSize = 14.sp, lineHeight = 20.sp, fontWeight = FontWeight.Bold),
  labelLarge = TextStyle(fontSize = 14.sp, lineHeight = 20.sp, fontWeight = FontWeight.SemiBold),
)

@Composable
fun AndroidMobileTheme(lightAppearance: Boolean = true, content: @Composable () -> Unit) {
  val colors = if (lightAppearance) LightColors else DarkColors
  val baseScheme = if (lightAppearance) lightColorScheme() else darkColorScheme()
  CompositionLocalProvider(LocalWorkbenchColors provides colors) {
    MaterialTheme(
      colorScheme = baseScheme.copy(
        primary = colors.active,
        onPrimary = colors.onActive,
        background = colors.background,
        onBackground = colors.text,
        surface = colors.background,
        onSurface = colors.text,
        surfaceVariant = colors.card,
        onSurfaceVariant = colors.secondaryText,
        outline = colors.border,
      ),
      typography = WorkbenchTypography,
      content = content,
    )
  }
}

@Composable
fun WorkbenchSystemBars(activity: Activity?, lightAppearance: Boolean) {
  SideEffect {
    val host = activity as? ComponentActivity ?: return@SideEffect
    val style = if (lightAppearance) {
      SystemBarStyle.light(android.graphics.Color.TRANSPARENT, android.graphics.Color.TRANSPARENT)
    } else {
      SystemBarStyle.dark(android.graphics.Color.TRANSPARENT)
    }
    host.enableEdgeToEdge(statusBarStyle = style, navigationBarStyle = style)
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
      host.window.isNavigationBarContrastEnforced = false
    }
  }
}
