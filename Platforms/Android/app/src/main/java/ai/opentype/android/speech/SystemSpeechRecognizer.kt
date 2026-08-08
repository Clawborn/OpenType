package ai.opentype.android.speech

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer

class SystemSpeechRecognizer(
    context: Context,
    private val callback: Callback
) {
    interface Callback {
        fun onReady()
        fun onPartial(text: String)
        fun onFinal(text: String)
        fun onLevel(level: Float)
        fun onError(message: String)
    }

    private val applicationContext = context.applicationContext
    private var recognizer: SpeechRecognizer? = null
    private var active = false
    private var generation = 0L

    val isAvailable: Boolean
        get() = SpeechRecognizer.isRecognitionAvailable(applicationContext)

    fun start(language: String = "auto") {
        if (active) return
        if (!isAvailable) {
            callback.onError("No system speech recognition service is available")
            return
        }
        generation += 1
        val currentGeneration = generation
        recognizer?.destroy()
        val speechRecognizer = SpeechRecognizer
            .createSpeechRecognizer(applicationContext)
            .also {
                it.setRecognitionListener(GenerationListener(currentGeneration))
                recognizer = it
            }
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
            putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS, 900L)
            putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_POSSIBLY_COMPLETE_SILENCE_LENGTH_MILLIS, 650L)
            when (language) {
                "zh" -> putExtra(RecognizerIntent.EXTRA_LANGUAGE, "zh-CN")
                "en" -> putExtra(RecognizerIntent.EXTRA_LANGUAGE, "en-US")
                else -> Unit
            }
        }
        active = true
        runCatching { speechRecognizer.startListening(intent) }
            .onFailure { error ->
                active = false
                speechRecognizer.destroy()
                if (recognizer === speechRecognizer) recognizer = null
                callback.onError(error.message ?: "Unable to start speech recognition")
            }
    }

    fun stop() {
        if (!active) return
        runCatching { recognizer?.stopListening() }
            .onFailure {
                active = false
                callback.onError(it.message ?: "Unable to stop speech recognition")
            }
    }

    fun cancel() {
        generation += 1
        active = false
        recognizer?.cancel()
        recognizer?.destroy()
        recognizer = null
    }

    fun destroy() {
        generation += 1
        active = false
        recognizer?.destroy()
        recognizer = null
    }

    private inner class GenerationListener(
        private val listenerGeneration: Long
    ) : RecognitionListener {
        private fun isCurrent(): Boolean = listenerGeneration == generation && active

        override fun onReadyForSpeech(params: Bundle?) {
            if (isCurrent()) callback.onReady()
        }

        override fun onBeginningOfSpeech() = Unit

        override fun onRmsChanged(rmsdB: Float) {
            if (isCurrent()) callback.onLevel(((rmsdB + 2f) / 12f).coerceIn(0f, 1f))
        }

        override fun onBufferReceived(buffer: ByteArray?) = Unit

        override fun onEndOfSpeech() = Unit

        override fun onError(error: Int) {
            if (!isCurrent()) return
            active = false
            callback.onLevel(0f)
            callback.onError(errorMessage(error))
        }

        override fun onResults(results: Bundle?) {
            if (!isCurrent()) return
            active = false
            callback.onLevel(0f)
            callback.onFinal(bestResult(results))
        }

        override fun onPartialResults(partialResults: Bundle?) {
            if (!isCurrent()) return
            val text = bestResult(partialResults)
            if (text.isNotBlank()) callback.onPartial(text)
        }

        override fun onEvent(eventType: Int, params: Bundle?) = Unit
    }

    private fun bestResult(bundle: Bundle?): String = bundle
        ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
        ?.firstOrNull()
        ?.trim()
        .orEmpty()

    private fun errorMessage(error: Int): String = when (error) {
        SpeechRecognizer.ERROR_AUDIO -> "Audio recording failed"
        SpeechRecognizer.ERROR_CLIENT -> "Speech recognition was cancelled"
        SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> "Microphone permission is required"
        SpeechRecognizer.ERROR_NETWORK, SpeechRecognizer.ERROR_NETWORK_TIMEOUT -> "Speech recognition network error"
        SpeechRecognizer.ERROR_NO_MATCH -> "No speech was recognized"
        SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> "Speech recognition is busy; try again"
        SpeechRecognizer.ERROR_SERVER -> "Speech recognition service error"
        SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> "No speech was heard"
        else -> "Speech recognition failed ($error)"
    }
}
