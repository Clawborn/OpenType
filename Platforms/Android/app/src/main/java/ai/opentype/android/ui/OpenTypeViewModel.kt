package ai.opentype.android.ui

import android.app.Application
import android.content.ClipData
import android.content.ClipboardManager
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import ai.opentype.android.core.OpenTypeEngine
import ai.opentype.android.data.AppPreferences
import ai.opentype.android.data.HistoryRepository
import ai.opentype.android.data.SecureTokenStore
import ai.opentype.android.model.AppSettings
import ai.opentype.android.model.HistoryEntry
import ai.opentype.android.model.InputMode
import ai.opentype.android.model.ProcessRequest
import ai.opentype.android.model.ProcessResult
import ai.opentype.android.model.ProcessingState
import ai.opentype.android.speech.SystemSpeechRecognizer
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

data class OpenTypeUiState(
    val settings: AppSettings = AppSettings(),
    val processingState: ProcessingState = ProcessingState.IDLE,
    val transcript: String = "",
    val contextText: String = "",
    val result: String = "",
    val statusMessage: String = "",
    val audioLevel: Float = 0f,
    val history: List<HistoryEntry> = emptyList(),
    val tokenConfigured: Boolean = false
)

class OpenTypeViewModel(application: Application) : AndroidViewModel(application),
    SystemSpeechRecognizer.Callback {
    private val preferences = AppPreferences(application)
    private val tokens = SecureTokenStore(application)
    private val history = HistoryRepository(application)
    private val engine = OpenTypeEngine(application)
    private val recognizer = SystemSpeechRecognizer(application, this)

    private val _state = MutableStateFlow(
        OpenTypeUiState(
            settings = preferences.load()
        )
    )
    val state: StateFlow<OpenTypeUiState> = _state.asStateFlow()

    init {
        refreshFromStorage()
    }

    fun selectMode(mode: InputMode) {
        val updated = _state.value.settings.copy(mode = mode)
        preferences.save(updated)
        _state.update {
            it.copy(
                settings = updated,
                processingState = ProcessingState.IDLE,
                result = "",
                statusMessage = ""
            )
        }
    }

    fun setTranscript(value: String) {
        _state.update { it.copy(transcript = value) }
    }

    fun setContext(value: String) {
        _state.update { it.copy(contextText = value) }
    }

    fun startListening() {
        if (_state.value.processingState == ProcessingState.TRANSFORMING ||
            _state.value.processingState == ProcessingState.LISTENING
        ) return
        _state.update {
            it.copy(
                processingState = ProcessingState.LISTENING,
                transcript = "",
                result = "",
                statusMessage = ""
            )
        }
        recognizer.start(_state.value.settings.recognitionLanguage)
    }

    fun stopListening() {
        if (_state.value.processingState != ProcessingState.LISTENING) return
        _state.update { it.copy(processingState = ProcessingState.TRANSCRIBING) }
        recognizer.stop()
    }

    fun processCurrent(allowEmptyXViewpoint: Boolean = false) {
        val snapshot = _state.value
        val transcript = snapshot.transcript.trim()
        if (transcript.isEmpty() && !(allowEmptyXViewpoint && snapshot.settings.mode == InputMode.X_REPLY)) {
            _state.update { it.copy(processingState = ProcessingState.CANCELLED, statusMessage = "No speech was recognized") }
            return
        }
        _state.update { it.copy(processingState = ProcessingState.TRANSFORMING, statusMessage = "") }
        viewModelScope.launch {
            try {
                val mode = snapshot.settings.mode
                val result = engine.process(
                    ProcessRequest(
                        mode = mode,
                        transcript = transcript,
                        selectedText = snapshot.contextText.takeIf { mode == InputMode.SMART_EDIT && it.isNotBlank() },
                        xPostContext = snapshot.contextText.takeIf { mode == InputMode.X_REPLY && it.isNotBlank() }
                    )
                )
                val latestHistory = withContext(Dispatchers.IO) { history.displayEntries() }
                when (result) {
                    is ProcessResult.Success -> _state.update {
                        it.copy(
                            processingState = ProcessingState.DONE,
                            result = result.text,
                            statusMessage = "Copied",
                            history = latestHistory
                        )
                    }
                    is ProcessResult.Cancelled -> _state.update {
                        it.copy(
                            processingState = ProcessingState.CANCELLED,
                            statusMessage = result.reason,
                            history = latestHistory
                        )
                    }
                    is ProcessResult.Failure -> _state.update {
                        it.copy(
                            processingState = ProcessingState.FAILED,
                            result = result.localFallback.orEmpty(),
                            statusMessage = result.reason,
                            history = latestHistory
                        )
                    }
                }
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (error: Throwable) {
                _state.update {
                    it.copy(
                        processingState = ProcessingState.FAILED,
                        statusMessage = error.message ?: "Processing failed"
                    )
                }
            }
        }
    }

    fun copyResult() {
        val text = _state.value.result.takeIf { it.isNotBlank() } ?: return
        getApplication<Application>().getSystemService(ClipboardManager::class.java)
            ?.setPrimaryClip(ClipData.newPlainText("OpenType", text))
        _state.update { it.copy(processingState = ProcessingState.COPIED, statusMessage = "Copied") }
    }

    fun saveSettings(settings: AppSettings, token: String) {
        preferences.save(settings)
        _state.update { it.copy(settings = settings) }
        viewModelScope.launch {
            val configured = withContext(Dispatchers.IO) {
                if (token.isNotBlank()) tokens.save(settings.provider, token)
                tokens.hasToken(settings.provider)
            }
            if (_state.value.settings.provider == settings.provider) {
                _state.update { it.copy(tokenConfigured = configured) }
            }
        }
    }

    fun removeCurrentToken() {
        val provider = _state.value.settings.provider
        viewModelScope.launch {
            withContext(Dispatchers.IO) { tokens.clear(provider) }
            if (_state.value.settings.provider == provider) {
                _state.update { it.copy(tokenConfigured = false) }
            }
        }
    }

    fun refreshFromStorage() {
        val settings = preferences.load()
        _state.update { it.copy(settings = settings) }
        viewModelScope.launch {
            val (entries, configured) = withContext(Dispatchers.IO) {
                history.displayEntries() to tokens.hasToken(settings.provider)
            }
            if (_state.value.settings.provider == settings.provider) {
                _state.update { it.copy(history = entries, tokenConfigured = configured) }
            }
        }
    }

    override fun onReady() = Unit

    override fun onPartial(text: String) {
        _state.update { it.copy(transcript = text) }
    }

    override fun onFinal(text: String) {
        _state.update {
            it.copy(
                transcript = text,
                audioLevel = 0f,
                processingState = ProcessingState.TRANSCRIBING
            )
        }
        if (text.isBlank()) onError("No speech was recognized") else processCurrent()
    }

    override fun onLevel(level: Float) {
        _state.update { it.copy(audioLevel = level) }
    }

    override fun onError(message: String) {
        _state.update {
            it.copy(
                processingState = ProcessingState.FAILED,
                audioLevel = 0f,
                statusMessage = message
            )
        }
    }

    override fun onCleared() {
        recognizer.destroy()
        super.onCleared()
    }

}
