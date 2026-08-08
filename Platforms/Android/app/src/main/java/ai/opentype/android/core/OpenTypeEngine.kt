package ai.opentype.android.core

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import ai.opentype.android.ai.EditInstructionDetector
import ai.opentype.android.ai.EnglishOutputPolicy
import ai.opentype.android.ai.LightTranscriptionPolicy
import ai.opentype.android.ai.PromptRequest
import ai.opentype.android.ai.TextGenerationClient
import ai.opentype.android.data.AppPreferences
import ai.opentype.android.data.HistoryRepository
import ai.opentype.android.data.SecureTokenStore
import ai.opentype.android.model.InputMode
import ai.opentype.android.model.AppSettings
import ai.opentype.android.model.ProcessRequest
import ai.opentype.android.model.ProcessResult
import ai.opentype.android.model.TextProvider
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.withContext
import java.util.UUID

class OpenTypeEngine(context: Context) {
    private val applicationContext = context.applicationContext
    private val preferences = AppPreferences(applicationContext)
    private val tokens = SecureTokenStore(applicationContext)
    private val history = HistoryRepository(applicationContext)
    private val client = TextGenerationClient()

    suspend fun process(request: ProcessRequest): ProcessResult {
        val requestId = UUID.randomUUID().toString()
        val settings = preferences.load()
        val transcript = request.transcript.trim()
        val selectedText = request.selectedText?.trim()?.takeIf { it.isNotEmpty() }
        val xContext = request.xPostContext?.trim()?.takeIf { it.isNotEmpty() }

        // Password editors are a hard privacy boundary: do not invoke speech
        // transformation, cloud providers, the clipboard, or the audit store.
        if (request.isPasswordField) {
            return ProcessResult.Cancelled("Voice input is unavailable in password fields")
        }

        auditFailure(requestId, request, settings, "recognized", null, null, false)?.let { error ->
            val fallback = failureFallback(request, transcript, selectedText)
            runCatching { copyToClipboard(fallback) }
            return ProcessResult.Failure(
                "Local audit storage is unavailable; no cloud request was sent (${error.safeMessage()})",
                fallback
            )
        }

        if (request.mode != InputMode.X_REPLY && transcript.isEmpty()) {
            auditFailure(requestId, request, settings, "cancelled", null, "No speech was recognized", false)
                ?.let { return auditStorageFailure(it) }
            return ProcessResult.Cancelled("No speech was recognized")
        }
        if (request.mode == InputMode.X_REPLY && xContext == null) {
            auditFailure(requestId, request, settings, "cancelled", null, "Original X post context is required", false)
                ?.let { return auditStorageFailure(it) }
            return ProcessResult.Cancelled("Copy or select the original X post first")
        }
        if (
            request.mode == InputMode.SMART_EDIT &&
            selectedText != null &&
            !EditInstructionDetector.hasExplicitIntent(transcript)
        ) {
            auditFailure(requestId, request, settings, "cancelled", null, "Explicit editing instruction is required", false)
                ?.let { return auditStorageFailure(it) }
            return ProcessResult.Cancelled("Selected text needs an explicit editing instruction")
        }

        if (request.mode == InputMode.TRANSCRIBE && !LightTranscriptionPolicy.shouldUseModel(transcript)) {
            return deliver(
                request = request,
                output = LightTranscriptionPolicy.localCleanup(transcript),
                usedModel = false,
                requestId = requestId,
                settings = settings,
                providerUsed = false
            )
        }

        val token = withContext(Dispatchers.IO) { tokens.token(settings.provider) }
        if (token == null) {
            if (request.mode == InputMode.TRANSCRIBE) {
                return deliver(
                    request = request,
                    output = LightTranscriptionPolicy.localCleanup(transcript),
                    usedModel = false,
                    requestId = requestId,
                    settings = settings,
                    providerUsed = false
                )
            }
            val fallback = failureFallback(request, transcript, selectedText)
            runCatching { copyToClipboard(fallback) }
            auditFailure(requestId, request, settings, "failed", fallback, "Provider token is not configured", false)
                ?.let { return auditStorageFailure(it, fallback) }
            return ProcessResult.Failure("Configure a provider token in OpenType Settings", fallback)
        }

        val prompt = PromptRequest(
            mode = request.mode,
            transcript = transcript,
            selectedText = selectedText,
            xPostContext = xContext,
            recentAgentTasks = if (
                request.mode == InputMode.AGENT &&
                settings.includeRecentTasks &&
                !request.isPasswordField
            ) withContext(Dispatchers.IO) {
                runCatching { history.recentAgentContext() }.getOrDefault("")
            } else ""
        )

        return try {
            val initialCandidate = client.generate(prompt, settings, token)
            val usesDedicatedTranslation = request.mode == InputMode.ENGLISH &&
                settings.provider == TextProvider.DASH_SCOPE
            val candidate = if (usesDedicatedTranslation) {
                require(
                    !EnglishOutputPolicy.requiresRepair(
                        request.mode,
                        transcript,
                        initialCandidate
                    )
                ) { "Dedicated translator returned an invalid English transformation" }
                initialCandidate.trim()
            } else {
                EnglishOutputPolicy.enforce(
                    mode = request.mode,
                    sourceText = transcript,
                    initialCandidate = initialCandidate
                ) {
                    client.generate(
                        prompt.copy(englishOnlyRepair = true),
                        settings,
                        token
                    )
                }
            }
            val output = if (request.mode == InputMode.TRANSCRIBE) {
                if (LightTranscriptionPolicy.acceptModelCandidate(transcript, candidate)) candidate
                else LightTranscriptionPolicy.localCleanup(transcript)
            } else candidate
            deliver(
                request = request,
                output = output,
                usedModel = true,
                requestId = requestId,
                settings = settings,
                providerUsed = true
            )
        } catch (cancelled: CancellationException) {
            // Preserve the audit trail but never turn session cancellation into
            // a fallback clipboard write or an apparent provider failure.
            withContext(NonCancellable + Dispatchers.IO) {
                runCatching {
                    audit(
                        requestId, request, settings, "cancelled", null,
                        "Input session ended before delivery", providerUsed = true
                    )
                }
            }
            throw cancelled
        } catch (error: Throwable) {
            val fallback = failureFallback(request, transcript, selectedText)
            runCatching { copyToClipboard(fallback) }
            val message = error.safeMessage()
            auditFailure(
                requestId, request, settings, "failed", fallback, message,
                providerUsed = true
            )?.let { return auditStorageFailure(it, fallback) }
            ProcessResult.Failure(reason = message, localFallback = fallback)
        }
    }

    private suspend fun deliver(
        request: ProcessRequest,
        output: String,
        usedModel: Boolean,
        requestId: String,
        settings: AppSettings,
        providerUsed: Boolean
    ): ProcessResult {
        val normalized = output.trim()
        if (normalized.isEmpty()) return ProcessResult.Failure("The result was empty")
        // Persist before delivery so a completed task is always locally auditable.
        auditFailure(
            requestId = requestId,
            request = request,
            settings = settings,
            status = "completed",
            result = normalized,
            error = null,
            providerUsed = providerUsed
        )?.let { error ->
            runCatching { copyToClipboard(normalized) }
            return auditStorageFailure(error, normalized)
        }
        copyToClipboard(normalized)
        return ProcessResult.Success(normalized, usedModel, copied = true)
    }

    private suspend fun auditFailure(
        requestId: String,
        request: ProcessRequest,
        settings: AppSettings,
        status: String,
        result: String?,
        error: String?,
        providerUsed: Boolean
    ): Throwable? = withContext(Dispatchers.IO) {
        runCatching {
            audit(requestId, request, settings, status, result, error, providerUsed)
        }.exceptionOrNull()
    }

    private fun auditStorageFailure(error: Throwable, fallback: String? = null): ProcessResult.Failure =
        ProcessResult.Failure(
            "Local audit storage is unavailable (${error.safeMessage()})",
            fallback
        )

    private fun Throwable.safeMessage(): String =
        (message?.take(180)?.takeIf { it.isNotBlank() } ?: "local storage error")

    private fun audit(
        requestId: String,
        request: ProcessRequest,
        settings: AppSettings,
        status: String,
        result: String?,
        error: String?,
        providerUsed: Boolean
    ) {
        if (request.isPasswordField) return
        history.append(
            requestId = requestId,
            status = status,
            mode = request.mode,
            rawTranscript = request.transcript.trim(),
            selectedText = when (request.mode) {
                InputMode.X_REPLY -> request.xPostContext?.trim()
                else -> request.selectedText?.trim()
            },
            result = result,
            provider = settings.provider.id.takeIf { providerUsed },
            model = when {
                !providerUsed -> null
                request.mode == InputMode.ENGLISH &&
                    settings.provider == TextProvider.DASH_SCOPE ->
                    TextGenerationClient.DASH_SCOPE_TRANSLATION_MODEL
                else -> settings.model
            },
            error = error
        )
    }

    private fun copyToClipboard(text: String) {
        if (text.isEmpty()) return
        val clipboard = applicationContext.getSystemService(ClipboardManager::class.java)
        clipboard?.setPrimaryClip(ClipData.newPlainText("OpenType", text))
    }

    private fun failureFallback(
        request: ProcessRequest,
        transcript: String,
        selectedText: String?
    ): String = if (request.mode == InputMode.SMART_EDIT && selectedText != null) {
        selectedText
    } else if (request.mode == InputMode.X_REPLY && transcript.isEmpty()) {
        request.xPostContext.orEmpty()
    } else LightTranscriptionPolicy.localCleanup(transcript)
}
