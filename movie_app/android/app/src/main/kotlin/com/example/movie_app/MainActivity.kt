package com.example.movie_app

import android.content.ContentValues
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // 必须在 super.onCreate 之后安装，确保我们的原生崩溃处理器最后注册，
        // 能覆盖任何更早注册的 handler，从而稳稳捕获播放器原生崩溃。
        super.onCreate(savedInstanceState)
        CrashHandler.install(this)

        val messenger = flutterEngine?.dartExecutor?.binaryMessenger
        if (messenger != null) {
            // 让 Dart 在播放器后端（media_kit/libmpv）初始化后重新断言崩溃处理器，
            // 抢回可能被覆盖的 native 信号处理器。
            MethodChannel(messenger, "guanzi/crash").setMethodCallHandler { call, result ->
                if (call.method == "reassert") {
                    CrashHandler.install(this)
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }

            // 诊断日志导出：把 App 私有目录里的 guanzi_logs（含 crash_*.txt）打包后的 zip
            // 写入系统「下载」目录，免权限、用户可在任意文件管理器取用/删除。
            MethodChannel(messenger, "guanzi/logExport").setMethodCallHandler { call, result ->
                when (call.method) {
                    "export" -> {
                        val srcPath = call.argument<String>("path")
                        val name = call.argument<String>("name")
                        if (srcPath.isNullOrEmpty() || name.isNullOrEmpty()) {
                            result.error("INVALID_ARGS", "path / name required", null)
                            return@setMethodCallHandler
                        }
                        Thread {
                            try {
                                val dest = exportToDownloads(this, srcPath, name)
                                runOnUiThread { result.success(dest) }
                            } catch (e: Exception) {
                                runOnUiThread {
                                    result.error("EXPORT_FAILED", e.message ?: "export failed", null)
                                }
                            }
                        }.start()
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }
}

/**
 * 把 [srcPath] 这个 zip 写入系统「下载」目录。
 * - Android 10（API 29）及以上：走 MediaStore.Downloads，无需任何存储权限；
 * - 更低版本：写公共 Download 目录（manifest 已声明 WRITE_EXTERNAL_STORAGE 且 maxSdk=28）。
 * 返回用户可见的目标描述（下载目录相对路径或绝对路径）。
 */
private fun exportToDownloads(context: MainActivity, srcPath: String, name: String): String {
    val src = File(srcPath)
    if (!src.exists() || !src.isFile) throw IOException("source zip not found: $srcPath")

    val resolver = context.contentResolver
    val displayPath: String

    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
        val collection = MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        val values = ContentValues().apply {
            put(MediaStore.Downloads.DISPLAY_NAME, name)
            put(MediaStore.Downloads.MIME_TYPE, "application/zip")
            put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
            put(MediaStore.Downloads.IS_PENDING, 1)
        }
        val uri = resolver.insert(collection, values)
            ?: throw IOException("MediaStore insert failed")
        resolver.openOutputStream(uri)?.use { out ->
            src.inputStream().use { it.copyTo(out) }
        } ?: throw IOException("open MediaStore output failed")
        values.clear()
        values.put(MediaStore.Downloads.IS_PENDING, 0)
        resolver.update(uri, values, null, null)
        displayPath = "${Environment.DIRECTORY_DOWNLOADS}/$name"
    } else {
        // Android 9（API 28）及以下：写公共 Download 需要运行时 WRITE_EXTERNAL_STORAGE 权限。
        // 若用户从未授权，直接写会抛 FileNotFoundException(... Permission denied)。
        // 因此先检查权限：有权限写公共下载目录（用户易找）；无权限则降级到
        // 应用外部文件目录（Android/data/<pkg>/files/Download，免权限，且旧系统
        // 的文件管理器可直接访问），保证导出一定成功。
        val granted = context.packageManager.checkPermission(
            android.Manifest.permission.WRITE_EXTERNAL_STORAGE,
            context.packageName,
        ) == android.content.pm.PackageManager.PERMISSION_GRANTED
        val dir = if (granted) {
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
        } else {
            context.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS)
                ?: File(context.filesDir, "Download")
        }
        dir.mkdirs()
        val target = File(dir, name)
        target.outputStream().use { out ->
            src.inputStream().use { it.copyTo(out) }
        }
        displayPath = target.absolutePath
    }
    return displayPath
}
