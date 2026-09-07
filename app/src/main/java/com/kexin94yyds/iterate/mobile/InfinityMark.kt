package com.kexin94yyds.iterate.mobile

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathFillType
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.unit.dp

/** Fixed infinity artwork matching the iOS-style mark with a lighter optical weight. */
@Composable
fun InfinityMark(pointSize: Float, color: Color, modifier: Modifier = Modifier) {
  val outline = remember { infinityOutline() }
  Canvas(modifier.size((16.6986f * pointSize / 20f).dp, (8.0362f * pointSize / 20f).dp)) {
    scale(size.width / 16.6986f, size.height / 8.0362f, pivot = androidx.compose.ui.geometry.Offset.Zero) {
      drawPath(outline, color)
    }
  }
}

private fun infinityOutline() = Path().apply {
  fillType = PathFillType.EvenOdd
  moveTo(4.0765f, 8.0362f)
  quadraticBezierTo(2.9108f, 8.0362f, 1.9886f, 7.5069f)
  quadraticBezierTo(1.0664f, 6.9777f, 0.5332f, 6.0715f)
  quadraticBezierTo(0.0000f, 5.1654f, 0.0000f, 4.0279f)
  lineTo(0.0000f, 4.0083f)
  quadraticBezierTo(0.0000f, 2.8708f, 0.5332f, 1.9637f)
  quadraticBezierTo(1.0664f, 1.0567f, 1.9886f, 0.5283f)
  quadraticBezierTo(2.9108f, 0.0000f, 4.0765f, 0.0000f)
  quadraticBezierTo(5.2245f, 0.0000f, 6.1877f, 0.5637f)
  quadraticBezierTo(7.1510f, 1.1273f, 8.2233f, 2.4593f)
  lineTo(8.3493f, 2.6147f)
  lineTo(8.4755f, 2.4593f)
  quadraticBezierTo(9.5476f, 1.1273f, 10.5109f, 0.5637f)
  quadraticBezierTo(11.4742f, 0.0000f, 12.6221f, 0.0000f)
  quadraticBezierTo(13.7898f, 0.0000f, 14.7110f, 0.5283f)
  quadraticBezierTo(15.6322f, 1.0567f, 16.1654f, 1.9637f)
  quadraticBezierTo(16.6986f, 2.8708f, 16.6986f, 4.0083f)
  lineTo(16.6986f, 4.0279f)
  quadraticBezierTo(16.6986f, 5.1654f, 16.1654f, 6.0715f)
  quadraticBezierTo(15.6322f, 6.9777f, 14.7110f, 7.5069f)
  quadraticBezierTo(13.7898f, 8.0362f, 12.6221f, 8.0362f)
  quadraticBezierTo(11.4742f, 8.0362f, 10.5109f, 7.4677f)
  quadraticBezierTo(9.5476f, 6.8991f, 8.4755f, 5.5769f)
  lineTo(8.3493f, 5.4214f)
  lineTo(8.2233f, 5.5769f)
  quadraticBezierTo(7.1510f, 6.8991f, 6.1877f, 7.4677f)
  quadraticBezierTo(5.2245f, 8.0362f, 4.0765f, 8.0362f)
  close()
  moveTo(4.1817f, 6.2112f)
  quadraticBezierTo(4.6848f, 6.2112f, 5.1266f, 6.0147f)
  quadraticBezierTo(5.5685f, 5.8182f, 6.0423f, 5.3724f)
  quadraticBezierTo(6.5161f, 4.9266f, 7.1230f, 4.1699f)
  lineTo(7.2455f, 4.0181f)
  lineTo(7.1230f, 3.8663f)
  quadraticBezierTo(6.5161f, 3.1096f, 6.0423f, 2.6638f)
  quadraticBezierTo(5.5685f, 2.2180f, 5.1266f, 2.0215f)
  quadraticBezierTo(4.6848f, 1.8250f, 4.1817f, 1.8250f)
  quadraticBezierTo(3.5385f, 1.8250f, 3.0399f, 2.1101f)
  quadraticBezierTo(2.5412f, 2.3953f, 2.2560f, 2.8851f)
  quadraticBezierTo(1.9708f, 3.3748f, 1.9708f, 4.0083f)
  lineTo(1.9708f, 4.0279f)
  quadraticBezierTo(1.9708f, 4.6533f, 2.2560f, 5.1471f)
  quadraticBezierTo(2.5412f, 5.6409f, 3.0399f, 5.9261f)
  quadraticBezierTo(3.5385f, 6.2112f, 4.1817f, 6.2112f)
  close()
  moveTo(12.5169f, 6.2112f)
  quadraticBezierTo(13.1619f, 6.2112f, 13.6597f, 5.9261f)
  quadraticBezierTo(14.1574f, 5.6409f, 14.4427f, 5.1471f)
  quadraticBezierTo(14.7279f, 4.6533f, 14.7279f, 4.0279f)
  lineTo(14.7279f, 4.0083f)
  quadraticBezierTo(14.7279f, 3.3748f, 14.4427f, 2.8851f)
  quadraticBezierTo(14.1574f, 2.3953f, 13.6597f, 2.1101f)
  quadraticBezierTo(13.1619f, 1.8250f, 12.5169f, 1.8250f)
  quadraticBezierTo(12.0139f, 1.8250f, 11.5720f, 2.0215f)
  quadraticBezierTo(11.1301f, 2.2180f, 10.6572f, 2.6638f)
  quadraticBezierTo(10.1843f, 3.1096f, 9.5758f, 3.8663f)
  lineTo(9.4531f, 4.0181f)
  lineTo(9.5758f, 4.1699f)
  quadraticBezierTo(10.1843f, 4.9266f, 10.6572f, 5.3724f)
  quadraticBezierTo(11.1301f, 5.8182f, 11.5720f, 6.0147f)
  quadraticBezierTo(12.0139f, 6.2112f, 12.5169f, 6.2112f)
  close()
}
