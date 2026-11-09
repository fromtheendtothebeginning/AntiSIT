package top.anticraft.campus_service

import android.Manifest
import android.app.Activity
import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.drawable.Icon
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import kotlin.math.max

/**
 * 流体云 / 原子通知 / 焦点通知的**无 SDK** 接入。
 *
 * 三家系统都按系统通知规则识别「常驻进度通知」：
 *  - Android 16+：`Notification.ProgressStyle` + `setRequestPromotedOngoing(true)`
 *    （promoted ongoing），由系统决定是否升格成流体云 / 原子通知 / 焦点通知；
 *  - Android 15 及更早：同一套字段退回常驻倒计时通知（`setUsesChronometer` + 倒计时）。
 *
 * 课程窗口（几点亮、几点收）用 AlarmManager 排期，App 被杀掉也生效；
 * 开机 / 应用更新后由 [FluidCloudBootReceiver] 恢复。
 */
data class FluidWindow(
    val id: String,
    val title: String,
    val subtitle: String,
    val startAt: Long,
    val endAt: Long,
    val leadMinutes: Int,
)

object FluidCloud {
    private const val prefsName = "fluid_cloud"
    private const val keyWindows = "windows"
    private const val keyActiveEnd = "active_end"
    private const val channelId = "antisit.course.live"
    private const val notificationId = 8801

    const val actionStart = "top.anticraft.campus_service.FLUID_START"
    const val actionEnd = "top.anticraft.campus_service.FLUID_END"

    // ---------- 系统信息 ----------

    fun info(ctx: Context): Map<String, Any?> {
        val (vendor, label) = vendor()
        return mapOf(
            "vendor" to vendor,
            "label" to label,
            "apiLevel" to Build.VERSION.SDK_INT,
            "notificationsEnabled" to NotificationManagerCompat.from(ctx).areNotificationsEnabled(),
            "exactAlarm" to exactAlarm(ctx),
            "promotedSupported" to (Build.VERSION.SDK_INT >= 36),
        )
    }

    private fun exactAlarm(ctx: Context): Boolean {
        if (Build.VERSION.SDK_INT < 31) return true
        val am = ctx.getSystemService(AlarmManager::class.java) ?: return false
        return am.canScheduleExactAlarms()
    }

    /** 读取 ROM 标识：ColorOS / OriginOS / 澎湃OS（MIUI），其它算通用。 */
    private fun vendor(): Pair<String, String> {
        val oppo = listOf("ro.build.version.opporom", "ro.build.version.oplusrom", "ro.oplus.version")
            .firstNotNullOfOrNull { prop(it).takeIf { v -> v.isNotEmpty() } }
        if (oppo != null) return "coloros" to "ColorOS"
        val vivo = listOf("ro.vivo.os.version", "ro.vivo.rom.version")
            .firstNotNullOfOrNull { prop(it).takeIf { v -> v.isNotEmpty() } }
        if (vivo != null) return "originos" to "OriginOS"
        val hyper = prop("ro.mi.os.version.name")
        if (hyper.isNotEmpty()) return "hyperos" to "澎湃OS"
        val miui = listOf("ro.miui.ui.version.name", "ro.miui.ui.version.code")
            .firstNotNullOfOrNull { prop(it).takeIf { v -> v.isNotEmpty() } }
        if (miui != null) return "hyperos" to "MIUI"
        return "other" to "本机系统"
    }

    private fun prop(key: String): String = try {
        val cls = Class.forName("android.os.SystemProperties")
        val m = cls.getMethod("get", String::class.java)
        (m.invoke(null, key) as? String) ?: ""
    } catch (_: Throwable) {
        ""
    }

    // ---------- 通知 ----------

    private fun ensureChannel(ctx: Context) {
        if (Build.VERSION.SDK_INT < 26) return
        val nm = ctx.getSystemService(NotificationManager::class.java) ?: return
        if (nm.getNotificationChannel(channelId) != null) return
        val ch = NotificationChannel(channelId, "课程流体云", NotificationManager.IMPORTANCE_LOW).apply {
            description = "上课时常驻的流体云 / 原子通知 / 焦点通知"
            setSound(null, null)
            enableVibration(false)
            setShowBadge(false)
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
        }
        nm.createNotificationChannel(ch)
    }

    fun show(ctx: Context, w: FluidWindow) {
        if (w.title.isBlank()) return
        ensureChannel(ctx)
        val nm = ctx.getSystemService(NotificationManager::class.java) ?: return
        if (!NotificationManagerCompat.from(ctx).areNotificationsEnabled()) return
        val content = Intent(ctx, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("antisit.route", "timetable")
        }
        val piFlags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        val contentPi = PendingIntent.getActivity(ctx, 8804, content, piFlags)
        val now = System.currentTimeMillis()
        val span = max(1L, w.endAt - w.startAt)
        val elapsed = (now - w.startAt).coerceIn(0L, span)
        // 状态短语放 subText：紧凑态也能一眼看出「还有多久 / 已经上了多久」
        val status = if (now < w.startAt) {
            val mins = ((w.startAt - now) / 60_000L + 1).coerceAtLeast(1L)
            "$mins 分钟后上课"
        } else {
            val left = ((w.endAt - now) / 60_000L).coerceAtLeast(0L)
            "上课中 · 剩余 ${if (left <= 0) "不到 1" else left} 分钟"
        }
        val builder = if (Build.VERSION.SDK_INT >= 26) {
            Notification.Builder(ctx, channelId)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(ctx).setPriority(Notification.PRIORITY_LOW)
        }
        builder
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(w.title)
            .setContentText(w.subtitle.ifEmpty { "上课中" })
            .setSubText(status)
            .setContentIntent(contentPi)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(true)
            .setWhen(w.endAt)
            .setUsesChronometer(true)
            .setChronometerCountDown(true)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setCategory(Notification.CATEGORY_EVENT)
        runCatching {
            builder.addAction(
                Notification.Action.Builder(
                    Icon.createWithResource(ctx, R.drawable.ic_shortcut_timetable),
                    "课表",
                    contentPi,
                ).build()
            )
        }
        // 16 以下的系统没有 ProgressStyle：用进度条 + 倒计时表达同一件事
        if (Build.VERSION.SDK_INT < 36) {
            runCatching {
                builder.setProgress(100, ((elapsed.toFloat() / span) * 100).toInt().coerceIn(0, 100), false)
            }
        }
        if (Build.VERSION.SDK_INT >= 36) {
            // Android 16 的 live update：分段进度 + promoted ongoing，系统据此决定是否升格
            runCatching {
                val elapsedMin = (elapsed / 60_000L).toInt().coerceAtLeast(1)
                val remainMin = ((span - elapsed) / 60_000L).toInt().coerceAtLeast(1)
                val style = Notification.ProgressStyle()
                    .setProgressSegments(
                        listOf(
                            Notification.ProgressStyle.Segment(elapsedMin),
                            Notification.ProgressStyle.Segment(remainMin),
                        )
                    )
                    .setProgressPoints(
                        listOf(
                            Notification.ProgressStyle.Point(0),
                            Notification.ProgressStyle.Point(elapsedMin + remainMin),
                        )
                    )
                    .setStyledByProgress(true)
                    .setProgress(elapsedMin)
                builder.setStyle(style)
                // setRequestPromotedOngoing 是 36.1 才有的 API：反射调用，
                // 36.0 上不存在就跳过（ProgressStyle + ongoing 本身已经能升格）。
                runCatching {
                    Notification.Builder::class.java
                        .getMethod("setRequestPromotedOngoing", Boolean::class.javaPrimitiveType)
                        .invoke(builder, true)
                }
            }
        }
        runCatching { nm.notify(notificationId, builder.build()) }
    }

    fun dismiss(ctx: Context) {
        val nm = ctx.getSystemService(NotificationManager::class.java) ?: return
        runCatching { nm.cancel(notificationId) }
        prefs(ctx).edit().remove(keyActiveEnd).apply()
    }

    // ---------- 排期 ----------

    fun markActive(ctx: Context, endAt: Long) {
        prefs(ctx).edit().putLong(keyActiveEnd, endAt).apply()
    }

    fun endIfActive(ctx: Context, endAt: Long) {
        val active = prefs(ctx).getLong(keyActiveEnd, 0L)
        if (active == 0L || active == endAt) dismiss(ctx)
    }

    /** 重排整批窗口：先清旧的，再按新表排。返回真正排上的条数（含立即亮的）。 */
    fun schedule(ctx: Context, windows: List<FluidWindow>): Int {
        clear(ctx)
        val now = System.currentTimeMillis()
        val keep = windows.filter { it.title.isNotBlank() && it.endAt > now }
        prefs(ctx).edit().putString(keyWindows, encode(keep)).apply()
        var count = 0
        for (w in keep) {
            val trigger = w.startAt - w.leadMinutes * 60_000L
            if (trigger > now) {
                setAlarm(ctx, trigger, requestCode(w.id, actionStart), actionStart, w)
                count++
            } else if (w.endAt > now) {
                // 已经在课上：切到流体云模式时立刻亮当前这节
                markActive(ctx, w.endAt)
                show(ctx, w)
                count++
            }
            if (w.endAt > now) {
                setAlarm(ctx, w.endAt, requestCode(w.id, actionEnd), actionEnd, w)
            }
        }
        return count
    }

    /** 清掉本插件排的全部闹钟并收起通知。 */
    fun clear(ctx: Context) {
        val old = decode(prefs(ctx).getString(keyWindows, null))
        for (w in old) {
            cancelAlarm(ctx, requestCode(w.id, actionStart), actionStart, w)
            cancelAlarm(ctx, requestCode(w.id, actionEnd), actionEnd, w)
        }
        prefs(ctx).edit().remove(keyWindows).apply()
        dismiss(ctx)
    }

    /** 开机 / 应用更新后恢复排期；已经在上的课立刻亮。 */
    fun restore(ctx: Context) {
        val windows = decode(prefs(ctx).getString(keyWindows, null))
        if (windows.isEmpty()) return
        schedule(ctx, windows)
    }

    private fun setAlarm(ctx: Context, triggerAt: Long, code: Int, action: String, w: FluidWindow) {
        val am = ctx.getSystemService(AlarmManager::class.java) ?: return
        val pi = alarmPending(ctx, code, action, w)
        try {
            if (Build.VERSION.SDK_INT >= 31 && !am.canScheduleExactAlarms()) {
                am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pi)
            } else {
                am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pi)
            }
        } catch (_: SecurityException) {
            am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pi)
        }
    }

    private fun cancelAlarm(ctx: Context, code: Int, action: String, w: FluidWindow) {
        val am = ctx.getSystemService(AlarmManager::class.java) ?: return
        runCatching { am.cancel(alarmPending(ctx, code, action, w)) }
    }

    private fun alarmPending(ctx: Context, code: Int, action: String, w: FluidWindow): PendingIntent {
        val intent = Intent(ctx, FluidCloudReceiver::class.java).setAction(action)
            .putExtra("id", w.id)
            .putExtra("title", w.title)
            .putExtra("subtitle", w.subtitle)
            .putExtra("startAt", w.startAt)
            .putExtra("endAt", w.endAt)
            .putExtra("leadMinutes", w.leadMinutes)
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        return PendingIntent.getBroadcast(ctx, code, intent, flags)
    }

    private fun requestCode(id: String, action: String): Int = (id + action).hashCode()

    private fun prefs(ctx: Context) = ctx.getSharedPreferences(prefsName, Context.MODE_PRIVATE)

    private fun encode(windows: List<FluidWindow>): String {
        val arr = JSONArray()
        for (w in windows) {
            arr.put(JSONObject().apply {
                put("id", w.id)
                put("title", w.title)
                put("subtitle", w.subtitle)
                put("startAt", w.startAt)
                put("endAt", w.endAt)
                put("leadMinutes", w.leadMinutes)
            })
        }
        return arr.toString()
    }

    private fun decode(raw: String?): List<FluidWindow> {
        if (raw.isNullOrBlank()) return emptyList()
        return try {
            val arr = JSONArray(raw)
            (0 until arr.length()).mapNotNull { i ->
                val o = arr.optJSONObject(i) ?: return@mapNotNull null
                FluidWindow(
                    id = o.optString("id"),
                    title = o.optString("title"),
                    subtitle = o.optString("subtitle"),
                    startAt = o.optLong("startAt"),
                    endAt = o.optLong("endAt"),
                    leadMinutes = o.optInt("leadMinutes", 15),
                )
            }
        } catch (_: Throwable) {
            emptyList()
        }
    }
}

/** 闹钟到点：开始 → 亮通知；结束 → 收起（只收当前这条）。 */
class FluidCloudReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context?, intent: Intent?) {
        if (context == null || intent == null) return
        val w = FluidWindow(
            id = intent.getStringExtra("id") ?: "",
            title = intent.getStringExtra("title") ?: "",
            subtitle = intent.getStringExtra("subtitle") ?: "",
            startAt = intent.getLongExtra("startAt", 0L),
            endAt = intent.getLongExtra("endAt", 0L),
            leadMinutes = intent.getIntExtra("leadMinutes", 15),
        )
        when (intent.action) {
            FluidCloud.actionStart -> {
                FluidCloud.markActive(context, w.endAt)
                FluidCloud.show(context, w)
            }
            FluidCloud.actionEnd -> FluidCloud.endIfActive(context, w.endAt)
        }
    }
}

/** 开机 / 应用更新后恢复课程窗口排期。 */
class FluidCloudBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context?, intent: Intent?) {
        if (context == null) return
        when (intent?.action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            "android.intent.action.QUICKBOOT_POWERON",
            "com.htc.intent.action.QUICKBOOT_POWERON" -> FluidCloud.restore(context)
        }
    }
}

/** Dart 侧 `antisit/fluid_cloud` 通道。 */
class FluidCloudBridge(private val activity: Activity) {
    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, "antisit/fluid_cloud").setMethodCallHandler { call, result ->
            when (call.method) {
                "info" -> result.success(FluidCloud.info(activity))
                "show" -> {
                    val w = parseWindow(call.arguments)
                    if (w == null) {
                        result.error("args", "缺少窗口参数", null)
                    } else {
                        FluidCloud.show(activity, w)
                        result.success(true)
                    }
                }
                "dismiss" -> {
                    FluidCloud.dismiss(activity)
                    result.success(true)
                }
                "schedule" -> result.success(FluidCloud.schedule(activity, parseWindows(call.arguments)))
                "clear" -> {
                    FluidCloud.clear(activity)
                    result.success(true)
                }
                "requestPermission" -> result.success(requestNotifications())
                else -> result.notImplemented()
            }
        }
    }

    private fun requestNotifications(): Boolean {
        val nm = NotificationManagerCompat.from(activity)
        if (Build.VERSION.SDK_INT < 33) return nm.areNotificationsEnabled()
        val granted = ContextCompat.checkSelfPermission(
            activity, Manifest.permission.POST_NOTIFICATIONS
        ) == PackageManager.PERMISSION_GRANTED
        if (!granted) {
            ActivityCompat.requestPermissions(
                activity, arrayOf(Manifest.permission.POST_NOTIFICATIONS), 9001
            )
        }
        return granted
    }

    private fun parseWindow(args: Any?): FluidWindow? {
        val map = args as? Map<*, *> ?: return null
        return FluidWindow(
            id = "${map["id"] ?: ""}",
            title = "${map["title"] ?: ""}",
            subtitle = "${map["subtitle"] ?: ""}",
            startAt = (map["startAt"] as? Number)?.toLong() ?: 0L,
            endAt = (map["endAt"] as? Number)?.toLong() ?: 0L,
            leadMinutes = (map["leadMinutes"] as? Number)?.toInt() ?: 15,
        )
    }

    private fun parseWindows(args: Any?): List<FluidWindow> {
        val list = (args as? Map<*, *>)?.get("windows") as? List<*> ?: return emptyList()
        return list.mapNotNull { parseWindow(it) }
    }
}
