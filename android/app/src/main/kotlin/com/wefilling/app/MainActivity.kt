package com.wefilling.app

import android.app.Activity
import android.app.NotificationManager
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.ContentValues
import android.content.Intent
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.media.MediaMuxer
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.MediaStore
import androidx.annotation.NonNull
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.BufferedInputStream
import java.io.BufferedOutputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.util.UUID
import java.util.concurrent.atomic.AtomicBoolean
import org.json.JSONObject

class MainActivity : FlutterActivity() {
    companion object {
        const val externalShareReadyAction = "com.wefilling.app.EXTERNAL_SHARE_READY"
        const val externalShareIdExtra = "externalShareId"
    }

    private val mediaSaverChannelName = "com.wefilling.app/media_saver"
    private val documentImportChannelName = "com.wefilling.app/document_import"
    private val organizationInviteChannelName =
        "com.wefilling.app/organization_invite"
    private val snapshotVideoEditorChannelName =
        "com.wefilling.app/snapshot_video_editor"
    private val notificationCenterChannelName =
        "com.wefilling.app/notification_center"
    private val keyboardGifChannelName = "com.wefilling.app/keyboard_gif"
    private val clipboardImageChannelName = "com.wefilling.app/clipboard_image"
    private val maxClipboardImageBytes = 20 * 1024 * 1024
    private val maxDocumentBytes = 20L * 1024L * 1024L
    private val legacyPhotoSaveRequest = 7241
    private var pendingImageBytes: ByteArray? = null
    private var pendingSaveResult: MethodChannel.Result? = null
    private val mediaSaveInProgress = AtomicBoolean(false)
    private var externalShareChannel: MethodChannel? = null
    private var organizationInviteChannel: MethodChannel? = null
    private var pendingOrganizationInviteUrl: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        captureOrganizationInvite(intent)
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            keyboardGifChannelName,
        ).setMethodCallHandler { call, result ->
            if (call.method != "readGif") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val rawUri = call.argument<String>("uri").orEmpty()
            if (!rawUri.startsWith("content://")) {
                result.error("invalid-uri", "Keyboard content URI required.", null)
                return@setMethodCallHandler
            }
            Thread {
                try {
                    val output = ByteArrayOutputStream()
                    contentResolver.openInputStream(Uri.parse(rawUri)).use { input ->
                        requireNotNull(input)
                        val buffer = ByteArray(8192)
                        while (true) {
                            val count = input.read(buffer)
                            if (count < 0) break
                            if (output.size() + count > 5 * 1024 * 1024) {
                                throw IllegalArgumentException("GIF exceeds size limit")
                            }
                            output.write(buffer, 0, count)
                        }
                    }
                    val bytes = output.toByteArray()
                    runOnUiThread { result.success(bytes) }
                } catch (error: Exception) {
                    runOnUiThread {
                        result.error("gif-unavailable", error.message, null)
                    }
                }
            }.start()
        }
        // 클립보드 이미지 복사·붙여넣기(댓글·스낵챗·DM).
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            clipboardImageChannelName,
        ).setMethodCallHandler { call, result ->
            val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
            when (call.method) {
                "hasImage" -> result.success(clipboardImageUri(clipboard) != null)
                "readImage" -> {
                    val uri = clipboardImageUri(clipboard)
                    if (uri == null) {
                        result.success(null)
                        return@setMethodCallHandler
                    }
                    Thread {
                        try {
                            val mime = contentResolver.getType(uri) ?: "image/*"
                            val output = ByteArrayOutputStream()
                            contentResolver.openInputStream(uri).use { input ->
                                requireNotNull(input)
                                val buffer = ByteArray(8192)
                                while (true) {
                                    val count = input.read(buffer)
                                    if (count < 0) break
                                    if (output.size() + count > maxClipboardImageBytes) {
                                        throw IllegalArgumentException("Image exceeds size limit")
                                    }
                                    output.write(buffer, 0, count)
                                }
                            }
                            val bytes = output.toByteArray()
                            runOnUiThread {
                                result.success(mapOf("bytes" to bytes, "mimeType" to mime))
                            }
                        } catch (error: Exception) {
                            runOnUiThread { result.error("clipboard-image-unavailable", error.message, null) }
                        }
                    }.start()
                }
                "writeImage" -> {
                    val bytes = call.argument<ByteArray>("bytes")
                    val mime = call.argument<String>("mimeType") ?: "image/png"
                    if (bytes == null || bytes.isEmpty() || bytes.size > maxClipboardImageBytes) {
                        result.error("invalid-image-data", "Image bytes are required.", null)
                        return@setMethodCallHandler
                    }
                    Thread {
                        try {
                            val dir = File(cacheDir, "clipboard").apply { mkdirs() }
                            // 이전에 복사한 임시 파일은 지운다(클립보드에는 최신 하나만 남는다).
                            dir.listFiles()?.forEach { it.delete() }
                            val ext = when (mime) {
                                "image/jpeg" -> "jpg"
                                "image/gif" -> "gif"
                                "image/webp" -> "webp"
                                else -> "png"
                            }
                            val file = File(dir, "wefilling_${System.currentTimeMillis()}.$ext")
                            FileOutputStream(file).use { it.write(bytes) }
                            val uri = FileProvider.getUriForFile(
                                this,
                                "$packageName.clipboard_provider",
                                file,
                            )
                            runOnUiThread {
                                try {
                                    clipboard.setPrimaryClip(
                                        ClipData.newUri(contentResolver, "image", uri),
                                    )
                                    result.success(true)
                                } catch (error: Exception) {
                                    result.error("clipboard-write-failed", error.message, null)
                                }
                            }
                        } catch (error: Exception) {
                            runOnUiThread { result.error("clipboard-write-failed", error.message, null) }
                        }
                    }.start()
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            mediaSaverChannelName,
        ).setMethodCallHandler { call, result ->
            if (call.method != "saveImage") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val bytes = call.argument<ByteArray>("bytes")
            val filename = call.argument<String>("filename")?.trim().orEmpty()
            if (bytes == null || bytes.isEmpty()) {
                result.error("invalid-image-data", "Image bytes are required.", null)
                return@setMethodCallHandler
            }
            if (!mediaSaveInProgress.compareAndSet(false, true)) {
                result.error("save-in-progress", "Another image save is in progress.", null)
                return@setMethodCallHandler
            }
            val safeFilename = if (filename.isEmpty()) "wefilling.jpg" else filename
            if (Build.VERSION.SDK_INT <= Build.VERSION_CODES.P) {
                chooseLegacyImageDestination(bytes, safeFilename, result)
                return@setMethodCallHandler
            }
            saveImage(bytes, safeFilename, result)
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            documentImportChannelName,
        ).setMethodCallHandler { call, result ->
            if (call.method != "importDocument") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val uri = call.argument<String>("uri")?.trim().orEmpty()
            val fileName = call.argument<String>("fileName")?.trim().orEmpty()
            if (uri.isEmpty()) {
                result.error("invalid-document-uri", "Document URI is required.", null)
                return@setMethodCallHandler
            }
            importDocument(uri, fileName, result)
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            snapshotVideoEditorChannelName,
        ).setMethodCallHandler { call, result ->
            if (call.method != "trimVideo") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val path = call.argument<String>("path")?.trim().orEmpty()
            val startMs = call.argument<Number>("startMs")?.toLong() ?: -1L
            val endMs = call.argument<Number>("endMs")?.toLong() ?: -1L
            trimSnapshotVideo(path, startMs, endMs, result)
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            notificationCenterChannelName,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "removeDeliveredNotifications" ->
                    removeDeliveredNotifications(call.arguments as? Map<*, *>, result)
                "listDeliveredNotifications" ->
                    listDeliveredNotifications(call.arguments as? Map<*, *>, result)
                "recordLocalNotificationMetadata" ->
                    recordLocalNotificationMetadata(call.arguments as? Map<*, *>, result)
                "registerTodoNotificationMetadata" ->
                    registerTodoNotificationMetadata(call.arguments as? Map<*, *>, result)
                "cancelNotificationSlot" ->
                    cancelNotificationSlot(call.arguments as? Map<*, *>, result)
                else -> result.notImplemented()
            }
        }

        organizationInviteChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            organizationInviteChannelName,
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "getPendingLink" -> result.success(pendingOrganizationInviteUrl)
                    "consumeLink" -> {
                        pendingOrganizationInviteUrl = null
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }

        externalShareChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.wefilling.app/external_share",
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "getPendingShares" -> result.success(
                        ShareRequestStore.pending(applicationContext),
                    )
                    "consumeShare" -> {
                        val id = call.argument<String>("id")?.trim().orEmpty()
                        if (id.isEmpty()) {
                            result.error("invalid-share-id", "Share id is required.", null)
                        } else {
                            ShareRequestStore.consume(applicationContext, id)
                            result.success(null)
                        }
                    }
                    "completeShareFlow" -> {
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        captureOrganizationInvite(intent)
        if (intent.action == externalShareReadyAction) {
            externalShareChannel?.invokeMethod(
                "shareReceived",
                mapOf("id" to intent.getStringExtra(externalShareIdExtra)),
            )
        }
    }

    private fun registerTodoNotificationMetadata(
        rawArguments: Map<*, *>?, result: MethodChannel.Result,
    ) {
        val args = rawArguments ?: emptyMap<Any, Any>()
        val id = (args["id"] as? Number)?.toInt()
        val owner = args["ownerUserId"]?.toString().orEmpty()
        val todo = args["todoId"]?.toString().orEmpty()
        if (id == null || owner.isEmpty() || todo.isEmpty()) {
            result.success(false)
            return
        }
        getSharedPreferences("personal_todo_notification_identity_v1", Context.MODE_PRIVATE)
            .edit().putString(id.toString(), "$owner:$todo").apply()
        result.success(true)
    }

    private fun recordLocalNotificationMetadata(
        rawArguments: Map<*, *>?, result: MethodChannel.Result,
    ) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            result.success(false)
            return
        }
        val args = rawArguments ?: emptyMap<Any, Any>()
        val tag = args["tag"]?.toString().orEmpty()
        val id = (args["id"] as? Number)?.toInt()
        val expectedWhen = (args["when"] as? Number)?.toLong()
        val values = args["payload"] as? Map<*, *>
        if (tag.isEmpty() || id == null || expectedWhen == null || values == null) {
            result.success(false)
            return
        }
        try {
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val active = manager.activeNotifications.firstOrNull {
                it.tag == tag && it.id == id && it.notification.`when` == expectedWhen
            }
            if (active == null) {
                result.success(false)
                return
            }
            val data = JSONObject()
            values.forEach { (key, value) ->
                if (key is String && value is String) data.put(key, value)
            }
            NotificationDeliveryMetadataReceiver.recordLocal(
                this, tag, active.notification.`when`, data,
            )
            result.success(true)
        } catch (_: Exception) {
            result.success(false)
        }
    }

    /**
     * Cancels exactly one notification slot (tag + id). Used before a local
     * chat card is posted so the card FCM rendered for the same room (always
     * id 0) does not remain next to it.
     */
    private fun cancelNotificationSlot(
        rawArguments: Map<*, *>?,
        result: MethodChannel.Result,
    ) {
        val arguments = rawArguments ?: emptyMap<Any, Any>()
        val tag = arguments["tag"]?.toString()?.trim().orEmpty()
        val id = arguments["id"]?.toString()?.toIntOrNull() ?: 0
        if (tag.isEmpty()) {
            result.success(false)
            return
        }
        try {
            val manager = getSystemService(NOTIFICATION_SERVICE) as android.app.NotificationManager
            manager.cancel(tag, id)
            result.success(true)
        } catch (error: Exception) {
            result.success(false)
        }
    }

    private fun removeDeliveredNotifications(
        rawArguments: Map<*, *>?,
        result: MethodChannel.Result,
    ) {
        val arguments = rawArguments ?: emptyMap<Any, Any>()
        val ownerUserId = arguments["ownerUserId"]?.toString()?.trim().orEmpty()
        val kind = arguments["kind"]?.toString()?.trim().orEmpty()
        val notificationId = arguments["notificationId"]?.toString()?.trim().orEmpty()
        val notificationIds = (arguments["notificationIds"] as? List<*>)?.map { it.toString() }?.toSet().orEmpty() + notificationId
        val expectedTags = (arguments["androidTags"] as? List<*>)?.map { it.toString() }?.toSet().orEmpty()
        val roomId = arguments["roomId"]?.toString()?.trim().orEmpty()
        val throughSequence = arguments["throughSequence"]?.toString()?.toLongOrNull() ?: 0L
        val throughSentAtMillis =
            arguments["throughSentAtMillis"]?.toString()?.toLongOrNull() ?: 0L
        val removeAllInRoom = arguments["removeAllInRoom"] == true
        val expectedTag = arguments["androidTag"]?.toString().orEmpty()
        if (ownerUserId.isEmpty()) {
            result.error(
                "invalid-notification-owner",
                "A notification owner is required.",
                null,
            )
            return
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            result.error("notification-removal-unsupported", "Android 6 or newer required", null)
            return
        }
        try {
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            var removed = 0
            var missingMetadata = false
            manager.activeNotifications.forEach activeLoop@{ active ->
                val (payload, metadataProof) = deliveredPayload(active)
                // FCM's automatic renderer does not copy data into extras.
                // Exact app-event tags are immutable. Chat requires the payload
                // captured by the metadata-only receiver, never a tag alone.
                val exactTag = (expectedTag.isNotEmpty() && active.tag == expectedTag) || active.tag in expectedTags
                val payloadOwner = payload["recipientUserId"]
                val todoIdentityMatches = kind == "todo_local" &&
                    getSharedPreferences("personal_todo_notification_identity_v1", Context.MODE_PRIVATE)
                        .getString(active.id.toString(), null) ==
                        "$ownerUserId:${arguments["todoId"]?.toString()}"
                if (payloadOwner.isNullOrEmpty() && (kind == "dm" || kind == "snack_chat") &&
                    active.tag == expectedTag) missingMetadata = true
                val publicAd = kind == "ad" && payload["type"] == "ad_updates" && payload["audience"] == "public"
                if (payloadOwner != ownerUserId && !exactTag && !publicAd &&
                    !todoIdentityMatches) return@activeLoop
                if (!payloadOwner.isNullOrEmpty() && payloadOwner != ownerUserId) return@activeLoop
                val matches = when (kind) {
                    "todo_local" -> (todoIdentityMatches ||
                        (payload["type"] == "personalTodoReminder" &&
                            payload["todoId"] == arguments["todoId"]?.toString())) &&
                        active.postTime < (arguments["throughDeliveredAtMillis"]?.toString()?.toLongOrNull() ?: 0L)
                    "ad" -> exactTag || (publicAd &&
                        payload["bannerId"] == arguments["bannerId"]?.toString() &&
                        payload["notificationVersion"] == arguments["version"]?.toString())
                    "app" -> (payload["notificationId"]?.let { it.isNotEmpty() && it in notificationIds } == true) || exactTag
                    // 알림 화면 '모두 읽음' / 다른 기기의 모두 읽음: DM·스낵챗·할 일·광고를
                    // 뺀 일반 알림 전체. 기준 시각 뒤에 온 새 알림은 남긴다.
                    "all_app" -> {
                        val boundary = arguments["throughDeliveredAtMillis"]?.toString()?.toLongOrNull() ?: 0L
                        payloadOwner == ownerUserId &&
                            payload["type"] !in setOf(
                                "dm_received", "snack_chat_message", "personalTodoReminder", "ad_updates",
                            ) &&
                            !payload["notificationId"].isNullOrEmpty() &&
                            (boundary <= 0L || active.postTime <= boundary)
                    }
                    "snack_chat" -> {
                        val sequence = payload["messageSequence"]?.toLongOrNull() ?: 0L
                        (removeAllInRoom && exactTag && roomId.isNotEmpty()) ||
                        (payload["type"] == "snack_chat_message" &&
                            roomId.isNotEmpty() &&
                            payload["snackChatId"] == roomId &&
                            (removeAllInRoom ||
                                (throughSequence > 0L && sequence in 1..throughSequence)))
                    }
                    "dm" -> {
                        val sentAtMillis = payload["sentAtMillis"]?.toLongOrNull() ?: 0L
                        val seconds = payload["sentAtSeconds"]?.toLongOrNull() ?: 0L
                        val nanos = payload["sentAtNanos"]?.toLongOrNull() ?: -1L
                        val throughSeconds = arguments["throughSeconds"]?.toString()?.toLongOrNull() ?: 0L
                        val throughNanos = arguments["throughNanos"]?.toString()?.toLongOrNull() ?: -1L
                        val exactRead = seconds > 0L && nanos in 0..999999999L &&
                            throughSeconds > 0L && throughNanos in 0..999999999L &&
                            (seconds < throughSeconds || (seconds == throughSeconds && nanos <= throughNanos))
                        (removeAllInRoom && exactTag && roomId.isNotEmpty()) ||
                        (payload["type"] == "dm_received" &&
                            roomId.isNotEmpty() &&
                            payload["conversationId"] == roomId &&
                            (removeAllInRoom || exactRead || (throughSentAtMillis > 0L &&
                            sentAtMillis in 1..throughSentAtMillis)))
                    }
                    else -> false
                }
                if (!matches) return@activeLoop
                if (metadataProof != null && metadataProof !=
                    NotificationDeliveryMetadataReceiver.read(this, active.tag, active.notification.`when`)) return@activeLoop
                // Do not remove a slot replaced while this enumeration ran.
                val latest = manager.activeNotifications.firstOrNull { it.key == active.key }
                if (latest == null || latest.postTime != active.postTime ||
                    latest.notification.`when` != active.notification.`when`) return@activeLoop
                if (active.tag == null) {
                    manager.cancel(active.id)
                } else {
                    manager.cancel(active.tag, active.id)
                }
                removed++
            }
            result.success(if (removed == 0 && missingMetadata) -1 else removed)
        } catch (error: Throwable) {
            result.error(
                "notification-removal-failed",
                error.localizedMessage,
                null,
            )
        }
    }

    /// 알림의 데이터(extras, 로컬 카드 JSON, 메타데이터 수신기 기록)를 합친다.
    private fun deliveredPayload(
        active: android.service.notification.StatusBarNotification,
    ): Pair<MutableMap<String, String>, String?> {
        val payload = mutableMapOf<String, String>()
        val extras = active.notification.extras
        extras.keySet().forEach extrasLoop@{ key ->
            val value = extras.get(key) ?: return@extrasLoop
            payload[key] = value.toString().trim()
        }
        extras.getString("payload")?.let { encoded ->
            runCatching {
                val json = JSONObject(encoded)
                val keys = json.keys()
                while (keys.hasNext()) {
                    val key = keys.next()
                    payload[key] = json.opt(key)?.toString()?.trim().orEmpty()
                }
            }
        }
        val metadataProof = if (payload["type"].isNullOrEmpty()) {
            NotificationDeliveryMetadataReceiver.read(this, active.tag, active.notification.`when`)
        } else null
        metadataProof?.let { encoded ->
            val json = JSONObject(encoded)
            json.keys().forEach { key -> payload[key] = json.optString(key) }
        }
        return payload to metadataProof
    }

    /// 알림센터에 남은 이 계정의 알림 메타데이터(앱 복귀 때 서버 읽음 상태와
    /// 맞춰 정리하는 데 쓴다). 내용·제목은 돌려주지 않는다.
    private fun listDeliveredNotifications(
        rawArguments: Map<*, *>?,
        result: MethodChannel.Result,
    ) {
        val ownerUserId = rawArguments?.get("ownerUserId")?.toString()?.trim().orEmpty()
        if (ownerUserId.isEmpty() || Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            result.success(emptyList<Map<String, Any>>())
            return
        }
        try {
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val items = manager.activeNotifications.mapNotNull { active ->
                val (payload, _) = deliveredPayload(active)
                if (payload["recipientUserId"] != ownerUserId) return@mapNotNull null
                mapOf(
                    "type" to payload["type"].orEmpty(),
                    "notificationId" to payload["notificationId"].orEmpty(),
                    "conversationId" to payload["conversationId"].orEmpty(),
                    "snackChatId" to payload["snackChatId"].orEmpty(),
                    "messageSequence" to (payload["messageSequence"]?.toLongOrNull() ?: 0L),
                    "sentAtMillis" to (payload["sentAtMillis"]?.toLongOrNull() ?: 0L),
                    "deliveredAtMillis" to active.postTime,
                )
            }
            result.success(items)
        } catch (error: Throwable) {
            result.error("notification-list-failed", error.localizedMessage, null)
        }
    }

    private fun captureOrganizationInvite(intent: Intent?) {
        val uri = intent?.data ?: return
        if (uri.scheme == "wefilling" && uri.host == "organization-invite" &&
            !uri.getQueryParameter("token").isNullOrBlank()
        ) {
            pendingOrganizationInviteUrl = uri.toString()
            organizationInviteChannel?.invokeMethod("inviteReceived", null)
        }
    }

    private fun importDocument(
        uriValue: String,
        fileName: String,
        result: MethodChannel.Result,
    ) {
        Thread {
            var outputFile: File? = null
            try {
                val sourceUri = Uri.parse(uriValue)
                val extension = fileName
                    .substringAfterLast('.', "")
                    .lowercase()
                    .takeIf { it.matches(Regex("[a-z0-9]{1,10}")) }
                val importDirectory = File(cacheDir, "snack_chat_document_imports")
                if (!importDirectory.exists() && !importDirectory.mkdirs()) {
                    throw IllegalStateException("Could not create document import cache.")
                }
                val importedFile = File(
                    importDirectory,
                    UUID.randomUUID().toString() + (extension?.let { ".$it" } ?: ""),
                )
                val pendingFile = File(importedFile.absolutePath + ".part")
                outputFile = pendingFile

                val rawInput = when (sourceUri.scheme?.lowercase()) {
                    "content" -> contentResolver.openInputStream(sourceUri)
                    "file" -> FileInputStream(
                        sourceUri.path
                            ?: throw IllegalArgumentException("Invalid file URI."),
                    )
                    else -> throw IllegalArgumentException("Unsupported document URI.")
                } ?: throw IllegalStateException("Could not open the selected document.")

                var totalBytes = 0L
                BufferedInputStream(rawInput).use { input ->
                    FileOutputStream(pendingFile).use { rawOutput ->
                        BufferedOutputStream(rawOutput).use { output ->
                            val buffer = ByteArray(DEFAULT_BUFFER_SIZE * 8)
                            while (true) {
                                val read = input.read(buffer)
                                if (read < 0) break
                                totalBytes += read
                                if (totalBytes > maxDocumentBytes) {
                                    throw IllegalArgumentException("Document exceeds the 20 MB limit.")
                                }
                                output.write(buffer, 0, read)
                            }
                            output.flush()
                            rawOutput.fd.sync()
                        }
                    }
                }
                if (totalBytes <= 0L) {
                    throw IllegalArgumentException("The selected document is empty.")
                }
                if (!pendingFile.renameTo(importedFile)) {
                    throw IllegalStateException("Could not publish the imported document.")
                }
                outputFile = importedFile
                runOnUiThread { result.success(importedFile.absolutePath) }
            } catch (error: Throwable) {
                outputFile?.delete()
                runOnUiThread {
                    result.error(
                        "document-import-failed",
                        error.localizedMessage ?: "Could not import the selected document.",
                        null,
                    )
                }
            }
        }.start()
    }

    private fun trimSnapshotVideo(
        path: String,
        startMs: Long,
        endMs: Long,
        result: MethodChannel.Result,
    ) {
        Thread {
            var outputFile: File? = null
            try {
                val inputFile = File(path)
                require(inputFile.isFile && inputFile.length() > 0L) {
                    "The selected video is unavailable."
                }
                require(startMs >= 0L && endMs > startMs) {
                    "The selected video range is invalid."
                }
                require(endMs - startMs <= 12_000L) {
                    "The selected video range exceeds 12 seconds."
                }

                val outputDirectory = File(cacheDir, "snapshot_video_trims")
                if (!outputDirectory.exists() && !outputDirectory.mkdirs()) {
                    throw IllegalStateException("Could not create the video edit cache.")
                }
                outputDirectory.listFiles()?.forEach { candidate ->
                    if (System.currentTimeMillis() - candidate.lastModified() > 86_400_000L) {
                        candidate.delete()
                    }
                }
                outputFile = File(
                    outputDirectory,
                    "snapshot_${UUID.randomUUID()}.mp4",
                )
                val trackMimes = copySnapshotVideoRange(inputFile, outputFile, startMs, endMs)
                if (!outputFile.isFile || outputFile.length() <= 0L) {
                    throw IllegalStateException("The edited video is empty.")
                }
                runOnUiThread {
                    result.success(
                        mapOf(
                            "path" to outputFile.absolutePath,
                            "videoMime" to trackMimes.first,
                            "audioMime" to trackMimes.second,
                        ),
                    )
                }
            } catch (error: Throwable) {
                outputFile?.delete()
                runOnUiThread {
                    result.error(
                        "snapshot-video-trim-failed",
                        error.localizedMessage ?: "Could not edit the selected video.",
                        null,
                    )
                }
            }
        }.start()
    }

    private fun copySnapshotVideoRange(
        inputFile: File,
        outputFile: File,
        startMs: Long,
        endMs: Long,
    ): Pair<String, String?> {
        val extractor = MediaExtractor()
        var muxer: MediaMuxer? = null
        var muxerStarted = false
        var muxerStopped = false
        try {
            extractor.setDataSource(inputFile.absolutePath)
            val activeMuxer = MediaMuxer(
                outputFile.absolutePath,
                MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4,
            )
            muxer = activeMuxer

            val trackMap = mutableMapOf<Int, Int>()
            var videoTrack = -1
            var videoMime = ""
            var audioMime: String? = null
            var maximumInputSize = 1024 * 1024
            for (trackIndex in 0 until extractor.trackCount) {
                val format = extractor.getTrackFormat(trackIndex)
                val mime = format.getString(MediaFormat.KEY_MIME).orEmpty()
                if (!mime.startsWith("video/") && !mime.startsWith("audio/")) {
                    continue
                }
                if (mime.startsWith("video/") && videoTrack < 0) {
                    videoTrack = trackIndex
                    videoMime = mime
                }
                if (mime.startsWith("audio/") && audioMime == null) {
                    audioMime = mime
                }
                if (format.containsKey(MediaFormat.KEY_MAX_INPUT_SIZE)) {
                    maximumInputSize = maxOf(
                        maximumInputSize,
                        format.getInteger(MediaFormat.KEY_MAX_INPUT_SIZE),
                    )
                }
                trackMap[trackIndex] = activeMuxer.addTrack(format)
                extractor.selectTrack(trackIndex)
            }
            if (videoTrack < 0 || trackMap.isEmpty()) {
                throw IllegalArgumentException("The selected file has no supported video track.")
            }

            val retriever = MediaMetadataRetriever()
            try {
                retriever.setDataSource(inputFile.absolutePath)
                val rotation = retriever.extractMetadata(
                    MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION,
                )?.toIntOrNull()
                if (rotation == 90 || rotation == 180 || rotation == 270) {
                    activeMuxer.setOrientationHint(rotation)
                }
            } finally {
                retriever.release()
            }

            activeMuxer.start()
            muxerStarted = true

            val requestedStartUs = startMs * 1000L
            val requestedEndUs = endMs * 1000L
            extractor.seekTo(requestedStartUs, MediaExtractor.SEEK_TO_NEXT_SYNC)
            val firstSampleUs = extractor.sampleTime
            if (firstSampleUs < 0L || firstSampleUs >= requestedEndUs) {
                throw IllegalArgumentException(
                    "No decodable video frame exists in the selected range.",
                )
            }
            val clipBaseUs = maxOf(requestedStartUs, firstSampleUs)
            val buffer = ByteBuffer.allocateDirect(
                maximumInputSize.coerceIn(1024 * 1024, 32 * 1024 * 1024),
            )
            val bufferInfo = MediaCodec.BufferInfo()
            var videoSamples = 0

            while (true) {
                val sourceTrack = extractor.sampleTrackIndex
                val sampleTimeUs = extractor.sampleTime
                if (sourceTrack < 0 || sampleTimeUs < 0L || sampleTimeUs >= requestedEndUs) {
                    break
                }
                val destinationTrack = trackMap[sourceTrack]
                if (destinationTrack == null || sampleTimeUs < clipBaseUs) {
                    if (!extractor.advance()) break
                    continue
                }

                buffer.clear()
                val sampleSize = extractor.readSampleData(buffer, 0)
                if (sampleSize < 0) break
                bufferInfo.set(
                    0,
                    sampleSize,
                    sampleTimeUs - clipBaseUs,
                    extractor.sampleFlags,
                )
                activeMuxer.writeSampleData(destinationTrack, buffer, bufferInfo)
                if (sourceTrack == videoTrack) videoSamples++
                if (!extractor.advance()) break
            }
            if (videoSamples == 0) {
                throw IllegalArgumentException(
                    "No decodable video frame exists in the selected range.",
                )
            }
            activeMuxer.stop()
            muxerStopped = true
            return Pair(videoMime, audioMime)
        } finally {
            if (muxerStarted && !muxerStopped) {
                runCatching { muxer?.stop() }
            }
            runCatching { muxer?.release() }
            extractor.release()
        }
    }

    private fun chooseLegacyImageDestination(
        bytes: ByteArray,
        filename: String,
        result: MethodChannel.Result,
    ) {
        pendingImageBytes = bytes
        pendingSaveResult = result
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = imageMimeType(filename)
            putExtra(Intent.EXTRA_TITLE, filename)
        }
        try {
            startActivityForResult(intent, legacyPhotoSaveRequest)
        } catch (error: Throwable) {
            clearPendingLegacySave()
            mediaSaveInProgress.set(false)
            result.error(
                "photo-save-failed",
                error.localizedMessage ?: "Could not open the system file picker.",
                null,
            )
        }
    }

    @Deprecated("Deprecated in Android SDK; required for the API 24-28 SAF result.")
    override fun onActivityResult(
        requestCode: Int,
        resultCode: Int,
        data: Intent?,
    ) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != legacyPhotoSaveRequest) return
        val result = pendingSaveResult
        val bytes = pendingImageBytes
        clearPendingLegacySave()
        if (result == null || bytes == null) {
            mediaSaveInProgress.set(false)
            return
        }
        val destination = data?.data
        if (resultCode != Activity.RESULT_OK || destination == null) {
            mediaSaveInProgress.set(false)
            result.error(
                "photo-save-canceled",
                "Image save was canceled.",
                null,
            )
            return
        }
        saveImageToUri(bytes, destination, result)
    }

    private fun clearPendingLegacySave() {
        pendingSaveResult = null
        pendingImageBytes = null
    }

    private fun saveImageToUri(
        bytes: ByteArray,
        destination: Uri,
        result: MethodChannel.Result,
    ) {
        Thread {
            try {
                contentResolver.openOutputStream(destination, "w")?.use { output ->
                    output.write(bytes)
                    output.flush()
                } ?: throw IllegalStateException("Could not open image output stream.")
                runOnUiThread {
                    mediaSaveInProgress.set(false)
                    result.success(null)
                }
            } catch (error: Throwable) {
                runOnUiThread {
                    mediaSaveInProgress.set(false)
                    result.error(
                        "photo-save-failed",
                        error.localizedMessage ?: "Could not save the image.",
                        null,
                    )
                }
            }
        }.start()
    }

    private fun imageMimeType(filename: String): String {
        return when (filename.substringAfterLast('.', "jpg").lowercase()) {
            "png" -> "image/png"
            "gif" -> "image/gif"
            "webp" -> "image/webp"
            "heic", "heif" -> "image/heic"
            "tif", "tiff" -> "image/tiff"
            else -> "image/jpeg"
        }
    }

    private fun saveImage(
        bytes: ByteArray,
        filename: String,
        result: MethodChannel.Result,
    ) {
        Thread {
            try {
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
                    throw IllegalStateException("Legacy image saves must use the system file picker.")
                }
                val values = ContentValues().apply {
                    put(MediaStore.Images.Media.DISPLAY_NAME, filename)
                    put(MediaStore.Images.Media.MIME_TYPE, imageMimeType(filename))
                    put(
                        MediaStore.Images.Media.RELATIVE_PATH,
                        Environment.DIRECTORY_PICTURES + "/Wefilling",
                    )
                    put(MediaStore.Images.Media.IS_PENDING, 1)
                }
                val uri = contentResolver.insert(
                    MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                    values,
                ) ?: throw IllegalStateException("Could not create MediaStore item.")
                try {
                    contentResolver.openOutputStream(uri, "w")?.use { output ->
                        output.write(bytes)
                        output.flush()
                    } ?: throw IllegalStateException("Could not open image output stream.")
                    values.clear()
                    values.put(MediaStore.Images.Media.IS_PENDING, 0)
                    val updated = contentResolver.update(uri, values, null, null)
                    if (updated != 1) {
                        throw IllegalStateException(
                            "Could not publish the MediaStore image.",
                        )
                    }
                } catch (error: Throwable) {
                    contentResolver.delete(uri, null, null)
                    throw error
                }
                runOnUiThread {
                    mediaSaveInProgress.set(false)
                    result.success(null)
                }
            } catch (error: Throwable) {
                runOnUiThread {
                    mediaSaveInProgress.set(false)
                    result.error(
                        "photo-save-failed",
                        error.localizedMessage ?: "Could not save the image.",
                        null,
                    )
                }
            }
        }.start()
    }

    /** 클립보드 첫 항목이 이미지 URI면 돌려준다(텍스트만 있으면 null). */
    private fun clipboardImageUri(clipboard: ClipboardManager): Uri? {
        if (!clipboard.hasPrimaryClip()) return null
        val clip = clipboard.primaryClip ?: return null
        if (clip.itemCount == 0) return null
        val uri = clip.getItemAt(0).uri ?: return null
        val described = (0 until clip.description.mimeTypeCount)
            .any { clip.description.getMimeType(it).startsWith("image/") }
        val resolved = try {
            contentResolver.getType(uri)?.startsWith("image/") == true
        } catch (_: Exception) {
            false
        }
        return if (described || resolved) uri else null
    }
}
