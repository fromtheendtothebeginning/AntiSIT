package top.anticraft.campus_service

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.view.View
import android.widget.RemoteViews
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * 桌面卡片（App Widget）与长按图标的快捷方式。
 *
 * * 两张卡片：**今日课程**（今天前 3 节 + 下一节）、**校园卡余额**；标准 App Widget，
 *   ColorOS / OriginOS / 澎湃OS 等桌面都支持。
 * * App 侧只同步「最近一次的数据」，渲染在 [TimetableWidgetProvider] / [EcardWidgetProvider]。
 * * 点卡片 / 长按图标快捷方式带 `antisit.route`（ecard / timetable）进来，转给 Flutter 切页。
 */
object HomeWidget {
    private const val prefsName = "home_widget"
    private const val keyTimetable = "timetable"
    private const val keyBalance = "balance"
    private const val keyBalanceAt = "balance_at"
    private const val keyLaunch = "launch_action"

    private const val routeExtra = "antisit.route"

    /** Dart 侧通道：注册后原生点卡片也会即时通知（App 在前台时不用等重启）。 */
    var channel: MethodChannel? = null

    private fun prefs(ctx: Context) = ctx.getSharedPreferences(prefsName, Context.MODE_PRIVATE)

    // ---------- 数据同步 ----------

    fun saveTimetable(
        ctx: Context,
        day: String,
        date: String,
        courses: JSONArray,
        next: JSONObject?,
    ) {
        val obj = JSONObject().put("day", day).put("date", date).put("courses", courses)
        if (next != null) obj.put("next", next)
        prefs(ctx).edit().putString(keyTimetable, obj.toString()).apply()
        updateAll(ctx)
    }

    fun saveBalance(ctx: Context, balance: String?) {
        prefs(ctx).edit()
            .putString(keyBalance, balance ?: "")
            .putLong(keyBalanceAt, System.currentTimeMillis())
            .apply()
        updateAll(ctx)
    }

    fun takeLaunch(ctx: Context): String? {
        val action = prefs(ctx).getString(keyLaunch, null)
        if (action != null) prefs(ctx).edit().remove(keyLaunch).apply()
        return action
    }

    /** 冷启动 / onNewIntent 收到的入口动作：存下来并尽量即时通知 Flutter。 */
    fun setLaunch(ctx: Context, action: String) {
        if (action.isBlank()) return
        prefs(ctx).edit().putString(keyLaunch, action).apply()
        runCatching { channel?.invokeMethod("launchAction", action) }
    }

    // ---------- 刷新 ----------

    fun updateAll(ctx: Context) {
        updateTimetableWidgets(ctx)
        updateEcardWidgets(ctx)
    }

    private fun updateTimetableWidgets(ctx: Context) {
        val manager = AppWidgetManager.getInstance(ctx) ?: return
        val ids = manager.getAppWidgetIds(
            ComponentName(ctx, TimetableWidgetProvider::class.java)
        )
        for (id in ids) manager.updateAppWidget(id, buildTimetable(ctx))
    }

    private fun updateEcardWidgets(ctx: Context) {
        val manager = AppWidgetManager.getInstance(ctx) ?: return
        val ids = manager.getAppWidgetIds(ComponentName(ctx, EcardWidgetProvider::class.java))
        for (id in ids) manager.updateAppWidget(id, buildEcard(ctx))
    }

    // ---------- 渲染 ----------

    fun buildTimetable(ctx: Context): RemoteViews {
        val views = RemoteViews(ctx.packageName, R.layout.widget_timetable)
        views.setOnClickPendingIntent(R.id.widget_root, openPending(ctx, "timetable", 8802))
        val raw = prefs(ctx).getString(keyTimetable, null)
        val rowIds = arrayOf(
            Pair(R.id.row1, intArrayOf(R.id.row1_time, R.id.row1_name, R.id.row1_place)),
            Pair(R.id.row2, intArrayOf(R.id.row2_time, R.id.row2_name, R.id.row2_place)),
        )
        fun empty(message: String) {
            views.setTextViewText(R.id.widget_date, "")
            views.setViewVisibility(R.id.widget_hero, View.GONE)
            views.setViewVisibility(R.id.widget_section, View.GONE)
            for (row in rowIds) views.setViewVisibility(row.first, View.GONE)
            views.setTextViewText(R.id.widget_next, message)
        }
        if (raw.isNullOrBlank()) {
            empty("打开 App 同步一次课表")
            return views
        }
        return try {
            val obj = JSONObject(raw)
            val today = SimpleDateFormat("yyyy-MM-dd", Locale.getDefault()).format(Date())
            val stale = obj.optString("day") != today
            val courses = if (stale) JSONArray() else obj.optJSONArray("courses") ?: JSONArray()
            views.setTextViewText(
                R.id.widget_date,
                if (stale) "待刷新" else obj.optString("date")
            )
            if (courses.length() == 0) {
                empty(if (stale) "打开 App 更新今日课程" else "今天没有课")
                return views
            }

            val now = nowMinutes()
            val list = (0 until courses.length()).mapNotNull { courses.optJSONObject(it) }
            val current = list.firstOrNull {
                minutesOf(it.optString("start")) <= now && now < minutesOf(it.optString("end"))
            }
            val upcoming = list.filter { minutesOf(it.optString("start")) > now }
            val hero = current ?: upcoming.firstOrNull()
            val rest = if (hero == null) emptyList()
                else if (hero === current) upcoming
                else upcoming.drop(1)

            if (hero == null) {
                views.setViewVisibility(R.id.widget_hero, View.GONE)
            } else {
                views.setViewVisibility(R.id.widget_hero, View.VISIBLE)
                views.setTextViewText(
                    R.id.widget_status,
                    if (hero === current) "上课中"
                    else "${minutesOf(hero.optString("start")) - now} 分钟后"
                )
                views.setTextViewText(
                    R.id.widget_hero_time,
                    "${hero.optString("start")}–${hero.optString("end")}"
                )
                views.setTextViewText(R.id.widget_hero_name, hero.optString("name"))
                views.setTextViewText(R.id.widget_hero_place, hero.optString("place"))
                if (hero === current) {
                    val start = minutesOf(hero.optString("start"))
                    val end = minutesOf(hero.optString("end"))
                    val progress = (((now - start).toFloat() / (end - start).coerceAtLeast(1)) * 100)
                        .toInt().coerceIn(0, 100)
                    views.setViewVisibility(R.id.widget_progress, View.VISIBLE)
                    views.setProgressBar(R.id.widget_progress, 100, progress, false)
                } else {
                    views.setViewVisibility(R.id.widget_progress, View.GONE)
                }
            }

            if (rest.isEmpty()) {
                views.setViewVisibility(R.id.widget_section, View.GONE)
                for (row in rowIds) views.setViewVisibility(row.first, View.GONE)
            } else {
                views.setViewVisibility(R.id.widget_section, View.VISIBLE)
                for (i in rowIds.indices) {
                    val c = rest.getOrNull(i)
                    if (c == null) {
                        views.setViewVisibility(rowIds[i].first, View.GONE)
                        continue
                    }
                    views.setViewVisibility(rowIds[i].first, View.VISIBLE)
                    views.setTextViewText(rowIds[i].second[0], c.optString("start"))
                    views.setTextViewText(rowIds[i].second[1], c.optString("name"))
                    views.setTextViewText(rowIds[i].second[2], c.optString("place"))
                }
            }
            views.setTextViewText(
                R.id.widget_next,
                if (current == null && upcoming.isEmpty()) "今天的课都上完了"
                else "共 ${courses.length()} 节 · 点开查看完整课表"
            )
            views
        } catch (_: Throwable) {
            empty("数据读取失败，打开 App 刷新一次")
            views
        }
    }

    private fun nowMinutes(): Int {
        val c = java.util.Calendar.getInstance()
        return c.get(java.util.Calendar.HOUR_OF_DAY) * 60 + c.get(java.util.Calendar.MINUTE)
    }

    private fun minutesOf(hhmm: String): Int {
        val parts = hhmm.split(":")
        val h = parts.getOrNull(0)?.toIntOrNull() ?: 0
        val m = parts.getOrNull(1)?.toIntOrNull() ?: 0
        return h * 60 + m
    }

    fun buildEcard(ctx: Context): RemoteViews {
        val views = RemoteViews(ctx.packageName, R.layout.widget_ecard)
        views.setOnClickPendingIntent(R.id.ecard_root, openPending(ctx, "ecard", 8803))
        val p = prefs(ctx)
        val balance = p.getString(keyBalance, null)
        val at = p.getLong(keyBalanceAt, 0L)
        views.setTextViewText(
            R.id.ecard_balance,
            if (balance.isNullOrBlank()) "¥—" else "¥$balance"
        )
        views.setTextViewText(
            R.id.ecard_hint,
            if (balance.isNullOrBlank()) "打开 App 刷新" else "查看动态码 ›"
        )
        views.setTextViewText(
            R.id.ecard_updated,
            if (at > 0L) {
                "更新于 ${SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date(at))}"
            } else {
                ""
            }
        )
        return views
    }

    private fun openPending(ctx: Context, route: String, requestCode: Int): PendingIntent {
        val intent = Intent(ctx, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(routeExtra, route)
        }
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        return PendingIntent.getActivity(ctx, requestCode, intent, flags)
    }

    /** 从 MainActivity 的启动 Intent 里取出入口动作（取出后清掉，旋转 / 重建不重复触发）。 */
    fun routeOf(intent: Intent?): String? {
        if (intent == null) return null
        val route = intent.getStringExtra(routeExtra) ?: return null
        intent.removeExtra(routeExtra)
        return route
    }
}

/** 「今日课程」卡片。 */
class TimetableWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        for (id in ids) manager.updateAppWidget(id, HomeWidget.buildTimetable(context))
    }
}

/** 「校园卡余额」卡片。 */
class EcardWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        for (id in ids) manager.updateAppWidget(id, HomeWidget.buildEcard(context))
    }
}

/** Dart 侧 `antisit/home_widget` 通道。 */
class HomeWidgetBridge(private val activity: android.app.Activity) {
    fun register(messenger: BinaryMessenger) {
        val ch = MethodChannel(messenger, "antisit/home_widget")
        HomeWidget.channel = ch
        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                "syncTimetable" -> {
                    val args = call.arguments as? Map<*, *> ?: emptyMap<String, Any?>()
                    HomeWidget.saveTimetable(
                        activity,
                        "${args["day"] ?: ""}",
                        "${args["date"] ?: ""}",
                        toArray(args["courses"] as? List<*>),
                        (args["next"] as? Map<*, *>)?.let { toObject(it) },
                    )
                    result.success(true)
                }
                "syncEcard" -> {
                    val balance = (call.arguments as? Map<*, *>)?.get("balance")
                    HomeWidget.saveBalance(activity, balance?.toString())
                    result.success(true)
                }
                "takeLaunchAction" -> result.success(HomeWidget.takeLaunch(activity))
                else -> result.notImplemented()
            }
        }
    }

    private fun toArray(list: List<*>?): JSONArray {
        val arr = JSONArray()
        list?.forEach { item ->
            val map = item as? Map<*, *> ?: return@forEach
            arr.put(toObject(map))
        }
        return arr
    }

    private fun toObject(map: Map<*, *>): JSONObject = JSONObject().apply {
        put("name", "${map["name"] ?: ""}")
        put("place", "${map["place"] ?: ""}")
        put("start", "${map["start"] ?: ""}")
        put("end", "${map["end"] ?: ""}")
    }
}
