package ai.opentype.android.ai

import ai.opentype.android.model.AppSettings
import ai.opentype.android.model.InputMode
import ai.opentype.android.model.TextProvider
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

class TextGenerationClient {
    companion object {
        const val DASH_SCOPE_TRANSLATION_MODEL = "qwen-mt-flash"
    }

    suspend fun generate(
        prompt: PromptRequest,
        settings: AppSettings,
        token: String
    ): String = withContext(Dispatchers.IO) {
        val endpoint = validateEndpoint(settings.endpoint)
        val body = requestBody(prompt, settings)

        val connection = (endpoint.openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            connectTimeout = 20_000
            readTimeout = 90_000
            doOutput = true
            instanceFollowRedirects = false
            setRequestProperty("Content-Type", "application/json")
            setRequestProperty("Accept", "application/json")
            if (settings.provider == TextProvider.ANTHROPIC) {
                setRequestProperty("x-api-key", token.trim())
                setRequestProperty("anthropic-version", "2023-06-01")
            } else {
                setRequestProperty("Authorization", "Bearer ${token.trim()}")
            }
        }
        try {
            connection.outputStream.writer(Charsets.UTF_8).buffered().use { it.write(body.toString()) }
            val status = connection.responseCode
            val response = (if (status in 200..299) connection.inputStream else connection.errorStream)
                ?.bufferedReader(Charsets.UTF_8)
                ?.use { it.readText() }
                .orEmpty()
            if (status !in 200..299) {
                val safeMessage = runCatching {
                    JSONObject(response).optJSONObject("error")?.optString("message")
                }.getOrNull().orEmpty().take(240)
                error(if (safeMessage.isBlank()) "Provider request failed (HTTP $status)" else safeMessage)
            }
            if (settings.provider == TextProvider.ANTHROPIC) {
                parseAnthropicContent(response)
            } else parseOpenAICompatibleContent(response)
        } finally {
            connection.disconnect()
        }
    }

    internal fun effectiveModel(prompt: PromptRequest, settings: AppSettings): String =
        if (prompt.mode == InputMode.ENGLISH && settings.provider == TextProvider.DASH_SCOPE) {
            DASH_SCOPE_TRANSLATION_MODEL
        } else settings.model.trim()

    internal fun requestBody(prompt: PromptRequest, settings: AppSettings): JSONObject =
        if (prompt.mode == InputMode.ENGLISH && settings.provider == TextProvider.DASH_SCOPE) {
            JSONObject()
                .put("model", DASH_SCOPE_TRANSLATION_MODEL)
                .put(
                    "messages",
                    JSONArray().put(
                        JSONObject()
                            .put("role", "user")
                            .put("content", prompt.transcript.trim())
                    )
                )
                .put(
                    "translation_options",
                    JSONObject()
                        .put("source_lang", "auto")
                        .put("target_lang", "English")
                )
                .put("temperature", 0)
        } else if (settings.provider == TextProvider.ANTHROPIC) {
            JSONObject()
                .put("model", effectiveModel(prompt, settings))
                .put("max_tokens", 2_048)
                .put("system", PromptFactory.system(prompt))
                .put(
                    "messages",
                    JSONArray().put(
                        JSONObject().put("role", "user").put("content", PromptFactory.user(prompt))
                    )
                )
        } else {
            JSONObject()
                .put("model", effectiveModel(prompt, settings))
                .put(
                    "messages",
                    JSONArray()
                        .put(JSONObject().put("role", "system").put("content", PromptFactory.system(prompt)))
                        .put(JSONObject().put("role", "user").put("content", PromptFactory.user(prompt)))
                )
                .also { body ->
                    if (settings.provider != TextProvider.OPENAI) {
                        body.put("temperature", if (prompt.mode == InputMode.X_REPLY) 0.45 else 0.2)
                    }
                }
        }

    private fun validateEndpoint(rawValue: String): URL {
        val url = URL(rawValue.trim())
        val localHost = url.host.equals("localhost", true) ||
            url.host == "127.0.0.1" || url.host == "10.0.2.2"
        require(url.protocol == "https" || (url.protocol == "http" && localHost)) {
            "Provider URL must use HTTPS (HTTP is allowed only for a local development server)"
        }
        require(url.path.isNotBlank()) { "Provider URL must include the chat completions path" }
        return url
    }

    private fun parseOpenAICompatibleContent(response: String): String {
        val root = JSONObject(response)
        val message = root.getJSONArray("choices").getJSONObject(0).getJSONObject("message")
        val content = message.opt("content")
        val text = when (content) {
            is String -> content
            is JSONArray -> buildString {
                for (index in 0 until content.length()) {
                    val part = content.optJSONObject(index) ?: continue
                    if (part.optString("type") == "text") append(part.optString("text"))
                }
            }
            else -> ""
        }.trim()
        require(text.isNotEmpty()) { "Provider returned an empty result" }
        return text
    }

    private fun parseAnthropicContent(response: String): String {
        val blocks = JSONObject(response).getJSONArray("content")
        val text = buildString {
            for (index in 0 until blocks.length()) {
                val block = blocks.optJSONObject(index) ?: continue
                if (block.optString("type") == "text") append(block.optString("text"))
            }
        }.trim()
        require(text.isNotEmpty()) { "Provider returned an empty result" }
        return text
    }
}
