package ai.opentype.android.data

import android.content.Context
import ai.opentype.android.model.HistoryEntry
import ai.opentype.android.model.InputMode
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.time.Instant
import java.util.UUID

/**
 * Append-only local audit log. Events are newline-delimited JSON and are only
 * appended. UI and Agent memory read a bounded recent window without rewriting
 * or deleting historical records. A process-wide mutex plus an OS file lock
 * keeps the host app and IME from interleaving writes.
 */
class HistoryRepository(context: Context) {
    private val auditFile: File = File(context.applicationContext.filesDir, "opentype-audit/events.jsonl")

    fun entries(limit: Int = DEFAULT_READ_LIMIT): List<HistoryEntry> = synchronized(PROCESS_LOCK) {
        if (!auditFile.isFile) emptyList()
        else recentLines(limit).mapNotNull(::decode)
    }

    fun append(
        requestId: String,
        status: String,
        mode: InputMode,
        rawTranscript: String,
        selectedText: String?,
        result: String?,
        provider: String?,
        model: String?,
        error: String?
    ): HistoryEntry = synchronized(PROCESS_LOCK) {
        require(status in setOf("recognized", "completed", "cancelled", "failed"))
        auditFile.parentFile?.mkdirs()
        val eventId = UUID.randomUUID().toString()
        val createdAt = Instant.now()
        val effectiveMode = if (mode == InputMode.SMART_EDIT && !selectedText.isNullOrBlank()) {
            "selectedEdit"
        } else mode.id
        val event = JSONObject()
            .put("schemaVersion", 1)
            .put("eventId", eventId)
            .put("requestId", requestId)
            .put("createdAt", createdAt.toString())
            .put("platform", "Android")
            .put("status", status)
            .put("mode", effectiveMode)
            .put("rawTranscript", rawTranscript)
            .put("effectiveInput", rawTranscript)
            .put("selectedContext", selectedText ?: JSONObject.NULL)
            .put("result", result ?: JSONObject.NULL)
            .put("provider", provider ?: JSONObject.NULL)
            .put("model", model ?: JSONObject.NULL)
            .put("error", error ?: JSONObject.NULL)
            .put("supersedesEventId", JSONObject.NULL)
        val bytes = (event.toString() + "\n").toByteArray(Charsets.UTF_8)
        FileOutputStream(auditFile, true).channel.use { channel ->
            channel.lock().use {
                val buffer = ByteBuffer.wrap(bytes)
                while (buffer.hasRemaining()) channel.write(buffer)
                channel.force(true)
            }
        }
        HistoryEntry(
            id = eventId,
            requestId = requestId,
            timestampMillis = createdAt.toEpochMilli(),
            mode = mode,
            status = status,
            originalTranscript = rawTranscript,
            selectedText = selectedText,
            output = result.orEmpty(),
            provider = provider,
            model = model,
            error = error
        )
    }

    fun recentAgentContext(limit: Int = 8): String = entries(DEFAULT_READ_LIMIT)
        .asSequence()
        .filter { it.mode == InputMode.AGENT && it.status == "completed" && it.output.isNotBlank() }
        .take(limit)
        .joinToString("\n") { entry ->
            "- Task: ${entry.originalTranscript.take(500)}\n  Result: ${entry.output.take(800)}"
        }

    fun displayEntries(limit: Int = DEFAULT_READ_LIMIT): List<HistoryEntry> =
        entries(limit * 4)
            .asSequence()
            .filter { it.status != "recognized" }
            .distinctBy { it.requestId }
            .take(limit)
            .toList()

    private fun decode(line: String): HistoryEntry? = runCatching {
        val item = JSONObject(line)
        val createdAt = Instant.parse(item.getString("createdAt"))
        HistoryEntry(
            id = item.getString("eventId"),
            requestId = item.getString("requestId"),
            timestampMillis = createdAt.toEpochMilli(),
            mode = InputMode.fromId(item.getString("mode")),
            status = item.getString("status"),
            originalTranscript = item.getString("rawTranscript"),
            selectedText = item.nullableString("selectedContext"),
            output = item.nullableString("result").orEmpty(),
            provider = item.nullableString("provider"),
            model = item.nullableString("model"),
            error = item.nullableString("error")
        )
    }.getOrNull()

    private fun JSONObject.nullableString(key: String): String? =
        if (isNull(key)) null else optString(key).takeIf { it.isNotBlank() }

    /** Reads only the UTF-8 tail needed by the caller, newest event first. */
    private fun recentLines(limit: Int): List<String> {
        if (limit <= 0) return emptyList()
        val output = mutableListOf<String>()
        RandomAccessFile(auditFile, "r").use { file ->
            var position = file.length()
            var pending = ByteArray(0)
            while (position > 0 && output.size < limit) {
                val byteCount = minOf(READ_BLOCK_SIZE.toLong(), position).toInt()
                position -= byteCount
                val block = ByteArray(byteCount)
                file.seek(position)
                file.readFully(block)
                val combined = block + pending
                var lineEnd = combined.size
                for (index in combined.lastIndex downTo 0) {
                    if (combined[index] != '\n'.code.toByte()) continue
                    if (index + 1 < lineEnd) {
                        val line = String(combined, index + 1, lineEnd - index - 1, Charsets.UTF_8).trim()
                        if (line.isNotEmpty()) output += line
                        if (output.size == limit) break
                    }
                    lineEnd = index
                }
                pending = if (output.size == limit) ByteArray(0)
                else combined.copyOfRange(0, lineEnd)
            }
            if (output.size < limit && pending.isNotEmpty()) {
                val line = String(pending, Charsets.UTF_8).trim()
                if (line.isNotEmpty()) output += line
            }
        }
        return output.take(limit)
    }

    companion object {
        private const val DEFAULT_READ_LIMIT = 200
        private const val READ_BLOCK_SIZE = 64 * 1024
        private val PROCESS_LOCK = Any()
    }
}
