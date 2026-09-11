package com.kexin94yyds.iterate.mobile

import kotlinx.coroutines.runBlocking
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class AuthenticatedReplyTest {
  @Test fun transientClientStatusesRemainRetryable() = runBlocking {
    val server = MockWebServer().apply { start() }
    try {
      val base = server.url("/").toString().trimEnd('/')
      for (status in listOf(408, 429)) {
        server.enqueue(MockResponse().setResponseCode(status))
        val error = runCatching { BridgeClient(base,"$base/ws","fixture-token").sendReply(JSONObject()) }.exceptionOrNull()
        assertTrue(error is java.io.IOException)
        assertFalse(error is BridgeClient.ReplyRejected)
      }
    } finally { server.shutdown() }
  }
  @Test fun replyUsesPairedBearerAndRetainsOperationIdentity() = runBlocking {
    val server = MockWebServer().apply { start() }
    try {
      server.enqueue(MockResponse().setBody("""{"operation_id":"operation-test","status":"delivered"}"""))
      val base = server.url("/").toString().trimEnd('/')
      val reply = JSONObject().put("operation_id","operation-test").put("request_id","request-test").put("action","submit")
      assertEquals("delivered", BridgeClient(base,"$base/ws","private-test-token").sendReply(reply).getString("status"))
      val sent = server.takeRequest()
      assertEquals("Bearer private-test-token", sent.getHeader("Authorization"))
      assertEquals("/api/mobile/reply", sent.path)
      assertEquals("operation-test", JSONObject(sent.body.readUtf8()).getString("operation_id"))
    } finally { server.shutdown() }
  }
  @Test fun pairedRequestsDoNotLeakBearerThroughRedirects() = runBlocking {
    val server = MockWebServer().apply { start() }; val other = MockWebServer().apply { start() }
    try {
      server.enqueue(MockResponse().setResponseCode(302).addHeader("Location",other.url("/capture")))
      val base = server.url("/").toString().trimEnd('/')
      assertTrue(runCatching { BridgeClient(base,"$base/ws","private-test-token").readJson("/api/active-sessions") }.isFailure)
      assertEquals(0, other.requestCount)
    } finally { server.shutdown(); other.shutdown() }
  }
}
