package com.kexin94yyds.iterate.mobile

import org.junit.Assert.assertEquals
import org.junit.Test

class VoiceInputControllerTest {
  @Test
  fun reducerMovesFromIdleToListening() {
    assertEquals(VoiceInputState.Listening, VoiceInputReducer.reduce(VoiceInputState.Idle, VoiceInputEvent.Start))
  }

  @Test
  fun reducerReturnsIdleWhenTranscriptArrives() {
    assertEquals(VoiceInputState.Idle, VoiceInputReducer.reduce(VoiceInputState.Listening, VoiceInputEvent.Transcript("继续")))
  }

  @Test
  fun reducerRecordsPermissionDenied() {
    assertEquals(VoiceInputState.PermissionDenied, VoiceInputReducer.reduce(VoiceInputState.Idle, VoiceInputEvent.PermissionDenied))
  }
}
