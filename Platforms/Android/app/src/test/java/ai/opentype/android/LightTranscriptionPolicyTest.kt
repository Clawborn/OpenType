package ai.opentype.android

import ai.opentype.android.ai.LightTranscriptionPolicy
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class LightTranscriptionPolicyTest {
    @Test
    fun shortQuestionIsHandledLocallyAndNeverAnswered() {
        val transcript = "为啥微信不行"
        assertFalse(LightTranscriptionPolicy.shouldUseModel(transcript))
        assertEquals("为啥微信不行？", LightTranscriptionPolicy.localCleanup(transcript))
    }

    @Test
    fun shortStatementKeepsOriginalWording() {
        assertFalse(LightTranscriptionPolicy.shouldUseModel("打开门"))
        assertEquals("打开门", LightTranscriptionPolicy.localCleanup("打开门"))
    }

    @Test
    fun longerMessyDictationMayUseModel() {
        val transcript = "嗯，我想问一下，为什么这个版本在微信里面不行，然后帮我把这句话记下来"
        assertTrue(LightTranscriptionPolicy.shouldUseModel(transcript))
    }

    @Test
    fun generatedAnswerIsRejectedByFaithfulnessGate() {
        val transcript = "嗯，我想问一下，为什么这个版本在微信里面不行，然后帮我把这句话记下来"
        val answer = "微信不行主要是因为它的输入机制并不开放，第三方应用无法直接接管输入。建议你改用系统输入法或者复制粘贴。"
        assertFalse(LightTranscriptionPolicy.acceptModelCandidate(transcript, answer))
    }

    @Test
    fun conservativeCleanupCanPassFaithfulnessGate() {
        val transcript = "嗯，我想问一下，为什么这个版本在微信里面不行，然后帮我把这句话记下来"
        val cleaned = "我想问一下，为什么这个版本在微信里面不行，然后帮我把这句话记下来。"
        assertTrue(LightTranscriptionPolicy.acceptModelCandidate(transcript, cleaned))
    }
}
