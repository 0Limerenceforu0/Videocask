package com.example.movie_app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager

/**
 * 后台播放保活的前台服务。
 *
 * 为什么必须有它：Android 12+（API 31）起，应用退到后台约 10 秒内会被判定为
 * cached 进程并「冻结」——CPU 调度被暂停，Dart isolate 与 libmpv 的解码线程
 * 一起停摆，表现为「返回桌面后声音继续几秒就没了」。唯一合法解法是持有一个
 * 前台服务，让进程保持在 foreground 优先级。
 *
 * 类型必须是 `mediaPlayback`：Android 14（API 34）对前台服务类型有强制校验，
 * 类型与 Manifest 声明不符会直接抛 `ForegroundServiceTypeNotAllowedException`。
 *
 * 这个服务**不做播放控制**——播放器仍然在 Dart 侧（media_kit/libmpv），
 * 服务只负责「别让系统冻死这个进程」+ 显示一条常驻通知。
 */
class PlaybackForegroundService : Service() {

    companion object {
        private const val CHANNEL_ID = "videocask_playback"
        private const val NOTIFICATION_ID = 1001

        private const val EXTRA_TITLE = "title"
        private const val EXTRA_TEXT = "text"

        fun start(context: Context, title: String?, text: String?) {
            val intent = Intent(context, PlaybackForegroundService::class.java).apply {
                putExtra(EXTRA_TITLE, title)
                putExtra(EXTRA_TEXT, text)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, PlaybackForegroundService::class.java))
        }
    }

    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        ensureChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val title = intent?.getStringExtra(EXTRA_TITLE) ?: "罐子"
        val text = intent?.getStringExtra(EXTRA_TEXT) ?: "正在后台播放"
        val notification = buildNotification(title, text)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }

        acquireWakeLock()
        // 不用 START_STICKY：进程若真被系统杀掉，播放器实例也一并没了，
        // 重启一个空服务毫无意义，反而会留下一条幽灵通知。
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        releaseWakeLock()
        super.onDestroy()
    }

    /**
     * 播放期间持 PARTIAL_WAKE_LOCK：屏幕熄灭后 CPU 仍能跑解码线程。
     * 不持 FULL_WAKE_LOCK——那会强行点亮屏幕，用户只是想在后台听声音。
     */
    private fun acquireWakeLock() {
        if (wakeLock?.isHeld == true) return
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "videocask:playback").apply {
            setReferenceCounted(false)
            try {
                acquire(12 * 60 * 60 * 1000L) // 12 小时上限，防止异常退出后永久持锁
            } catch (_: Exception) {
                // 极端情况下（权限被 ROM 改动）拿不到锁也不影响前台服务本身
            }
        }
    }

    private fun releaseWakeLock() {
        try {
            if (wakeLock?.isHeld == true) wakeLock?.release()
        } catch (_: Exception) {
            // ignore
        }
        wakeLock = null
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (nm.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "后台播放",
            NotificationManager.IMPORTANCE_LOW, // LOW：无声音、不弹横幅，只在通知栏常驻
        ).apply {
            description = "在后台继续播放视频声音时显示"
            setShowBadge(false)
        }
        nm.createNotificationChannel(channel)
    }

    private fun buildNotification(title: String, text: String): Notification {
        val launch = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val pending = if (launch != null) {
            PendingIntent.getActivity(
                this,
                0,
                launch,
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                else
                    PendingIntent.FLAG_UPDATE_CURRENT,
            )
        } else {
            null
        }

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        builder
            .setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setOngoing(true)
            .setShowWhen(false)
            .setPriority(Notification.PRIORITY_LOW)

        if (pending != null) builder.setContentIntent(pending)
        return builder.build()
    }
}
