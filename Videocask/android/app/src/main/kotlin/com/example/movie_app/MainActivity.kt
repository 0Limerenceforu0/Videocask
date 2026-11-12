package com.example.movie_app

import android.content.BroadcastReceiver
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.provider.Settings
import android.view.WindowManager
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.EventChannel
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
            MethodChannel(messenger, "videocask/crash").setMethodCallHandler { call, result ->
                if (call.method == "reassert") {
                    CrashHandler.install(this)
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }

            // 诊断日志导出：把 App 私有目录里的 videocask_logs（含 crash_*.txt）打包后的 zip
            // 写入系统「下载」目录，免权限、用户可在任意文件管理器取用/删除。
            MethodChannel(messenger, "videocask/logExport").setMethodCallHandler { call, result ->
                when (call.method) {
                    "export" -> {
                        val srcPath = call.argument<String>("path")
                        val name = call.argument<String>("name")
                        // 可选：日志包默认 application/zip，数据备份传 application/json。
                        val mime = call.argument<String>("mime") ?: "application/zip"
                        if (srcPath.isNullOrEmpty() || name.isNullOrEmpty()) {
                            result.error("INVALID_ARGS", "path / name required", null)
                            return@setMethodCallHandler
                        }
                        Thread {
                            try {
                                val dest = exportToDownloads(this, srcPath, name, mime)
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

            // ===== 系统音量统一（videocask/volume）=====
            // App 内音量手势 / 滑块与系统音量（STREAM_MUSIC）统一为同一个音量；
            // 实际响度由系统音量决定，播放器保持 100% 直通，仅静音走播放器增益。
            val audioManager = getSystemService(AUDIO_SERVICE) as AudioManager
            val musicStream = AudioManager.STREAM_MUSIC
            fun currentVolumeLevel(): Double {
                val max = audioManager.getStreamMaxVolume(musicStream).coerceAtLeast(1)
                return audioManager.getStreamVolume(musicStream).toDouble() / max
            }
            MethodChannel(messenger, "videocask/volume").setMethodCallHandler { call, result ->
                when (call.method) {
                    "getVolume" -> result.success(currentVolumeLevel())
                    "getMaxVolume" -> result.success(audioManager.getStreamMaxVolume(musicStream))
                    "setVolume" -> {
                        val level = (call.argument<Double>("level") ?: 1.0).coerceIn(0.0, 1.0)
                        val max = audioManager.getStreamMaxVolume(musicStream).coerceAtLeast(1)
                        val idx = ((level * max) + 0.5).toInt().coerceIn(0, max)
                        audioManager.setStreamVolume(musicStream, idx, 0)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

            // ===== 后台播放前台服务（videocask/playbackService）=====
            // Dart 侧在「通知栏显示后台播放」时启动，回到前台/停止播放时关闭。
            // 服务本身不碰播放器，只负责把进程钉在 foreground 优先级。
            MethodChannel(messenger, "videocask/playbackService").setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        val title = call.argument<String>("title")
                        val text = call.argument<String>("text")
                        try {
                            PlaybackForegroundService.start(this, title, text)
                            // Android 13+ 需要通知权限，否则常驻通知不可见（服务仍运行）。
                            // 只请求一次，用户拒绝就不再打扰。
                            if (Build.VERSION.SDK_INT >= 33 &&
                                checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) !=
                                android.content.pm.PackageManager.PERMISSION_GRANTED
                            ) {
                                requestPermissions(
                                    arrayOf(android.Manifest.permission.POST_NOTIFICATIONS),
                                    4101,
                                )
                            }
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("START_FAILED", e.message ?: "start failed", null)
                        }
                    }
                    "stop" -> {
                        try {
                            PlaybackForegroundService.stop(this)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("STOP_FAILED", e.message ?: "stop failed", null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

            // ===== 设备信息（videocask/device）=====
            // 只暴露内存：demuxer 缓冲挡位要按整机内存分档（128~512MB），
            // 并按「系统可用内存」在播放中动态升降档。
            // /proc/meminfo 在 Android 10+ 对普通应用已受限，必须走 ActivityManager。
            MethodChannel(messenger, "videocask/device").setMethodCallHandler { call, result ->
                when (call.method) {
                    "getTotalMemory" -> {
                        val am = getSystemService(ACTIVITY_SERVICE) as android.app.ActivityManager
                        val info = android.app.ActivityManager.MemoryInfo()
                        am.getMemoryInfo(info)
                        result.success(info.totalMem)
                    }
                    // availMem 是系统级「还可用」的内存（含可回收的 page cache），
                    // 正是 lmkd 判据；缩到 128MB 后停 10 分钟再评估就能看出压力。
                    "getAvailableMemory" -> {
                        val am = getSystemService(ACTIVITY_SERVICE) as android.app.ActivityManager
                        val info = android.app.ActivityManager.MemoryInfo()
                        am.getMemoryInfo(info)
                        result.success(info.availMem)
                    }
                    else -> result.notImplemented()
                }
            }

            // ===== 挖孔区绘制（videocask/display）=====
            // 默认（DEFAULT）系统会把前置挖孔划成安全区，应用窗口被裁窄。
            // 实测荣耀 70 横屏：屏幕 2400x1080，mAppBounds 只有 2310x1080，
            // 右侧 90px 永远画不进去（视频因此看起来像「右边一条黑边」）。
            // 全屏播放时切成 ALWAYS/SHORT_EDGES，让画面真正铺满整块屏幕；
            // 退出全屏必须恢复 DEFAULT，否则其它页面顶部/侧边会被挖孔遮挡。
            MethodChannel(messenger, "videocask/display").setMethodCallHandler { call, result ->
                when (call.method) {
                    "setCutoutMode" -> {
                        val allow = call.argument<Boolean>("allow") ?: false
                        applyCutoutMode(allow)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

            // ===== 应用内更新（videocask/update）=====
            // 原生只负责三件事：报 ABI、查/开「安装未知应用」权限、把 APK 交给系统安装器。
            // 版本比较、下载、进度、镜像回退全在 Dart 侧，保持各平台逻辑一致。
            MethodChannel(messenger, "videocask/update").setMethodCallHandler { call, result ->
                when (call.method) {
                    // 设备首选 ABI，用于挑对应架构的 APK。
                    "getAbi" -> result.success(Build.SUPPORTED_ABIS.toList())

                    // Android 8.0 起才有「安装未知应用」开关；更低版本只要
                    // manifest 声明了 REQUEST_INSTALL_PACKAGES 就能直接装。
                    "canRequestInstall" -> result.success(
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            packageManager.canRequestPackageInstalls()
                        } else {
                            true
                        },
                    )

                    "openInstallSettings" -> {
                        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
                            result.success(true)
                            return@setMethodCallHandler
                        }
                        try {
                            val intent = Intent(
                                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                Uri.parse("package:$packageName"),
                            ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }

                    "installApk" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrBlank()) {
                            result.error("BAD_ARGS", "缺少 APK 路径", null)
                            return@setMethodCallHandler
                        }
                        val apk = File(path)
                        if (!apk.exists()) {
                            result.error("FILE_NOT_FOUND", "安装包不存在：$path", null)
                            return@setMethodCallHandler
                        }
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                            !packageManager.canRequestPackageInstalls()
                        ) {
                            result.error("PERMISSION_DENIED", "请先允许「安装未知应用」", null)
                            return@setMethodCallHandler
                        }
                        try {
                            // authority 必须与 AndroidManifest 里的
                            // `${applicationId}.fileprovider` 一致；运行时 packageName 就是 applicationId。
                            // Android 7.0+ 直接传 file:// 会抛 FileUriExposedException，必须走 content://。
                            val uri = FileProvider.getUriForFile(
                                this,
                                "$packageName.fileprovider",
                                apk,
                            )
                            val intent = Intent(Intent.ACTION_VIEW).apply {
                                setDataAndType(uri, "application/vnd.android.package-archive")
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("INSTALL_FAILED", e.message ?: "调起安装器失败", null)
                        }
                    }

                    // 安装前的「降级拦截」：若设备上已装的 versionCode 比新包更高
                    // （常见于残留了更高版本号的测试包），系统会报「已存在更高版本」且原因不明确。
                    // 这里提前读出两者的 versionCode 并比较，给 Dart 层一个明确的引导文案，
                    // 避免用户被系统错误提示搞懵。
                    "verifyUpdateInstall" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrBlank()) {
                            result.error("BAD_ARGS", "缺少 APK 路径", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val pm = packageManager
                            val apkFile = File(path)
                            if (!apkFile.exists()) {
                                result.error("FILE_NOT_FOUND", "安装包不存在：$path", null)
                                return@setMethodCallHandler
                            }
                            val apkInfo = pm.getPackageArchiveInfo(path, 0)
                            val apkVc = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                                apkInfo?.longVersionCode ?: -1L
                            } else {
                                @Suppress("DEPRECATION")
                                (apkInfo?.versionCode?.toLong() ?: -1L)
                            }
                            val installedInfo = try {
                                pm.getPackageInfo(packageName, 0)
                            } catch (_: Exception) {
                                null
                            }
                            val installedVc = if (installedInfo != null) {
                                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                                    installedInfo.longVersionCode
                                } else {
                                    @Suppress("DEPRECATION")
                                    installedInfo.versionCode.toLong()
                                }
                            } else -1L
                            // 未安装过（installedVc<=0）或新包版本号更高才放行；否则视为降级，拦截。
                            val allowed = installedVc <= 0L || apkVc > installedVc
                            val map = HashMap<String, Any>()
                            map["apkVersionCode"] = apkVc
                            map["installedVersionCode"] = installedVc
                            map["allowed"] = allowed
                            result.success(map)
                        } catch (e: Exception) {
                            // 读取失败不应阻断安装，放行并由系统兜底。
                            val map = HashMap<String, Any>()
                            map["apkVersionCode"] = -1L
                            map["installedVersionCode"] = -1L
                            map["allowed"] = true
                            result.success(map)
                        }
                    }

                    else -> result.notImplemented()
                }
            }

            // ===== 硬件音量键 / 系统设置变化回写 Dart（多数设备经 VOLUME_CHANGED_ACTION）。
            val volumeEvents = EventChannel(messenger, "videocask/volumeEvents")
            var volumeSink: EventChannel.EventSink? = null
            val volumeReceiver = object : BroadcastReceiver() {
                override fun onReceive(context: Context?, intent: Intent?) {
                    if (intent?.action == "android.media.VOLUME_CHANGED_ACTION") {
                        // 正确字段名是 "android.media.EXTRA_VOLUME_STREAM_TYPE"（AudioManager
                        // 里同名常量非公开 API，Kotlin 引用会 unresolved，故用字面量）。
                        // 之前写成 "android.media.EXTRA_VOLUME_STREAM"，getIntExtra 恒为 -1，
                        // 导致硬件音量键/系统设置的变化永远回写不到 Dart，App 内音量长期失同步。
                        val streamType = intent
                            .getIntExtra("android.media.EXTRA_VOLUME_STREAM_TYPE", -1)
                            .takeIf { it != -1 }
                            // 少数 ROM 仍发旧字段，做兼容兜底。
                            ?: intent.getIntExtra("android.media.EXTRA_VOLUME_STREAM", -1)
                        if (streamType == musicStream) {
                            volumeSink?.success(currentVolumeLevel())
                        }
                    }
                }
            }
            volumeEvents.setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    volumeSink = events
                    volumeSink?.success(currentVolumeLevel())
                    registerReceiver(
                        volumeReceiver,
                        IntentFilter("android.media.VOLUME_CHANGED_ACTION"),
                        Context.RECEIVER_NOT_EXPORTED,
                    )
                }

                override fun onCancel(arguments: Any?) {
                    try {
                        unregisterReceiver(volumeReceiver)
                    } catch (_: Exception) {
                        // ignore
                    }
                    volumeSink = null
                }
            })
        }
    }

    /**
     * 全屏播放时允许内容绘制到挖孔区，退出全屏恢复默认。
     *
     * 默认模式下系统把挖孔所在边划成安全区：实测荣耀 70 横屏时
     * mAppBounds 只有 2310x1080（屏幕 2400x1080），右侧 90px 无法绘制，
     * 视频看起来就像「右边一条黑边」。全屏切成 ALWAYS（Android 11+）/
     * SHORT_EDGES（Android 9~10）后可铺满整屏，代价是挖孔本身会压在画面上。
     */
    private fun applyCutoutMode(allow: Boolean) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) return
        val mode = when {
            !allow -> WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_DEFAULT
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.R ->
                WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_ALWAYS
            else -> WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
        }
        val attrs = window.attributes
        if (attrs.layoutInDisplayCutoutMode == mode) return
        attrs.layoutInDisplayCutoutMode = mode
        window.attributes = attrs
        // 部分 ROM 改完属性不会立刻重排，显式请求一次。
        window.decorView.requestLayout()
    }
}

/**
 * 把 [srcPath] 这个文件写入系统「下载」目录（日志 zip 或数据备份 json）。
 * - Android 10（API 29）及以上：走 MediaStore.Downloads，无需任何存储权限；
 * - 更低版本：写公共 Download 目录（manifest 已声明 WRITE_EXTERNAL_STORAGE 且 maxSdk=28）。
 * 返回用户可见的目标描述（下载目录相对路径或绝对路径）。
 */
private fun exportToDownloads(context: MainActivity, srcPath: String, name: String, mimeType: String): String {
    val src = File(srcPath)
    if (!src.exists() || !src.isFile) throw IOException("source file not found: $srcPath")

    val resolver = context.contentResolver
    val displayPath: String

    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
        val collection = MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        val values = ContentValues().apply {
            put(MediaStore.Downloads.DISPLAY_NAME, name)
            put(MediaStore.Downloads.MIME_TYPE, mimeType)
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
