package com.kexin94yyds.iterate.mobile

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLinkStyles
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.withLink
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import org.commonmark.ext.gfm.tables.TableBlock
import org.commonmark.ext.gfm.tables.TableCell
import org.commonmark.ext.gfm.tables.TablesExtension
import org.commonmark.node.BlockQuote
import org.commonmark.node.BulletList
import org.commonmark.node.Code
import org.commonmark.node.Emphasis
import org.commonmark.node.FencedCodeBlock
import org.commonmark.node.HardLineBreak
import org.commonmark.node.Heading
import org.commonmark.node.HtmlBlock
import org.commonmark.node.HtmlInline
import org.commonmark.node.Image
import org.commonmark.node.IndentedCodeBlock
import org.commonmark.node.Link
import org.commonmark.node.Node
import org.commonmark.node.OrderedList
import org.commonmark.node.Paragraph
import org.commonmark.node.SoftLineBreak
import org.commonmark.node.StrongEmphasis
import org.commonmark.node.ThematicBreak
import org.commonmark.node.Text as MarkdownText
import org.commonmark.parser.Parser
import java.net.URI

@Composable
fun RequestMarkdown(source: String) {
  val document = remember(source) {
    Parser.builder().extensions(listOf(TablesExtension.create())).build().parse(source)
  }
  MarkdownBlocks(document)
}

private fun Node.children(): List<Node> = generateSequence(firstChild) { it.next }.toList()

@Composable
private fun MarkdownBlocks(parent: Node) {
  val colors = WorkbenchTheme.colors
  Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
    parent.children().forEach { node ->
      when (node) {
        is Heading -> Text(
          inlineContent(node, colors),
          color = colors.text,
          fontWeight = FontWeight.Bold,
          fontSize = when (node.level) { 1 -> 20.sp; 2 -> 17.sp; else -> 15.sp },
          lineHeight = 25.sp,
        )
        is Paragraph -> Text(inlineContent(node, colors), color = colors.text, fontSize = 14.sp, lineHeight = 23.sp)
        is FencedCodeBlock -> MarkdownCodeBlock(node.literal.trimEnd('\n'), node.info.substringBefore(' '))
        is IndentedCodeBlock -> MarkdownCodeBlock(node.literal.trimEnd('\n'), "")
        is BulletList, is OrderedList -> Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
          node.children().forEachIndexed { index, item ->
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
              Text(if (node is OrderedList) "${node.startNumber + index}." else "•",
                fontSize = 14.sp, lineHeight = 23.sp, color = colors.secondaryText,
                modifier = Modifier.width(if (node is OrderedList) 24.dp else 10.dp))
              Box(Modifier.weight(1f)) { MarkdownBlocks(item) }
            }
          }
        }
        is BlockQuote -> Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
          Box(Modifier.size(height = 24.dp, width = 2.dp).background(colors.border))
          Box(Modifier.weight(1f)) { MarkdownBlocks(node) }
        }
        is ThematicBreak -> HorizontalDivider(color = colors.border)
        is HtmlBlock -> Text(node.literal, color = colors.secondaryText, fontSize = 13.sp)
        is TableBlock -> MarkdownTable(node)
        else -> MarkdownBlocks(node)
      }
    }
  }
}

private fun inlineContent(parent: Node, colors: WorkbenchColors): AnnotatedString = buildAnnotatedString {
  appendChildren(parent, colors)
}

private fun AnnotatedString.Builder.appendChildren(parent: Node, colors: WorkbenchColors) {
  parent.children().forEach { node ->
    when (node) {
      is MarkdownText -> append(node.literal)
      is Code -> withStyle(SpanStyle(fontFamily = FontFamily.Monospace, background = colors.background, fontSize = 13.sp)) {
        append(node.literal)
      }
      is StrongEmphasis -> withStyle(SpanStyle(fontWeight = FontWeight.Bold)) { appendChildren(node, colors) }
      is Emphasis -> withStyle(SpanStyle(fontStyle = FontStyle.Italic)) { appendChildren(node, colors) }
      is SoftLineBreak, is HardLineBreak -> append("\n")
      is HtmlInline -> append(node.literal)
      is Link -> appendSafeLink(node, node.destination, colors)
      is Image -> {
        append("图片 · ")
        appendSafeLink(node, node.destination, colors)
      }
      else -> appendChildren(node, colors)
    }
  }
}

private fun AnnotatedString.Builder.appendSafeLink(node: Node, destination: String, colors: WorkbenchColors) {
  val scheme = runCatching { URI(destination).scheme?.lowercase() }.getOrNull()
  if (scheme in setOf("https", "http", "mailto")) {
    withLink(LinkAnnotation.Url(destination, TextLinkStyles(SpanStyle(color = colors.accent, textDecoration = TextDecoration.Underline)))) {
      appendChildren(node, colors)
    }
  } else {
    appendChildren(node, colors)
  }
}

@Composable
private fun MarkdownCodeBlock(source: String, language: String) {
  val colors = WorkbenchTheme.colors
  val clipboard = LocalClipboardManager.current
  Surface(color = colors.secondaryBackground, shape = RoundedCornerShape(6.dp), border = BorderStroke(0.5.dp, colors.border)) {
    Column(Modifier.fillMaxWidth()) {
      Row(Modifier.fillMaxWidth().padding(start = 12.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(language, fontSize = 10.sp, color = colors.secondaryText, modifier = Modifier.weight(1f))
        IconButton(onClick = { clipboard.setText(AnnotatedString(source)) }) {
          Icon(Icons.Default.ContentCopy, contentDescription = "复制代码", tint = colors.secondaryText, modifier = Modifier.size(15.dp))
        }
      }
      Text(source, fontSize = 12.sp, lineHeight = 19.sp, fontFamily = FontFamily.Monospace, color = colors.text,
        modifier = Modifier.horizontalScroll(rememberScrollState()).padding(start = 12.dp, end = 12.dp, bottom = 12.dp))
    }
  }
}

@Composable
private fun MarkdownTable(table: TableBlock) {
  val colors = WorkbenchTheme.colors
  Column(Modifier.horizontalScroll(rememberScrollState())) {
    table.children().flatMap { it.children() }.forEach { row ->
      Row {
        row.children().filterIsInstance<TableCell>().forEach { cell ->
          Text(inlineContent(cell, colors), color = colors.text, fontSize = 13.sp, lineHeight = 20.sp,
            fontWeight = if (cell.isHeader) FontWeight.Bold else FontWeight.Normal,
            modifier = Modifier.width(160.dp).padding(10.dp))
        }
      }
      HorizontalDivider(color = colors.border)
    }
  }
}
