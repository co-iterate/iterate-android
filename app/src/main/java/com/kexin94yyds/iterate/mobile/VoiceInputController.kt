package com.kexin94yyds.iterate.mobile

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.widget.Toast
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
  private var stopping = false
  private var permissionPending = false
  private val handler = Handler(Looper.getMainLooper())
  private var stopTimeout: Runnable? = null

  fun start(requestPermission: () -> Unit) {
    if (ContextCompat.checkSelfPermission(activity, Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
      permissionPending = true
      requestPermission()
      return
    }
    startGranted()
  }

  fun onPermissionResult(granted: Boolean) {
    if (!permissionPending) return
    permissionPending = false
    if (granted) {
      startGranted()
    } else {
      onState(VoiceInputState.PermissionDenied)
      showFeedback("需要麦克风权限才能语音输入，请允许后重试")
    }
  }

  private fun startGranted() {
    val available = try {
      SpeechRecognizer.isRecognitionAvailable(activity)
    } catch (_: RuntimeException) {
      false
    }
    if (!available) {
      onState(VoiceInputState.Error)
      showFeedback("此手机没有可用的语音识别服务")
      return
    }

    releaseRecognizer(cancel = true)
    val speechRecognizer = try {
      SpeechRecognizer.createSpeechRecognizer(activity)
    } catch (_: RuntimeException) {
      onState(VoiceInputState.Error)
      showFeedback("语音识别服务启动失败，请检查系统语音服务")
      return
    }
    recognizer = speechRecognizer
    speechRecognizer.setRecognitionListener(object : RecognitionListener {
      override fun onReadyForSpeech(params: Bundle?) {
        if (recognizer !== speechRecognizer) return
        onState(VoiceInputState.Listening)
      }

      override fun onResults(results: Bundle?) {
        if (recognizer !== speechRecognizer) return
        val text = results
          ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
          ?.firstOrNull()
          .orEmpty()
        if (text.isNotBlank()) {
          onTranscript(text)
        } else {
          showFeedback("没有识别到语音，请重试")
        }
        onState(VoiceInputState.Idle)
        releaseRecognizer(cancel = false)
      }

      override fun onError(error: Int) {
        if (recognizer !== speechRecognizer) return
        onState(VoiceInputState.Error)
        showFeedback(voiceErrorMessage(error))
        releaseRecognizer(cancel = false)
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
    try {
      speechRecognizer.startListening(intent)
    } catch (_: RuntimeException) {
      onState(VoiceInputState.Error)
      showFeedback("语音识别无法开始，请重试")
      releaseRecognizer(cancel = true)
    }
  }

  fun stop() {
    val active = recognizer ?: return
    if (stopping) return
    stopping = true
    try {
      // Keep the recognizer alive until onResults/onError supplies the final transcript.
      active.stopListening()
      if (recognizer !== active) return
      val timeout = Runnable {
        if (recognizer === active) {
          onState(VoiceInputState.Error)
          showFeedback("语音识别超时，请重试")
          releaseRecognizer(cancel = true)
        }
      }
      stopTimeout = timeout
      handler.postDelayed(timeout, 10_000)
    } catch (_: RuntimeException) {
      onState(VoiceInputState.Error)
      showFeedback("语音识别结束失败，请重试")
      releaseRecognizer(cancel = true)
    }
  }

  fun cancel() {
    permissionPending = false
    releaseRecognizer(cancel = true)
    onState(VoiceInputState.Idle)
  }

  private fun releaseRecognizer(cancel: Boolean) {
    stopTimeout?.let(handler::removeCallbacks)
    stopTimeout = null
    if (cancel) recognizer?.cancel()
    recognizer?.destroy()
    recognizer = null
    stopping = false
  }

  private fun voiceErrorMessage(error: Int): String = when (error) {
    SpeechRecognizer.ERROR_NO_MATCH, SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> "没有识别到语音，请重试"
    SpeechRecognizer.ERROR_NETWORK, SpeechRecognizer.ERROR_NETWORK_TIMEOUT -> "语音识别网络不可用，请检查网络"
    SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> "麦克风权限未开启，请在系统设置中允许"
    SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> "语音识别正忙，请稍后重试"
    SpeechRecognizer.ERROR_AUDIO -> "麦克风无法录音，请检查设备"
    else -> "语音识别失败（错误码 $error），请重试"
  }

  private fun showFeedback(message: String) {
    Toast.makeText(activity, message, Toast.LENGTH_LONG).show()
  }
}
