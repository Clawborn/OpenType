package ai.opentype.android.ai

import ai.opentype.android.model.InputMode

/**
 * Enforces the product contract for Chinese-to-English mode after generation.
 * A provider occasionally follows the Chinese source language or answers a
 * quoted question despite the prompt. In that case OpenType makes exactly one
 * corrective request and never presents a second contract violation as a
 * successful translation.
 */
object EnglishOutputPolicy {
    suspend fun enforce(
        mode: InputMode,
        sourceText: String,
        initialCandidate: String,
        repair: suspend () -> String
    ): String {
        val initial = initialCandidate.trim()
        require(initial.isNotEmpty()) { "Provider returned an empty result" }
        if (!requiresRepair(mode, sourceText, initial)) return initial

        val repaired = repair().trim()
        require(repaired.isNotEmpty()) { "Provider returned an empty English retry" }
        require(!requiresRepair(mode, sourceText, repaired)) {
            "Provider violated the English transformation contract after one corrective retry"
        }
        return repaired
    }

    fun requiresRepair(
        mode: InputMode,
        sourceText: String,
        candidate: String
    ): Boolean = mode == InputMode.ENGLISH && (
        containsHanCharacters(candidate) ||
            isSuspiciouslyExpanded(sourceText, candidate) ||
            (sourceIsClearlyAQuestion(sourceText) && !candidateIsAQuestion(candidate)) ||
            (
                sourceRequestsAction(sourceText) &&
                    !candidatePreservesRequestedAction(sourceText, candidate)
                )
        )

    fun isSuspiciouslyExpanded(sourceText: String, candidate: String): Boolean {
        val sourceLength = sourceText.trim().length
        val outputLength = candidate.trim().length
        return outputLength > maxOf(96, sourceLength * 6)
    }

    fun containsHanCharacters(text: String): Boolean {
        var index = 0
        while (index < text.length) {
            val codePoint = Character.codePointAt(text, index)
            if (Character.UnicodeScript.of(codePoint) == Character.UnicodeScript.HAN) {
                return true
            }
            index += Character.charCount(codePoint)
        }
        return false
    }

    fun sourceIsClearlyAQuestion(text: String): Boolean {
        val normalized = text.trim().trimEnd('。', '.', '！', '!').lowercase()
        if (normalized.endsWith('？') || normalized.endsWith('?')) return true
        if (normalized.endsWith("吗") || normalized.endsWith("嘛")) return true

        val directQuestionPrefixes = listOf(
            "为什么", "为啥", "怎么", "如何", "是不是", "是否", "能不能",
            "可不可以", "什么", "谁", "哪里", "哪儿", "什么时候", "多少", "几点",
            "why ", "how ", "what ", "when ", "where ", "who ", "which ",
            "can ", "could ", "would ", "should ", "is ", "are ", "do ",
            "does ", "did "
        )
        return directQuestionPrefixes.any(normalized::startsWith)
    }

    fun candidateIsAQuestion(text: String): Boolean {
        val closingCharacters = "\"'”’）)]}》】"
        val normalized = text.trim().trimEnd { it in closingCharacters }
        return normalized.endsWith('?') || normalized.endsWith('？')
    }

    private data class ActionFamily(
        val sourceSignals: List<String>,
        val candidateSignals: List<String>
    )

    private val actionFamilies = listOf(
        ActionFamily(
            listOf("总结", "概括", "归纳", "summarize", "sum up"),
            listOf("总结", "概括", "归纳", "summarize", "sum up")
        ),
        ActionFamily(
            listOf("翻译", "翻成", "译成", "translate", "render into"),
            listOf("翻译", "翻成", "译成", "translate", "render")
        ),
        ActionFamily(
            listOf("写", "生成", "起草", "创作", "撰写", "write", "draft", "generate", "compose"),
            listOf("写", "生成", "起草", "创作", "撰写", "write", "draft", "generate", "compose", "create")
        ),
        ActionFamily(
            listOf("发送", "发一", "发布", "寄给", "send", "post", "publish", "tweet", "email"),
            listOf("发送", "发一", "发布", "寄给", "send", "post", "publish", "tweet", "email")
        ),
        ActionFamily(
            listOf("告诉", "提醒", "通知", "tell", "remind", "notify"),
            listOf("告诉", "提醒", "通知", "tell", "remind", "notify")
        ),
        ActionFamily(
            listOf("列出", "列一下", "列个", "列一份", "list"),
            listOf("列出", "列一下", "list")
        ),
        ActionFamily(
            listOf("搜索", "查一下", "查找", "找一下", "检索", "search", "look up", "find"),
            listOf("搜索", "查一下", "查找", "找一下", "检索", "search", "look up", "find")
        ),
        ActionFamily(
            listOf("保存", "存到", "save"),
            listOf("保存", "存到", "save")
        ),
        ActionFamily(
            listOf("删除", "删掉", "去掉", "remove", "delete"),
            listOf("删除", "删掉", "去掉", "remove", "delete")
        ),
        ActionFamily(
            listOf("解释", "说明一下", "explain"),
            listOf("解释", "说明一下", "explain")
        )
    )

    private val chineseRequestSignals = listOf(
        "帮我", "请你", "请帮", "麻烦你", "麻烦帮", "替我", "给我",
        "我要你", "我希望你", "你帮我", "你帮忙", "你来", "你把",
        "你可以", "你能", "能不能", "可不可以"
    )

    private val englishRequestSignals = listOf(
        "please ", "could you", "can you", "would you", "will you",
        "help me", "i need you to", "i want you to", "i'd like you to", "let's "
    )

    private val directChineseCommandPrefixes = listOf(
        "总结一下", "概括一下", "翻译一下", "翻成", "写一", "写个", "写份",
        "写封", "写条", "生成一", "起草一", "列出", "列一下", "发一",
        "发送", "发布", "告诉", "提醒", "通知", "搜索", "查一下", "找一下",
        "保存", "打开", "删除", "删掉", "去掉", "修改", "改写", "润色",
        "优化", "解释一下", "说明一下"
    )

    private val directEnglishCommandPrefixes = listOf(
        "summarize ", "translate ", "write ", "draft ", "generate ",
        "create ", "make ", "build ", "design ", "list ", "send ",
        "post ", "publish ", "tweet ", "email ", "tell ", "remind ",
        "notify ", "search ", "look up ", "find ", "save ", "open ",
        "delete ", "remove ", "edit ", "revise ", "rewrite ", "polish ",
        "explain "
    )

    fun sourceRequestsAction(text: String): Boolean {
        val normalized = text.trim().lowercase()
        if (normalized.isEmpty()) return false
        if (chineseRequestSignals.any(normalized::contains) ||
            englishRequestSignals.any(normalized::contains)
        ) return true

        val stripped = stripSpokenLeadIn(normalized)
        if ((stripped.startsWith("把") || stripped.startsWith("将")) &&
            actionFamilies.any { family -> family.sourceSignals.any(stripped::contains) }
        ) return true
        return directChineseCommandPrefixes.any(stripped::startsWith) ||
            directEnglishCommandPrefixes.any(stripped::startsWith)
    }

    fun candidatePreservesRequestedAction(source: String, candidate: String): Boolean {
        val normalizedSource = source.trim().lowercase()
        val normalizedCandidate = candidate.trim().lowercase()
        if (!candidateLooksLikeRequestOrCommand(normalizedCandidate)) return false

        val requiredFamilies = actionFamilies.filter { family ->
            family.sourceSignals.any(normalizedSource::contains)
        }
        return requiredFamilies.all { family ->
            family.candidateSignals.any(normalizedCandidate::contains)
        }
    }

    private fun candidateLooksLikeRequestOrCommand(candidate: String): Boolean {
        if (sourceRequestsAction(candidate)) return true
        val stripped = stripSpokenLeadIn(candidate)
        return directChineseCommandPrefixes.any(stripped::startsWith) ||
            directEnglishCommandPrefixes.any(stripped::startsWith)
    }

    private fun stripSpokenLeadIn(text: String): String {
        var result = text.trim()
        val prefixes = listOf(
            "嗯", "呃", "额", "然后", "那", "那么", "好", "ok", "okay",
            "请", "please"
        )
        var changed = true
        while (changed) {
            changed = false
            for (prefix in prefixes) {
                if (result.startsWith(prefix)) {
                    result = result.removePrefix(prefix)
                        .trimStart { it.isWhitespace() || it in "，,。.!！?？:：;；" }
                    changed = true
                    break
                }
            }
        }
        return result
    }
}
