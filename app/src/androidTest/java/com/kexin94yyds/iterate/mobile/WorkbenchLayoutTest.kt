package com.kexin94yyds.iterate.mobile

import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertIsOn
import androidx.compose.ui.test.assertTextContains
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.graphics.toPixelMap
import androidx.test.platform.app.InstrumentationRegistry
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import android.graphics.Bitmap
import java.io.File

class WorkbenchLayoutTest {
  @get:Rule
  val compose = createAndroidComposeRule<WorkbenchPreviewActivity>()

  @Test
  fun activeProjectsOpenAndSelectExactPreviewRequest() {
    compose.onNodeWithText("iterate · 预览").performClick()
    compose.onNodeWithText("活跃项目").assertExists()
    compose.waitUntil(5000) { compose.onAllNodesWithText("notes · 预览").fetchSemanticsNodes().isNotEmpty() }
    compose.onAllNodesWithText("搜索").assertCountEquals(0)
    compose.onNodeWithText("notes · 预览").assertExists()
    val sheet = compose.onNodeWithTag("active_project_sheet").fetchSemanticsNode().boundsInWindow
    val screenHeight = compose.activity.window.decorView.height
    assertTrue("Active projects did not fully expand", sheet.top < screenHeight * 0.25f && sheet.height > screenHeight * 0.65f)
    saveScreenshot("active-projects.png")
    compose.onNodeWithText("notes · 预览").performClick()
    compose.onNodeWithText("整理今天的记录").assertExists()
  }

  @Test
  fun selectedFileAppendsToExistingDraft() {
    compose.onNodeWithTag("reply_editor").performScrollTo().performTextInput("请看")
    compose.onNodeWithText("路径").performScrollTo().performClick()
    compose.waitUntil(5000) { compose.onAllNodesWithText("     README.md").fetchSemanticsNodes().isNotEmpty() }
    saveScreenshot("path-selector.png")
    compose.onNodeWithText("     README.md").performClick()
    compose.onNodeWithTag("reply_editor").assertTextContains("请看 @/preview/iterate/README.md")
  }

  @Test
  fun confirmActionClearsSystemNavigationBar() {
    val confirm = compose.onNodeWithText("确认").fetchSemanticsNode().boundsInWindow
    var safeBottom = 0
    compose.runOnUiThread {
      val decor = compose.activity.window.decorView
      val nav = ViewCompat.getRootWindowInsets(decor)
        ?.getInsets(WindowInsetsCompat.Type.navigationBars())?.bottom ?: 0
      safeBottom = decor.height - nav
    }
    assertTrue("Confirm overlaps Android navigation: $confirm / $safeBottom", confirm.bottom <= safeBottom)
  }

  @Test
  fun themeToggleChangesTheRenderedBackground() {
    val light = androidx.core.graphics.ColorUtils.calculateLuminance(screenBitmap().getPixel(2, 150))
    compose.onNodeWithContentDescription("切换到深色模式").performClick()
    val dark = androidx.core.graphics.ColorUtils.calculateLuminance(screenBitmap().getPixel(2, 150))
    assertTrue("Light background not rendered: $light", light > 0.9f)
    assertTrue("Dark toggle did not repaint the UI: $dark", dark < 0.05f)
  }

  @Test
  fun requestRendersMarkdownWithoutInjectedValidationResults() {
    compose.onNodeWithText("安卓界面，与 iOS 对齐").assertExists()
    compose.onAllNodesWithText("DMG notarization", substring = true).assertCountEquals(0)
  }

  @Test
  fun quotePreservesTheUsersDraft() {
    compose.onNodeWithTag("reply_editor").performScrollTo().performTextInput("我的补充")
    compose.onNodeWithText("引用原文").performScrollTo().performClick()
    compose.onNodeWithTag("reply_editor").assertTextContains("我的补充\n\n" + WorkbenchPreviewActivity.sampleRequest.message)
  }

  @Test
  fun optionsRemainIndependentlySelectable() {
    compose.onNodeWithText("看看深色模式").performScrollTo().performClick().assertIsOn()
    compose.onNodeWithText("试试回复和选项").performScrollTo().performClick().assertIsOn()
    compose.onNodeWithText("看看深色模式").assertIsOn()
    saveScreenshot("composer-options-light.png")
    compose.onNodeWithContentDescription("切换到深色模式").performClick()
    saveScreenshot("composer-options-dark.png")
  }

  @Test
  fun keyboardDoesNotCoverConfirmOrGoal() {
    compose.onNodeWithTag("reply_editor").performScrollTo().performTextInput("键盘弹出后，底部操作仍可使用。")
    var keyboardTop = 0
    var lastLayout = ""
    try { compose.waitUntil(timeoutMillis = 5_000) {
      var bottom = 0
      compose.runOnUiThread {
        val decor = compose.activity.window.decorView
        bottom = ViewCompat.getRootWindowInsets(decor)?.getInsets(WindowInsetsCompat.Type.ime())?.bottom ?: 0
        keyboardTop = decor.height - bottom
      }
      // Android's IME insets arrive before the Compose layout animation has settled.
      // Wait for the visible action row, not only the first non-zero system inset.
      val confirmBottom = compose.onNodeWithTag("confirm_action").fetchSemanticsNode().boundsInWindow.bottom
      val goalBottom = compose.onNodeWithTag("goal_action").fetchSemanticsNode().boundsInWindow.bottom
      val editor = compose.onNodeWithTag("reply_editor").fetchSemanticsNode().boundsInWindow
      val confirmTop = compose.onNodeWithTag("confirm_action").fetchSemanticsNode().boundsInWindow.top
      val titleBottom = compose.onNodeWithText("iterate · 预览").fetchSemanticsNode().boundsInWindow.bottom
      lastLayout = "ime=$bottom keyboardTop=$keyboardTop editor=$editor confirmTop=$confirmTop confirmBottom=$confirmBottom titleBottom=$titleBottom"
      bottom > 0 && confirmBottom <= keyboardTop && goalBottom <= keyboardTop && editor.height > 100f && editor.top >= titleBottom && editor.bottom <= confirmTop
    } } catch (failure: Exception) {
      println(lastLayout)
      saveScreenshot("keyboard-failure.png")
      throw failure
    }
    compose.waitForIdle()
    val confirm = compose.onNodeWithTag("confirm_action").fetchSemanticsNode().boundsInWindow
    val goal = compose.onNodeWithTag("goal_action").fetchSemanticsNode().boundsInWindow
    assertTrue("Confirm overlaps keyboard: $confirm / $keyboardTop", confirm.bottom <= keyboardTop)
    assertTrue("Goal overlaps keyboard: $goal / $keyboardTop", goal.bottom <= keyboardTop)
    val editor = compose.onNodeWithTag("reply_editor").fetchSemanticsNode().boundsInWindow
    assertTrue("Reply editor is hidden by footer", editor.height > 100f && editor.bottom <= confirm.top)
    saveScreenshot("keyboard.png")
  }

  private fun screenBitmap(): Bitmap {
    compose.mainClock.advanceTimeBy(600)
    compose.waitForIdle()
    Thread.sleep(400)
    repeat(10) {
      val image = InstrumentationRegistry.getInstrumentation().uiAutomation.takeScreenshot()
      if (image != null) return image
      Thread.sleep(100)
    }
    error("Emulator screenshot unavailable")
  }

  private fun saveScreenshot(name: String) {
    compose.mainClock.advanceTimeBy(600)
    compose.waitForIdle()
    val image = screenBitmap()
    val directory = File(compose.activity.getExternalFilesDir(null), "ui-evidence").apply { mkdirs() }
    File(directory, name).outputStream().use { image.compress(Bitmap.CompressFormat.PNG, 100, it) }
  }
}
