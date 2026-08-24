package com.wefilling.app

import android.app.Activity
import android.content.ContentValues
import android.content.Intent
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
import java.util.UUID
import java.util.concurrent.atomic.AtomicBoolean

class MainActivity : FlutterActivity() {
    companion object {
        const val externalShareReadyAction = "com.wefilling.app.EXTERNAL_SHARE_READY"
        const val externalShareIdExtra = "externalShareId"
    }

    private val mediaSaverChannelName = "com.wefilling.app/media_saver"
    private val documentImportChannelName = "com.wefilling.app/document_import"
    private val maxDocumentBytes = 20L * 1024L * 1024L
    private val legacyPhotoSaveRequest = 7241
    private var pendingImageBytes: ByteArray? = null
    private var pendingSaveResult: MethodChannel.Result? = null
    private val mediaSaveInProgress = AtomicBoolean(false)
    private var externalShareChannel: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
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
        if (intent.action == externalShareReadyAction) {
            externalShareChannel?.invokeMethod(
                "shareReceived",
                mapOf("id" to intent.getStringExtra(externalShareIdExtra)),
            )
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
