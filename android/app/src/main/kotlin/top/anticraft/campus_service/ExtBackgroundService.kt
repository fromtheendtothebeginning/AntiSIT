package top.anticraft.campus_service

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder

/**
 * 拓展后台保活：只负责把进程保持在后台（前台服务 + 常驻通知）。
 *
 * 不执行任何隐藏页面 / 插件代码——插件页本身仍在 Flutter 的 WebView 里跑，
 * 它自己的定时器负责刷新。用户随时可以从通知点回 App 或关掉拓展页停止。
 */
class ExtBackgroundService : Service() {
    companion object {
        const val CHANNEL_ID = "ext_background"
        const val EXTRA_TITLE = "title"
        const val EXTRA_TEXT = "text"
        const val NOTIFICATION_ID = 0x5E4B // 避开拓展通知与上课提醒的区间
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val title = intent?.getStringExtra(EXTRA_TITLE)?.takeIf { it.isNotBlank() }
            ?: "拓展后台运行"
        val text = intent?.getStringExtra(EXTRA_TEXT)?.takeIf { it.isNotBlank() }
            ?: "点按回到 App"

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java)
            if (manager.getNotificationChannel(CHANNEL_ID) == null) {
                manager.createNotificationChannel(
                    NotificationChannel(
                        CHANNEL_ID,
                        "拓展后台运行",
                        NotificationManager.IMPORTANCE_LOW,
                    ).apply {
                        description = "拓展在后台定时刷新时显示的常驻通知"
                        setShowBadge(false)
                    }
                )
            }
        }

        val launch = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            this.flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pending = launch?.let {
            PendingIntent.getActivity(
                this, 0, it,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        builder.setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setOngoing(true)
        if (pending != null) builder.setContentIntent(pending)
        startForeground(NOTIFICATION_ID, builder.build())
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        super.onDestroy()
    }
}
