package com.wefilling.app

import android.content.ClipData
import android.content.ClipDescription
import android.content.ContentResolver
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.io.InputStream

class MainActivity : FlutterActivity() {
	private val CHANNEL = "com.wefilling.app/share"

	private var methodChannel: MethodChannel? = null

	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)
		methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
	}

	override fun onCreate(savedInstanceState: Bundle?) {
		super.onCreate(savedInstanceState)
		handleShareIntent(intent)
	}

	override fun onNewIntent(intent: Intent) {
		super.onNewIntent(intent)
		handleShareIntent(intent)
	}

	private fun handleShareIntent(intent: Intent?) {
		if (intent == null) return
		val action = intent.action
		val type = intent.type ?: return
		
		android.util.Log.d("Wefilling", "📸 공유 인텐트 수신: action=$action, type=$type")
		
		if (type.startsWith("image/")) {
			when (action) {
				Intent.ACTION_SEND -> {
					val uri: Uri? = intent.getParcelableExtra(Intent.EXTRA_STREAM)
					uri?.let {
						android.util.Log.d("Wefilling", "📸 단일 이미지 처리 중: $it")
						val cached = cacheUriToFile(it)
						if (cached != null) {
							android.util.Log.d("Wefilling", "✅ 이미지 캐시 완료: ${cached.absolutePath}")
							methodChannel?.invokeMethod("sharedImages", listOf(cached.absolutePath))
						} else {
							android.util.Log.e("Wefilling", "❌ 이미지 캐시 실패")
						}
					}
				}
				Intent.ACTION_SEND_MULTIPLE -> {
					val uris: ArrayList<Uri>? = intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM)
					if (!uris.isNullOrEmpty()) {
						android.util.Log.d("Wefilling", "📸 다중 이미지 처리 중: ${uris.size}개")
						val paths = uris.mapNotNull { cacheUriToFile(it)?.absolutePath }
						if (paths.isNotEmpty()) {
							android.util.Log.d("Wefilling", "✅ ${paths.size}개 이미지 캐시 완료")
							methodChannel?.invokeMethod("sharedImages", paths)
						} else {
							android.util.Log.e("Wefilling", "❌ 이미지 캐시 실패")
						}
					}
				}
			}
		}
	}

	private fun cacheUriToFile(uri: Uri): File? {
		return try {
			val cr: ContentResolver = applicationContext.contentResolver
			// 파일명 생성
			val name = queryDisplayName(uri) ?: "shared_${System.currentTimeMillis()}.jpg"
			val outFile = File(cacheDir, name)
			cr.openInputStream(uri)?.use { input ->
				FileOutputStream(outFile).use { output -> copyStream(input, output) }
			}
			outFile
		} catch (e: Exception) {
			null
		}
	}

	private fun copyStream(input: InputStream, output: FileOutputStream) {
		val buffer = ByteArray(8 * 1024)
		while (true) {
			val bytes = input.read(buffer)
			if (bytes <= 0) break
			output.write(buffer, 0, bytes)
		}
		output.flush()
	}

	private fun queryDisplayName(uri: Uri): String? {
		return try {
			val projection = arrayOf(android.provider.MediaStore.MediaColumns.DISPLAY_NAME)
			contentResolver.query(uri, projection, null, null, null)?.use { cursor ->
				val index = cursor.getColumnIndexOrThrow(android.provider.MediaStore.MediaColumns.DISPLAY_NAME)
				if (cursor.moveToFirst()) cursor.getString(index) else null
			}
		} catch (_: Exception) {
			null
		}
	}
}
