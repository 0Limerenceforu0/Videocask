package com.example.movie_app

import android.content.Context
import java.io.File
import java.io.PrintWriter
import java.io.StringWriter
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * 崩溃捕获（无需电脑）：
 * 1) Native 层信号处理器（libcrashhandler.so）：捕获 SIGSEGV/SIGBUS/SIGABRT/SIGILL/SIGFPE，
 *    把调用栈写入 videocask_logs/crash_*.txt；
 * 2) Java 层未捕获异常处理器：捕获主线程/其他线程的 Java 崩溃，写入 java_crash_*.txt；
 * 3) install() 可重复调用以「抢回」被播放器后端覆盖的 native 信号处理器。
 */
object CrashHandler {
    init {
        System.loadLibrary("crashhandler")
    }

    private external fun nativeInstall(logDir: String)

    fun install(context: Context) {
        val base = context.getExternalFilesDir(null) ?: context.filesDir
        val dir = File(base, "videocask_logs")
        try {
            dir.mkdirs()
        } catch (_: Exception) {
            // 忽略：写入时会再次尝试创建
        }
        // Native 信号处理器（可重复调用，重新注册以抢回被覆盖的处理器）
        try {
            nativeInstall(dir.absolutePath)
        } catch (_: Exception) {
        }
        // Java 层未捕获异常处理器（抓 Java 侧崩溃）
        installJavaHandler(dir)
    }

    private fun installJavaHandler(dir: File) {
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, throwable ->
            try {
                writeJavaCrash(dir, throwable)
            } catch (_: Exception) {
                // 忽略写入失败
            }
            // 交给系统默认处理器：仍会弹「应用已停止运行」并终止进程
            previous?.uncaughtException(thread, throwable)
        }
    }

    private fun writeJavaCrash(dir: File, t: Throwable) {
        val stamp = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(Date())
        val file = File(dir, "java_crash_$stamp.txt")
        try {
            PrintWriter(file, "UTF-8").use { w ->
                w.println("Videocask Java crash")
                w.println("time: $stamp")
                w.println("message: ${t.message ?: t.javaClass.name}")
                val sw = StringWriter()
                t.printStackTrace(PrintWriter(sw))
                w.println(sw.toString())
            }
        } catch (_: Exception) {
        }
    }
}
