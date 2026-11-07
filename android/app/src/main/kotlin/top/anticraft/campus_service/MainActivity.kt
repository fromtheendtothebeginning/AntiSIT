package top.anticraft.campus_service

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * 「上课提醒」与「应用内更新」的系统级入口。
 *
 * 提醒能不能弹出来，除了 App 自己排期，还取决于三件系统级的事：通知权限、精确闹钟、
 * 后台不被省电策略掐死。前两件通知插件自己能申请，第三件（以及「通知被关了」之后的补救）
 * 系统只给设置页、没有 API 能直接改——所以在这儿开一个极小的 MethodChannel：
 * 读状态 + 跳设置页 + 把下载好的 APK 交给系统安装器，不碰业务逻辑。
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
                    // 应用内更新的最后一步：把下载好并校验过的 APK 交给系统安装器
                    "installApk" -> result.success(installApk(call.argument<String>("path").orEmpty()))
                    else -> result.notImplemented()
                }
            }
    }

    private fun packageUri(): Uri = Uri.fromParts("package", packageName, null)

    /** 把 APK 经 FileProvider 只读共享给系统安装器（路径来自 UpdateDownloader）。
     *  返回 true = 已拉起；"settings" = Android 8+ 还没授予「安装未知应用」，已跳到
     *  授权页（授权回来 Dart 侧再点一次「安装」）；"missing" / "error" = 文件不在 /
     *  拉起失败，Dart 侧提示退回浏览器下载。 */
    private fun installApk(path: String): Any {
        val file = File(path)
        if (!file.exists()) return "missing"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !packageManager.canRequestPackageInstalls()
        ) {
            open(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, packageUri())
            return "settings"
        }
        val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
        return try {
            startActivity(
                Intent(Intent.ACTION_VIEW).apply {
                    setDataAndType(uri, "application/vnd.android.package-archive")
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
                }
            )
            true
        } catch (_: Exception) {
            "error"
        }
    }

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
