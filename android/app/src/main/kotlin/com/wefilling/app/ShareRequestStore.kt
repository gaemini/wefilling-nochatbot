package com.wefilling.app

import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.util.UUID

object ShareRequestStore {
    private const val preferencesName = "wefilling_external_shares"
    private const val pendingKey = "pending_shares_json"
    private const val maxImageBytes = 20L * 1024L * 1024L
    private const val retentionMillis = 7L * 24L * 60L * 60L * 1000L
    private val lock = Any()
    private val urlRegex = Regex("https?://[^\\s<>()\\[\\]{}\\\"']+", RegexOption.IGNORE_CASE)

    fun receive(context: Context, intent: Intent): String? {
        val action = intent.action ?: return null
        if (action != Intent.ACTION_SEND && action != Intent.ACTION_SEND_MULTIPLE) return null

        val subject = intent.getStringExtra(Intent.EXTRA_SUBJECT)?.trim().orEmpty()
        val extraText = intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()?.trim().orEmpty()
        val clipText = clipText(intent.clipData)
        val dataText = intent.dataString?.trim().orEmpty()
        val originalText = listOf(subject, extraText, clipText, dataText)
            .filter { it.isNotEmpty() }
            .distinct()
            .joinToString("\n")
        val originalUrl = urlRegex.findAll(originalText)
            .map { trimUrlPunctuation(it.value) }
            .firstOrNull { supportedProvider(it) != "unknown" }
            .orEmpty()
        val normalizedUrl = normalizeSupportedUrl(originalUrl)
        val source = supportedProvider(normalizedUrl)
        // YouTube sometimes includes its app icon (or another ClipData image)
        // alongside the shared URL. The video preview is built from the URL, so
        // that image must not become a normal post attachment.
        val imagePath = if (source == "youtube") {
            ""
        } else {
            firstImageUri(intent)?.let { copyImageToCache(context, it) }.orEmpty()
        }

        if (originalText.isEmpty() && normalizedUrl.isEmpty() && imagePath.isEmpty()) return null

        val id = UUID.randomUUID().toString()
        val request = JSONObject().apply {
            put("id", id)
            put("originalText", originalText)
            put("draftText", "")
            put("originalUrl", originalUrl)
            put("normalizedUrl", normalizedUrl)
            put("imagePath", imagePath)
            put("source", source)
            put("receivedAtMillis", System.currentTimeMillis())
            put("consumed", false)
            put("previewStatus", if (normalizedUrl.isEmpty()) "unavailable" else "pending")
        }
        synchronized(lock) {
            val current = readArray(context)
            val retained = pruned(current)
            retained.put(request)
            writeArray(context, retained)
        }
        return id
    }

    fun pending(context: Context): List<Map<String, Any?>> = synchronized(lock) {
        val retained = pruned(readArray(context))
        writeArray(context, retained)
        buildList {
            for (index in 0 until retained.length()) {
                val value = retained.optJSONObject(index) ?: continue
                if (value.optBoolean("consumed", false)) continue
                add(jsonMap(value))
            }
        }
    }

    fun consume(context: Context, id: String) = synchronized(lock) {
        val current = readArray(context)
        for (index in 0 until current.length()) {
            val value = current.optJSONObject(index) ?: continue
            if (value.optString("id") == id) value.put("consumed", true)
        }
        writeArray(context, pruned(current))
    }

    private fun readArray(context: Context): JSONArray {
        val raw = context.getSharedPreferences(preferencesName, Context.MODE_PRIVATE)
            .getString(pendingKey, "[]") ?: "[]"
        return try {
            JSONArray(raw)
        } catch (_: Throwable) {
            JSONArray()
        }
    }

    private fun writeArray(context: Context, value: JSONArray) {
        context.getSharedPreferences(preferencesName, Context.MODE_PRIVATE)
            .edit()
            .putString(pendingKey, value.toString())
            .commit()
    }

    private fun pruned(source: JSONArray): JSONArray {
        val result = JSONArray()
        val cutoff = System.currentTimeMillis() - retentionMillis
        for (index in 0 until source.length()) {
            val value = source.optJSONObject(index) ?: continue
            if (value.optLong("receivedAtMillis", 0L) < cutoff) {
                value.optString("imagePath").takeIf { it.isNotEmpty() }?.let { File(it).delete() }
                continue
            }
            result.put(value)
        }
        return result
    }

    private fun jsonMap(value: JSONObject): Map<String, Any?> {
        val result = mutableMapOf<String, Any?>()
        val keys = value.keys()
        while (keys.hasNext()) {
            val key = keys.next()
            result[key] = when (val item = value.opt(key)) {
                JSONObject.NULL -> null
                is JSONObject -> jsonMap(item)
                is JSONArray -> (0 until item.length()).map { item.opt(it) }
                else -> item
            }
        }
        return result
    }

    private fun clipText(clipData: ClipData?): String {
        if (clipData == null) return ""
        return buildList {
            for (index in 0 until clipData.itemCount) {
                clipData.getItemAt(index).text?.toString()?.trim()?.takeIf { it.isNotEmpty() }?.let(::add)
            }
        }.distinct().joinToString("\n")
    }

    private fun firstImageUri(intent: Intent): Uri? {
        streamUris(intent).firstOrNull()?.let { return it }
        val clipData = intent.clipData ?: return null
        for (index in 0 until clipData.itemCount) {
            clipData.getItemAt(index).uri?.let { return it }
        }
        return null
    }

    @Suppress("DEPRECATION")
    private fun streamUris(intent: Intent): List<Uri> {
        if (intent.action == Intent.ACTION_SEND_MULTIPLE) {
            return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java).orEmpty()
            } else {
                intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM).orEmpty()
            }
        }
        val single = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
        }
        return listOfNotNull(single)
    }

    private fun copyImageToCache(context: Context, uri: Uri): String? {
        return try {
            val directory = File(context.cacheDir, "external_share_images")
            if (!directory.exists() && !directory.mkdirs()) return null
            val extension = when (context.contentResolver.getType(uri)?.lowercase()) {
                "image/png" -> ".png"
                "image/webp" -> ".webp"
                "image/gif" -> ".gif"
                "image/heic", "image/heif" -> ".heic"
                else -> ".jpg"
            }
            val destination = File(directory, UUID.randomUUID().toString() + extension)
            var total = 0L
            context.contentResolver.openInputStream(uri)?.use { input ->
                FileOutputStream(destination).use { output ->
                    val buffer = ByteArray(DEFAULT_BUFFER_SIZE * 8)
                    while (true) {
                        val count = input.read(buffer)
                        if (count < 0) break
                        total += count
                        if (total > maxImageBytes) throw IllegalArgumentException("Shared image is too large.")
                        output.write(buffer, 0, count)
                    }
                    output.flush()
                }
            } ?: return null
            if (total == 0L) {
                destination.delete()
                null
            } else {
                destination.absolutePath
            }
        } catch (_: Throwable) {
            null
        }
    }

    private fun trimUrlPunctuation(value: String): String =
        value.trim().trimEnd('.', ',', ';', ':', '!', '?', ')', ']', '}')

    private fun supportedProvider(value: String): String {
        val host = runCatching { Uri.parse(value).host?.lowercase().orEmpty().trimEnd('.') }
            .getOrDefault("")
        return when {
            host == "youtu.be" ||
                host == "youtube.com" ||
                host == "www.youtube.com" ||
                host == "m.youtube.com" -> "youtube"
            host == "instagram.com" || host.endsWith(".instagram.com") -> "instagram"
            else -> "unknown"
        }
    }

    private fun normalizeSupportedUrl(value: String): String {
        val provider = supportedProvider(value)
        if (value.isEmpty() || provider == "unknown") return ""
        return runCatching {
            val parsed = Uri.parse(value)
            if (provider == "instagram") {
                val segments = parsed.pathSegments.filter { it.isNotEmpty() }
                if (segments.size != 2 ||
                    (segments[0] != "p" && segments[0] != "reel") ||
                    !segments[1].matches(Regex("^[A-Za-z0-9_-]{3,100}$"))
                ) {
                    return@runCatching ""
                }
                return@runCatching Uri.Builder()
                    .scheme("https")
                    .authority("www.instagram.com")
                    .appendPath(segments[0])
                    .appendPath(segments[1])
                    .appendPath("")
                    .build()
                    .toString()
            }
            Uri.Builder()
                .scheme("https")
                .encodedAuthority(parsed.encodedAuthority?.lowercase())
                .encodedPath(parsed.encodedPath)
                .encodedQuery(parsed.encodedQuery)
                .build()
                .toString()
        }.getOrDefault("")
    }
}
