package com.wefilling.app

import android.app.Activity
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
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.BufferedInputStream
import java.io.BufferedOutputStream
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.util.UUID
import java.util.concurrent.atomic.AtomicBoolean

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
                copySnapshotVideoRange(inputFile, outputFile, startMs, endMs)
                if (!outputFile.isFile || outputFile.length() <= 0L) {
                    throw IllegalStateException("The edited video is empty.")
                }
                runOnUiThread { result.success(outputFile.absolutePath) }
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
    ) {
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
            var maximumInputSize = 1024 * 1024
            for (trackIndex in 0 until extractor.trackCount) {
                val format = extractor.getTrackFormat(trackIndex)
                val mime = format.getString(MediaFormat.KEY_MIME).orEmpty()
                if (!mime.startsWith("video/") && !mime.startsWith("audio/")) {
                    continue
                }
                if (mime.startsWith("video/") && videoTrack < 0) {
                    videoTrack = trackIndex
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
}
