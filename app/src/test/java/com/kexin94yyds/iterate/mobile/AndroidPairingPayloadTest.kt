package com.kexin94yyds.iterate.mobile

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.fail
import org.junit.Test
import java.time.Instant

class AndroidPairingPayloadTest {
  private fun payload(baseUrl: String = "https://8.129.82.226:8443", wsUrl: String = "wss://8.129.82.226:8443/ws", expiry: Instant = Instant.now().plusSeconds(300)): JSONObject =
    JSONObject()
      .put("version", 2)
      .put("base_url", baseUrl)
      .put("ws_url", wsUrl)
      .put("expires_at", expiry.toString())
      .put("pairing_token", "pt_12345678901234567890")

  @Test
  fun acceptsCompactQrWithoutSessionId() {
    val parsed = AndroidPairingPayload.fromJson(payload())
    assertEquals("https://8.129.82.226:8443", parsed.baseUrl)
    assertEquals("wss://8.129.82.226:8443/ws", parsed.wsUrl)
  }

  @Test
  fun rejectsOtherEndpointAndExpiredQr() {
    for (item in listOf(
      payload(baseUrl = "http://8.129.82.226:8443"),
      payload(wsUrl = "ws://8.129.82.226:8443/ws"),
      payload(baseUrl = "https://evil.example"),
      payload(expiry = Instant.now().minusSeconds(1)),
    )) {
      try {
        AndroidPairingPayload.fromJson(item)
        fail("unsafe pairing payload was accepted")
      } catch (_: IllegalArgumentException) {
        // The scanned endpoint and expiry must match the approved route.
      }
    }
  }

  @Test
  fun parsesUtcAndOffsetExpiryOnMinSdkCompatiblePath() {
    assertEquals(1_600_000_000_123L, rfc3339Millis("2020-09-13T12:26:40.123456Z"))
    assertEquals(1_600_000_000_123L, rfc3339Millis("2020-09-13T20:26:40.123+08:00"))
  }
}
