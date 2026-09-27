package com.kexin94yyds.iterate.mobile

import org.commonmark.node.AbstractVisitor
import org.commonmark.node.Code
import org.commonmark.node.FencedCodeBlock
import org.commonmark.node.Heading
import org.commonmark.node.StrongEmphasis
import org.commonmark.node.Text
import org.commonmark.parser.Parser
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class MarkdownMessageTest {
  @Test
  fun realBridgeMessageRetainsMarkdownAndParsesItsBoldText() {
    val fixture = javaClass.getResourceAsStream("/markdown/real-port-summary.json")!!
      .bufferedReader().use { JSONObject(it.readText()) }
    val wire = JSONObject().put("message_type", "mcp_state")
      .put("payload", JSONObject().put("request", fixture))
    val request = BridgeJsonParser.parseRequest(wire.toString())!!
    assertTrue(request.isMarkdown)
    val bold = mutableListOf<String>()
    Parser.builder().build().parse(BridgeJsonParser.messageWithoutImages(request.message))
      .accept(object : AbstractVisitor() {
        override fun visit(node: StrongEmphasis) {
          bold += (node.firstChild as Text).literal
          visitChildren(node)
        }
      })
    assertTrue(bold.contains("8080 服务和远端 18080 隧道并入 Mytool 的统一后台启动、重启和退出流程"))
  }

  @Test
  fun commonMarkDistinguishesFormattingFromEscapesAndCode() {
    val source = "# 标题\n\n**加粗** 和 `**代码**` 与 \\*\\*转义\\*\\*\n\n```text\n**原样**\n```"
    var headings = 0
    var bold = 0
    var inlineCode = ""
    var fencedCode = ""
    Parser.builder().build().parse(source).accept(object : AbstractVisitor() {
      override fun visit(node: Heading) { headings++; visitChildren(node) }
      override fun visit(node: StrongEmphasis) { bold++; visitChildren(node) }
      override fun visit(node: Code) { inlineCode = node.literal }
      override fun visit(node: FencedCodeBlock) { fencedCode = node.literal }
    })
    assertEquals(1, headings)
    assertEquals(1, bold)
    assertEquals("**代码**", inlineCode)
    assertEquals("**原样**\n", fencedCode)
  }
}
