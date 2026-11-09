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
import android.os.Handler
import android.os.Looper
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * 流体云 / 原子通知 / 焦点通知的**无 SDK** 接入。
 *
 * 用常驻通知 + 系统倒计时（`setUsesChronometer` + `setChronometerCountDown`）表达
 * 「还有多久下课」，由系统决定是否升格成流体云 / 原子通知 / 焦点通知。
 *
 * 曾经用 `Notification.ProgressStyle` 画课程进度条，但 MagicOS 等桌面会把它渲染成
 * 一条静态条（不会随重发前进），所以改成「地点 + 下节课程」的信息，不再依赖进度动画。
 *
 * 课程窗口（几点亮、几点收）用 AlarmManager 排期，App 被杀掉也生效；
 * 进程活着时还有 15 秒一次的进程内刷新；开机 / 应用更新后由 [FluidCloudBootReceiver] 恢复。
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
    const val actionUpdate = "top.anticraft.campus_service.FLUID_UPDATE"
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

    /** 读取 ROM 标识：ColorOS / OriginOS / 荣耀 MagicOS / 澎湃OS（MIUI），其它算通用。 */
    private fun vendor(): Pair<String, String> {
        val oppo = listOf("ro.build.version.opporom", "ro.build.version.oplusrom", "ro.oplus.version")
            .firstNotNullOfOrNull { prop(it).takeIf { v -> v.isNotEmpty() } }
        if (oppo != null) return "coloros" to "ColorOS"
        val vivo = listOf("ro.vivo.os.version", "ro.vivo.rom.version")
            .firstNotNullOfOrNull { prop(it).takeIf { v -> v.isNotEmpty() } }
        if (vivo != null) return "originos" to "OriginOS"
        // 荣耀：MagicOS 有 ro.build.version.magic；厂商 / 品牌也认 HONOR
        val honor = prop("ro.build.version.magic").isNotEmpty() ||
            Build.MANUFACTURER.equals("HONOR", ignoreCase = true) ||
            prop("ro.product.brand").equals("HONOR", ignoreCase = true)
        if (honor) return "magicos" to "荣耀 MagicOS"
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

    private val handler = Handler(Looper.getMainLooper())
    private var ticker: Runnable? = null

    fun show(ctx: Context, w: FluidWindow) {
        if (w.title.isBlank()) return
        // 已经下课：别再亮着（预览 / 迟到的更新闹钟都会走到这里）
        if (System.currentTimeMillis() >= w.endAt) {
            dismiss(ctx)
            return
        }
        if (!buildAndNotify(ctx, w)) return
        // 进程活着时每 15 秒刷一次：预览与「App 在前台」的场景不依赖闹钟，进度一定在动
        startTicker(ctx, w)
        // 进程被杀后的兜底：每分钟一次更新闹钟 + 下课闹钟
        scheduleUpdate(ctx, w)
        setAlarm(ctx, w.endAt, requestCode(w.id, actionEnd), actionEnd, w)
    }

    /** 进程内刷新：进度条与剩余时间跟着走，到点自己收。 */
    private fun startTicker(ctx: Context, w: FluidWindow) {
        val app = ctx.applicationContext
        ticker?.let { handler.removeCallbacks(it) }
        val runnable = object : Runnable {
            override fun run() {
                if (System.currentTimeMillis() >= w.endAt) {
                    dismiss(app)
                    return
                }
                buildAndNotify(app, w)
                handler.postDelayed(this, 15_000L)
            }
        }
        ticker = runnable
        handler.postDelayed(runnable, 15_000L)
    }

    private fun stopTicker() {
        ticker?.let { handler.removeCallbacks(it) }
        ticker = null
    }

    /** 排下一次刷新（进程被杀后由闹钟接着刷进度）。 */
    private fun scheduleUpdate(ctx: Context, w: FluidWindow) {
        val now = System.currentTimeMillis()
        val next = minOf(now + 60_000L, w.endAt - 2_000L)
        if (next <= now) return
        setAlarm(ctx, next, requestCode(w.id, actionUpdate), actionUpdate, w)
    }

    /** 当前窗口之后最近的一节课（只看排期里存着的窗口，最多往后 12 小时）。 */
    private fun nextWindow(ctx: Context, w: FluidWindow): FluidWindow? {
        val windows = decode(prefs(ctx).getString(keyWindows, null))
        return windows
            .filter {
                it.title.isNotBlank() &&
                    it.startAt >= w.endAt &&
                    it.startAt - w.endAt <= 12 * 60 * 60 * 1000L
            }
            .minByOrNull { it.startAt }
    }

    /** 组装并发出通知；返回是否真的发了。 */
    private fun buildAndNotify(ctx: Context, w: FluidWindow): Boolean {
        ensureChannel(ctx)
        val nm = ctx.getSystemService(NotificationManager::class.java) ?: return false
        if (!NotificationManagerCompat.from(ctx).areNotificationsEnabled()) return false
        val content = Intent(ctx, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("antisit.route", "timetable")
        }
        val piFlags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        val contentPi = PendingIntent.getActivity(ctx, 8804, content, piFlags)
        val now = System.currentTimeMillis()
        val status = if (now < w.startAt) {
            val mins = ((w.startAt - now) / 60_000L + 1).coerceAtLeast(1L)
            "$mins 分钟后上课"
        } else {
            val left = ((w.endAt - now) / 60_000L).coerceAtLeast(0L)
            "剩余 ${if (left <= 0) "不到 1" else left} 分钟"
        }
        val place = w.subtitle.trim()
        val timeFmt = SimpleDateFormat("HH:mm", Locale.getDefault())
        // 进度条在部分 ROM 上不会动（MagicOS 等直接渲染成静态条），这里不再用渐进条，
        // 改为「地点 + 下一节课」这种更有用的信息；倒计时仍由系统 chronometer 自己走。
        val next = nextWindow(ctx, w)
        val nextText = next?.let { "下节 ${timeFmt.format(Date(it.startAt))} ${it.title}" }
        val statusLine = listOfNotNull(
            place.takeIf { it.isNotEmpty() },
            if (now < w.startAt) status else (nextText ?: status),
        ).joinToString(" · ")
        val builder = if (Build.VERSION.SDK_INT >= 26) {
            Notification.Builder(ctx, channelId)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(ctx).setPriority(Notification.PRIORITY_LOW)
        }
        builder
            .setSmallIcon(R.drawable.ic_stat_course)
            .setContentTitle(w.title)
            .setContentText(if (place.isEmpty()) "上课中" else place)
            .setSubText(statusLine)
            .setContentIntent(contentPi)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(true)
            .setWhen(w.endAt)
            .setUsesChronometer(true)
            .setChronometerCountDown(true)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setCategory(Notification.CATEGORY_EVENT)
        // Android 16.1 的胶囊文案（有就填，没有就算了）
        runCatching {
            Notification.Builder::class.java
                .getMethod("setShortCriticalText", CharSequence::class.java)
                .invoke(builder, if (now < w.startAt) status else "上课中")
        }
        runCatching {
            builder.addAction(
                Notification.Action.Builder(
                    Icon.createWithResource(ctx, R.drawable.ic_action_timetable),
                    "课表",
                    contentPi,
                ).build()
            )
        }
        runCatching { nm.notify(notificationId, builder.build()) }
        return true
    }

    fun dismiss(ctx: Context) {
        stopTicker()
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
            cancelAlarm(ctx, requestCode(w.id, actionUpdate), actionUpdate, w)
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
            FluidCloud.actionUpdate -> {
                // 每分钟刷新：进度条与「剩余 N 分钟」跟着时间走；过了下课点就收掉
                if (System.currentTimeMillis() >= w.endAt) {
                    FluidCloud.endIfActive(context, w.endAt)
                } else {
                    FluidCloud.markActive(context, w.endAt)
                    FluidCloud.show(context, w)
                }
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
