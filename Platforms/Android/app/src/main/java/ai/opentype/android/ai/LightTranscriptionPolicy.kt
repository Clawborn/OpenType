package ai.opentype.android.ai

import kotlin.math.max

object LightTranscriptionPolicy {
    private val fillerSignals = listOf(
        "嗯", "呃", "那个", "就是", "然后然后", "我想说", "怎么说呢",
        "um", "uh", "you know", "i mean"
    )
    private val questionSignals = listOf(
        "为什么", "为啥", "怎么", "如何", "是不是", "能不能", "可以吗", "吗", "呢",
        "why", "how", "what", "when", "where", "who", "can ", "could ", "is ", "are "
    )
    private val terminalPunctuation = setOf('。', '！', '？', '.', '!', '?')

    fun shouldUseModel(text: String): Boolean {
        val normalized = text.trim()
        if (normalized.length > 24 || normalized.contains('\n')) return true
        if (fillerSignals.any { normalized.lowercase().contains(it) }) return true
        return Regex("(.{2,8})[，, ]+\\1").containsMatchIn(normalized)
    }

    fun localCleanup(text: String): String {
        var result = text.trim()
            .replace(Regex("[ \\t]+"), " ")
            .replace(Regex("([，。！？,.!?])\\1+"), "$1")
        result = result.replace(Regex("^(嗯+|呃+|那个)[，,、 ]*"), "")
        if (result.isNotEmpty() && result.last() !in terminalPunctuation && looksLikeQuestion(result)) {
            result += if (containsCjk(result)) "？" else "?"
        }
        return result
    }

    fun acceptModelCandidate(original: String, candidate: String): Boolean {
        val source = comparable(original)
        val output = comparable(candidate)
        if (source.isEmpty() || output.isEmpty()) return false
        if (output.length > max((source.length * 1.34).toInt(), source.length + 8)) return false
        if (output.length < (source.length * 0.52).toInt()) return false
        return similarity(source, output) >= 0.52
    }

    private fun looksLikeQuestion(text: String): Boolean {
        val normalized = text.trim().lowercase()
        return questionSignals.any { signal ->
            if (signal == "吗" || signal == "呢") normalized.endsWith(signal)
            else normalized.startsWith(signal) || normalized.contains(signal)
        }
    }

    private fun containsCjk(text: String): Boolean = text.any { it.code in 0x3400..0x9FFF }

    private fun comparable(text: String): String = text.lowercase()
        .replace(Regex("[\\s，。！？、,.!?;；:'\"“”‘’()（）\\-—]"), "")

    private fun similarity(left: String, right: String): Double {
        val maximum = max(left.length, right.length)
        if (maximum == 0) return 1.0
        return 1.0 - levenshtein(left, right).toDouble() / maximum.toDouble()
    }

    private fun levenshtein(left: String, right: String): Int {
        var previous = IntArray(right.length + 1) { it }
        for (i in left.indices) {
            val current = IntArray(right.length + 1)
            current[0] = i + 1
            for (j in right.indices) {
                val substitution = if (left[i] == right[j]) 0 else 1
                current[j + 1] = minOf(
                    current[j] + 1,
                    previous[j + 1] + 1,
                    previous[j] + substitution
                )
            }
            previous = current
        }
        return previous[right.length]
    }
}
