package com.kexin94yyds.iterate.mobile

import kotlinx.coroutines.runBlocking
import okhttp3.OkHttpClient
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class PairingRepositoryTest {
  private fun offer(base: String = "https://desktop.example", ws: String = "wss://desktop.example/ws", expiry: String = "2099-01-01T00:00:00Z") = JSONObject()
    .put("version", 2).put("base_url", base).put("ws_url", ws).put("expires_at", expiry)
    .put("pairing_token", "pt-fixture").put("device_name", "Test Desktop").toString()
  @Test fun acceptsEncodedDesktopLink() {
    val link = "iterate://pairing?payload=" + java.net.URLEncoder.encode(offer(), "UTF-8")
    assertEquals("https://desktop.example", PairingParser.parse(link).baseUrl)
  }
  @Test fun rejectsExpiredMismatchedAndUnsecuredOffers() {
    for (bad in listOf(offer(expiry="2000-01-01T00:00:00Z"), offer(ws="wss://other.example/ws"),
      offer(base="http://desktop.example", ws="ws://desktop.example/ws"), offer(base="https://secret@desktop.example"),
      offer(ws="wss://desktop.example/ws?token=secret"), offer(base="https://desktop.example/path"))) {
      assertTrue(runCatching { PairingParser.parse(bad) }.isFailure)
    }
  }
  @Test fun loopbackIsOnlyAllowedByExplicitDebugOption() {
    val local = offer(base="http://127.0.0.1:8080", ws="ws://127.0.0.1:8080/ws")
    assertTrue(runCatching { PairingParser.parse(local) }.isFailure)
    assertEquals("http://127.0.0.1:8080", PairingParser.parse(local, allowDebugLoopback=true).baseUrl)
  }
  @Test fun claimBindsAndroidIdentityAndDoesNotFollowRedirects() = runBlocking {
    val server = MockWebServer().apply { start() }
    val other = MockWebServer().apply { start() }
    try {
      server.enqueue(MockResponse().setResponseCode(302).addHeader("Location", other.url("/stolen")))
      val base = server.url("/").toString().trimEnd('/')
      assertTrue(runCatching { PairingRepository().claim(PairingOffer(base, "$base/ws", "one-time-test", "test"), "android-test", "Test Phone") }.isFailure)
      assertEquals(0, other.requestCount)
      val request = server.takeRequest()
      assertEquals("/api/mobile/pairing/claim", request.path)
      assertEquals("android", JSONObject(request.body.readUtf8()).getString("client_kind"))
      assertNull(request.getHeader("Authorization"))
    } finally { server.shutdown(); other.shutdown() }
  }
  @Test fun claimRejectsMismatchedDeviceAndReturnsValidCredential() = runBlocking {
    val server = MockWebServer().apply { start() }
    try {
      val base = server.url("/").toString().trimEnd('/')
      val value = PairingOffer(base, "$base/ws", "one-time-test", "test")
      server.enqueue(MockResponse().setBody("""{"ok":true,"device_id":"other","device_token":"test-token"}"""))
      assertTrue(runCatching { PairingRepository().claim(value,"android-test","Test") }.isFailure)
      server.enqueue(MockResponse().setBody("""{"ok":true,"device_id":"android-test","device_token":"test-token"}"""))
      assertEquals("test-token", PairingRepository().claim(value,"android-test","Test").token)
    } finally { server.shutdown() }
  }
}
