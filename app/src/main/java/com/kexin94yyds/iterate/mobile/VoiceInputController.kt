package com.kexin94yyds.iterate.mobile

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import java.util.Locale

sealed class VoiceInputEvent {
  data object Start : VoiceInputEvent()
  data class Transcript(val text: String) : VoiceInputEvent()
  data object PermissionDenied : VoiceInputEvent()
  data object Error : VoiceInputEvent()
}

object VoiceInputReducer {
  fun reduce(current: VoiceInputState, event: VoiceInputEvent): VoiceInputState {
    return when (event) {
      VoiceInputEvent.Start -> VoiceInputState.Listening
      is VoiceInputEvent.Transcript -> VoiceInputState.Idle
      VoiceInputEvent.PermissionDenied -> VoiceInputState.PermissionDenied
      VoiceInputEvent.Error -> if (current == VoiceInputState.Listening) VoiceInputState.Error else current
    }
  }
}

class VoiceInputController(
  private val activity: Activity,
  private val onState: (VoiceInputState) -> Unit,
  private val onTranscript: (String) -> Unit,
) {
  private var recognizer: SpeechRecognizer? = null

  fun start() {
    if (ContextCompat.checkSelfPermission(activity, Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
      ActivityCompat.requestPermissions(activity, arrayOf(Manifest.permission.RECORD_AUDIO), 4108)
      onState(VoiceInputState.PermissionDenied)
      return
    }

    stopRecognizerOnly()
    val speechRecognizer = SpeechRecognizer.createSpeechRecognizer(activity)
    recognizer = speechRecognizer
    speechRecognizer.setRecognitionListener(object : RecognitionListener {
      override fun onReadyForSpeech(params: Bundle?) {
        onState(VoiceInputState.Listening)
      }

      override fun onResults(results: Bundle?) {
        val text = results
          ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
          ?.firstOrNull()
          .orEmpty()
        if (text.isNotBlank()) onTranscript(text)
        onState(VoiceInputState.Idle)
        stopRecognizerOnly()
      }

      override fun onError(error: Int) {
        onState(VoiceInputState.Error)
        stopRecognizerOnly()
      }

      override fun onBeginningOfSpeech() {}
      override fun onRmsChanged(rmsdB: Float) {}
      override fun onBufferReceived(buffer: ByteArray?) {}
      override fun onEndOfSpeech() {}
      override fun onPartialResults(partialResults: Bundle?) {}
      override fun onEvent(eventType: Int, params: Bundle?) {}
    })

    val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
      putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
      putExtra(RecognizerIntent.EXTRA_LANGUAGE, Locale.getDefault())
      putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
    }
    onState(VoiceInputState.Listening)
    speechRecognizer.startListening(intent)
  }

  fun stop() {
    stopRecognizerOnly()
    onState(VoiceInputState.Idle)
  }

  private fun stopRecognizerOnly() {
    recognizer?.stopListening()
    recognizer?.destroy()
    recognizer = null
  }
}
