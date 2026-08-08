package ai.opentype.android.model

enum class InputMode(val id: String) {
    SMART_EDIT("smartEdit"),
    ENGLISH("english"),
    AGENT("agent"),
    X_REPLY("xReply"),
    TRANSCRIBE("transcribe");

    fun next(): InputMode = entries[(entries.indexOf(this) + 1) % entries.size]

    companion object {
        fun fromId(value: String?): InputMode = if (value == "selectedEdit") SMART_EDIT
        else entries.firstOrNull { it.id == value } ?: SMART_EDIT
    }
}

enum class InterfaceLanguage(val id: String) {
    CHINESE("zh-Hans"),
    ENGLISH("en");

    companion object {
        fun fromId(value: String?): InterfaceLanguage = entries.firstOrNull { it.id == value } ?: CHINESE
    }
}

enum class AppTheme(val id: String) {
    OCEAN("ocean"),
    VIOLET("violet"),
    MINT("mint"),
    SUNSET("sunset"),
    SAKURA("sakura"),
    GRAPHITE("graphite");

    companion object {
        fun fromId(value: String?): AppTheme = entries.firstOrNull { it.id == value } ?: OCEAN
    }
}

enum class ProcessingState(val id: String) {
    IDLE("idle"),
    LISTENING("listening"),
    TRANSCRIBING("transcribing"),
    TRANSFORMING("transforming"),
    INSERTING("inserting"),
    DONE("done"),
    COPIED("copied"),
    CANCELLED("cancelled"),
    FAILED("failed")
}

enum class TextProvider(
    val id: String,
    val defaultEndpoint: String,
    val defaultModel: String
) {
    DASH_SCOPE(
        id = "dashScope",
        defaultEndpoint = "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions",
        defaultModel = "qwen-plus"
    ),
    VOLCENGINE(
        id = "volcengine",
        defaultEndpoint = "https://ark.cn-beijing.volces.com/api/v3/chat/completions",
        defaultModel = "doubao-seed-2-0-lite-260215"
    ),
    OPENAI(
        id = "openAI",
        defaultEndpoint = "https://api.openai.com/v1/chat/completions",
        defaultModel = "gpt-5-mini"
    ),
    ANTHROPIC(
        id = "anthropic",
        defaultEndpoint = "https://api.anthropic.com/v1/messages",
        defaultModel = "claude-sonnet-5"
    );

    companion object {
        fun fromId(value: String?): TextProvider = entries.firstOrNull { it.id == value } ?: DASH_SCOPE
    }
}

data class AppSettings(
    val interfaceLanguage: InterfaceLanguage = InterfaceLanguage.CHINESE,
    val theme: AppTheme = AppTheme.OCEAN,
    val mode: InputMode = InputMode.SMART_EDIT,
    val provider: TextProvider = TextProvider.DASH_SCOPE,
    val endpoint: String = TextProvider.DASH_SCOPE.defaultEndpoint,
    val model: String = TextProvider.DASH_SCOPE.defaultModel,
    val recognitionLanguage: String = "auto",
    val includeRecentTasks: Boolean = true
)

data class HistoryEntry(
    val id: String,
    val requestId: String,
    val timestampMillis: Long,
    val mode: InputMode,
    val status: String,
    val originalTranscript: String,
    val selectedText: String?,
    val output: String,
    val provider: String?,
    val model: String?,
    val error: String?
)

data class ProcessRequest(
    val mode: InputMode,
    val transcript: String,
    val selectedText: String? = null,
    val xPostContext: String? = null,
    val isPasswordField: Boolean = false
)

sealed interface ProcessResult {
    data class Success(
        val text: String,
        val usedModel: Boolean,
        val copied: Boolean
    ) : ProcessResult

    data class Cancelled(val reason: String) : ProcessResult
    data class Failure(val reason: String, val localFallback: String? = null) : ProcessResult
}

object L10n {
    fun text(language: InterfaceLanguage, chinese: String, english: String): String =
        if (language == InterfaceLanguage.CHINESE) chinese else english

    fun modeTitle(mode: InputMode, language: InterfaceLanguage): String = when (mode) {
        InputMode.SMART_EDIT -> text(language, "智能编辑", "Smart Edit")
        InputMode.ENGLISH -> text(language, "中转英", "English")
        InputMode.AGENT -> text(language, "Agent 模式", "Agent")
        InputMode.X_REPLY -> "X Reply"
        InputMode.TRANSCRIBE -> text(language, "文字转写", "Transcribe")
    }

    fun modeDescription(mode: InputMode, language: InterfaceLanguage): String = when (mode) {
        InputMode.SMART_EDIT -> text(language, "直接整理口述；有选区时按指令修改", "Clean dictation; edit a selection by instruction")
        InputMode.ENGLISH -> text(language, "中文或混合口述，写成自然英文", "Turn Chinese or mixed speech into natural English")
        InputMode.AGENT -> text(language, "完成轻量文字任务，不执行外部发送", "Complete a lightweight writing task; never send it")
        InputMode.X_REPLY -> text(language, "结合原帖，生成一条真人感回复", "Draft one natural reply from the original post")
        InputMode.TRANSCRIBE -> text(language, "只做保真轻整理，绝不回答口述", "Light cleanup only; never answer the dictation")
    }
}
