package com.wefilling.app

import android.Manifest
import android.content.ContentValues
import android.content.pm.PackageManager
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import androidx.annotation.NonNull
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
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
    private val mediaSaverChannelName = "com.wefilling.app/media_saver"
    private val documentImportChannelName = "com.wefilling.app/document_import"
    private val maxDocumentBytes = 20L * 1024L * 1024L
    private val photoWritePermissionRequest = 7241
    private var pendingImageBytes: ByteArray? = null
    private var pendingImageFilename: String? = null
    private var pendingSaveResult: MethodChannel.Result? = null
    private val mediaSaveInProgress = AtomicBoolean(false)

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
            if (
                Build.VERSION.SDK_INT <= Build.VERSION_CODES.P &&
                ContextCompat.checkSelfPermission(
                    this,
                    Manifest.permission.WRITE_EXTERNAL_STORAGE,
                ) != PackageManager.PERMISSION_GRANTED
            ) {
                pendingImageBytes = bytes
                pendingImageFilename = safeFilename
                pendingSaveResult = result
                ActivityCompat.requestPermissions(
                    this,
                    arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE),
                    photoWritePermissionRequest,
                )
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

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != photoWritePermissionRequest) return
        val result = pendingSaveResult
        val bytes = pendingImageBytes
        val filename = pendingImageFilename
        pendingSaveResult = null
        pendingImageBytes = null
        pendingImageFilename = null
        if (result == null || bytes == null || filename == null) return
        if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
            saveImage(bytes, filename, result)
        } else {
            mediaSaveInProgress.set(false)
            result.error(
                "photo-permission-denied",
                "Photo write permission was denied.",
                null,
            )
        }
    }

    private fun saveImage(
        bytes: ByteArray,
        filename: String,
        result: MethodChannel.Result,
    ) {
        Thread {
            try {
                val mimeType = when (filename.substringAfterLast('.', "jpg").lowercase()) {
                    "png" -> "image/png"
                    "gif" -> "image/gif"
                    "webp" -> "image/webp"
                    "heic", "heif" -> "image/heic"
                    "tif", "tiff" -> "image/tiff"
                    else -> "image/jpeg"
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    val values = ContentValues().apply {
                        put(MediaStore.Images.Media.DISPLAY_NAME, filename)
                        put(MediaStore.Images.Media.MIME_TYPE, mimeType)
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
                } else {
                    @Suppress("DEPRECATION")
                    val directory = File(
                        Environment.getExternalStoragePublicDirectory(
                            Environment.DIRECTORY_PICTURES,
                        ),
                        "Wefilling",
                    )
                    if (!directory.exists() && !directory.mkdirs()) {
                        throw IllegalStateException("Could not create Pictures directory.")
                    }
                    var outputFile = File(directory, filename)
                    if (outputFile.exists()) {
                        outputFile = File(
                            directory,
                            outputFile.nameWithoutExtension + "_" +
                                System.currentTimeMillis() + "." + outputFile.extension,
                        )
                    }
                    outputFile.outputStream().use { output ->
                        output.write(bytes)
                        output.flush()
                    }
                    MediaScannerConnection.scanFile(
                        this,
                        arrayOf(outputFile.absolutePath),
                        arrayOf(mimeType),
                        null,
                    )
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

