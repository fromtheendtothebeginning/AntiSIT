package top.anticraft.campus_service

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * 「上课提醒」的引导入口。
 *
 * 提醒能不能弹出来，除了 App 自己排期，还取决于三件系统级的事：通知权限、精确闹钟、
 * 后台不被省电策略掐死。前两件通知插件自己能申请，第三件（以及「通知被关了」之后的补救）
 * 系统只给设置页、没有 API 能直接改——所以在这儿开一个极小的 MethodChannel：
 * 读一个状态 + 跳几个设置页，不碰业务逻辑。
 */
class MainActivity : FlutterActivity() {
    private val channelName = "antisit/system"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // 只读查询，不需要任何权限
                    "isIgnoringBatteryOptimizations" -> {
                        val power = getSystemService(POWER_SERVICE) as PowerManager
                        result.success(power.isIgnoringBatteryOptimizations(packageName))
                    }
                    // 系统「电池优化」列表页：不申请 REQUEST_IGNORE_BATTERY_OPTIMIZATIONS 权限，
                    // 也就没有上架政策风险；用户在里面把 AntiSIT 选成「不优化 / 无限制」。
                    "openBatteryOptimizationSettings" ->
                        result.success(open(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
                    // 应用信息页：各家 ROM 的省电策略 / 自启动开关都在这里，兜底用
                    "openAppInfoSettings" -> result.success(
                        open(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, packageUri())
                    )
                    // 通知设置页（Android 8+ 有本应用专属页；没有就退到应用信息页）
                    "openNotificationSettings" -> {
                        val shown = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                            open(Settings.ACTION_APP_NOTIFICATION_SETTINGS, null, packageName)
                        result.success(
                            shown || open(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, packageUri())
                        )
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun packageUri(): Uri = Uri.fromParts("package", packageName, null)

    /** 跳设置页；部分 ROM 没有对应页面，返回 false 让 Dart 侧走兜底。 */
    private fun open(action: String, data: Uri? = null, appPackage: String? = null): Boolean =
        try {
            startActivity(
                Intent(action).apply {
                    data?.let { this.data = it }
                    appPackage?.let { putExtra(Settings.EXTRA_APP_PACKAGE, it) }
                }
            )
            true
        } catch (_: Exception) {
            false
        }
}
