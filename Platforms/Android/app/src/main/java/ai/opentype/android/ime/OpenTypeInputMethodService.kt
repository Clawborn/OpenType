package ai.opentype.android.ime

import android.Manifest
import android.content.ClipboardManager
import android.content.pm.PackageManager
import android.inputmethodservice.InputMethodService
import android.os.Build
import android.text.InputType
import android.view.View
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.ComposeView
import androidx.compose.ui.platform.ViewCompositionStrategy
import androidx.core.content.ContextCompat
import androidx.lifecycle.setViewTreeLifecycleOwner
import androidx.lifecycle.setViewTreeViewModelStoreOwner
import androidx.savedstate.setViewTreeSavedStateRegistryOwner
import ai.opentype.android.core.OpenTypeEngine
import ai.opentype.android.data.AppPreferences
import ai.opentype.android.model.AppTheme
import ai.opentype.android.model.InputMode
import ai.opentype.android.model.InterfaceLanguage
import ai.opentype.android.model.L10n
import ai.opentype.android.model.ProcessRequest
import ai.opentype.android.model.ProcessResult
import ai.opentype.android.speech.SystemSpeechRecognizer
import ai.opentype.android.ui.theme.OpenTypeTheme
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

class OpenTypeInputMethodService : InputMethodService(), SystemSpeechRecognizer.Callback {
    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private lateinit var preferences: AppPreferences
    private lateinit var engine: OpenTypeEngine
    private lateinit var speechRecognizer: SystemSpeechRecognizer
    private var lifecycleOwner: ImeLifecycleOwner? = null
    private var processingJob: Job? = null
    private var inputSession = 0L

    private var mode by mutableStateOf(InputMode.SMART_EDIT)
    private var interfaceLanguage by mutableStateOf(InterfaceLanguage.CHINESE)
    private var colorTheme by mutableStateOf(AppTheme.OCEAN)
    private var transcript by mutableStateOf("")
    private var status by mutableStateOf("")
    private var listening by mutableStateOf(false)
    private var processing by mutableStateOf(false)
    private var audioLevel by mutableFloatStateOf(0f)
    private var passwordField by mutableStateOf(false)
    private var capturedSelection: String? = null

    override fun onCreate() {
        super.onCreate()
        preferences = AppPreferences(this)
        engine = OpenTypeEngine(this)
        speechRecognizer = SystemSpeechRecognizer(this, this)
        val settings = preferences.load()
        mode = settings.mode
        interfaceLanguage = settings.interfaceLanguage
        colorTheme = settings.theme
        status = L10n.text(settings.interfaceLanguage, "就绪", "Ready")
    }

    override fun onCreateInputView(): View {
        lifecycleOwner?.destroy()
        val owner = ImeLifecycleOwner().also {
            it.resume()
            lifecycleOwner = it
        }
        return ComposeView(this).apply {
            setViewTreeLifecycleOwner(owner)
            setViewTreeViewModelStoreOwner(owner)
            setViewTreeSavedStateRegistryOwner(owner)
            setViewCompositionStrategy(ViewCompositionStrategy.DisposeOnViewTreeLifecycleDestroyed)
            setContent {
                OpenTypeTheme(theme = colorTheme) {
                    ImeKeyboard(
                        language = interfaceLanguage,
                        mode = mode,
                        transcript = transcript,
                        status = status,
                        listening = listening,
                        processing = processing,
                        audioLevel = audioLevel,
                        passwordField = passwordField,
                        onModeSelected = ::selectMode,
                        onPressStart = ::beginListening,
                        onPressEnd = ::endListening,
                        onAutomaticXReply = { processTranscript("") },
                        onSwitchInputMethod = ::switchKeyboard
                    )
                }
            }
        }
    }

    override fun onStartInput(attribute: EditorInfo?, restarting: Boolean) {
        super.onStartInput(attribute, restarting)
        invalidateInputSession()
        val settings = preferences.load()
        mode = settings.mode
        interfaceLanguage = settings.interfaceLanguage
        colorTheme = settings.theme
        passwordField = isPassword(attribute)
        capturedSelection = null
        transcript = ""
        val language = interfaceLanguage
        status = if (passwordField) {
            L10n.text(language, "隐私模式 · 不读取上下文或保存历史", "Private mode · No context or history")
        } else L10n.text(language, "就绪", "Ready")
    }

    override fun onWindowShown() {
        super.onWindowShown()
        lifecycleOwner?.resume()
    }

    override fun onWindowHidden() {
        invalidateInputSession()
        lifecycleOwner?.pause()
        super.onWindowHidden()
    }

    override fun onFinishInput() {
        invalidateInputSession()
        capturedSelection = null
        super.onFinishInput()
    }

    override fun onDestroy() {
        processingJob?.cancel()
        speechRecognizer.destroy()
        lifecycleOwner?.destroy()
        serviceScope.cancel()
        super.onDestroy()
    }

    private fun selectMode(value: InputMode) {
        mode = value
        capturedSelection = null
        preferences.setMode(value)
        val language = preferences.load().interfaceLanguage
        status = L10n.text(language, "已切换到 ${L10n.modeTitle(value, language)}", "Switched to ${L10n.modeTitle(value, language)}")
    }

    private fun beginListening() {
        if (processing || listening || passwordField) return
        val language = preferences.load().interfaceLanguage
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            status = L10n.text(language, "请先打开 OpenType App 允许麦克风", "Open the OpenType app and allow microphone access")
            return
        }
        capturedSelection = if (passwordField) null else currentInputConnection
            ?.getSelectedText(0)
            ?.toString()
            ?.trim()
            ?.takeIf { it.isNotEmpty() }
        transcript = ""
        listening = true
        status = L10n.text(language, "正在听", "Listening")
        speechRecognizer.start(preferences.load().recognitionLanguage)
    }

    private fun endListening() {
        if (!listening) return
        listening = false
        val language = preferences.load().interfaceLanguage
        status = L10n.text(language, "正在识别", "Transcribing")
        speechRecognizer.stop()
    }

    override fun onReady() {
        val language = preferences.load().interfaceLanguage
        status = L10n.text(language, "正在听 · 松开完成", "Listening · Release to finish")
    }

    override fun onPartial(text: String) {
        transcript = text
    }

    override fun onFinal(text: String) {
        listening = false
        audioLevel = 0f
        transcript = text
        if (text.isBlank()) {
            onError("No speech was recognized")
        } else {
            processTranscript(text)
        }
    }

    override fun onLevel(level: Float) {
        audioLevel = level
    }

    override fun onError(message: String) {
        listening = false
        processing = false
        audioLevel = 0f
        status = localizeError(message)
    }

    private fun processTranscript(spokenText: String) {
        if (processing || passwordField) return
        val session = inputSession
        val language = preferences.load().interfaceLanguage
        val liveSelection = if (passwordField) null else currentInputConnection
            ?.getSelectedText(0)
            ?.toString()
            ?.trim()
            ?.takeIf { it.isNotEmpty() }
        val sourceContext = if (passwordField) null else when (mode) {
            InputMode.X_REPLY -> liveSelection ?: capturedSelection ?: clipboardText()
            else -> null
        }
        processing = true
        status = L10n.text(language, "正在整理", "Refining")
        val request = ProcessRequest(
            mode = mode,
            transcript = spokenText,
            selectedText = if (mode == InputMode.SMART_EDIT) liveSelection ?: capturedSelection else null,
            xPostContext = sourceContext,
            isPasswordField = passwordField
        )
        processingJob = serviceScope.launch {
            try {
                val result = engine.process(request)
                if (session != inputSession || passwordField) return@launch
                when (result) {
                    is ProcessResult.Success -> {
                        status = L10n.text(language, "正在写入", "Inserting")
                        // The session comparison runs on the same main thread as
                        // onStartInput, so the target cannot change between this
                        // guard and commitText.
                        val inserted = session == inputSession && !passwordField &&
                            currentInputConnection?.commitText(result.text, 1) == true
                        status = if (inserted) {
                            L10n.text(language, "完成 · 已复制", "Done · Copied")
                        } else {
                            L10n.text(language, "写入失败 · 结果已复制", "Insert failed · Result copied")
                        }
                        transcript = result.text
                    }
                    is ProcessResult.Cancelled -> status = localizeError(result.reason)
                    is ProcessResult.Failure -> {
                        transcript = result.localFallback ?: transcript
                        status = localizeError(result.reason)
                    }
                }
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (error: Throwable) {
                if (session == inputSession) {
                    status = localizeError(error.message ?: "Processing failed")
                }
            } finally {
                if (session == inputSession) {
                    processing = false
                    processingJob = null
                }
            }
        }
    }

    private fun invalidateInputSession() {
        inputSession += 1
        processingJob?.cancel()
        processingJob = null
        speechRecognizer.cancel()
        listening = false
        processing = false
        audioLevel = 0f
    }

    private fun clipboardText(): String? {
        val clipboard = getSystemService(ClipboardManager::class.java) ?: return null
        return clipboard.primaryClip
            ?.getItemAt(0)
            ?.coerceToText(this)
            ?.toString()
            ?.trim()
            ?.takeIf { it.isNotEmpty() }
    }

    private fun switchKeyboard() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            switchToNextInputMethod(false)
            return
        }
        val token = window?.window?.decorView?.windowToken ?: return
        getSystemService(InputMethodManager::class.java)?.switchToNextInputMethod(token, false)
    }

    private fun localizeError(message: String): String {
        val language = preferences.load().interfaceLanguage
        return when {
            message.contains("explicit editing", true) -> L10n.text(language, "选中文字后，请明确说出修改指令", "Say an explicit edit instruction for selected text")
            message.contains("original X", true) -> L10n.text(language, "请先复制原帖内容", "Copy the original X post first")
            message.contains("permission", true) -> L10n.text(language, "请先在 OpenType App 允许麦克风", "Allow microphone access in the OpenType app")
            message.contains("No speech", true) -> L10n.text(language, "没有识别到语音", "No speech was recognized")
            else -> message
        }
    }

    private fun isPassword(editorInfo: EditorInfo?): Boolean {
        val inputType = editorInfo?.inputType ?: return false
        val variation = inputType and InputType.TYPE_MASK_VARIATION
        return when (inputType and InputType.TYPE_MASK_CLASS) {
            InputType.TYPE_CLASS_TEXT -> variation == InputType.TYPE_TEXT_VARIATION_PASSWORD ||
                variation == InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD ||
                variation == InputType.TYPE_TEXT_VARIATION_WEB_PASSWORD
            InputType.TYPE_CLASS_NUMBER -> variation == InputType.TYPE_NUMBER_VARIATION_PASSWORD
            else -> false
        }
    }
}
