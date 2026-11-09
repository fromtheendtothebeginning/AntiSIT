package top.anticraft.campus_service

import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageInstaller
import android.net.Uri
import android.os.Build
import android.os.Bundle
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

    /** Dart ↔ native 的通道：安装会话的异步结果也走它回传（installResult）。 */
    private var channel: MethodChannel? = null

    /** 最近一次安装的 APK 路径：系统没给确认界面时用它走 FileProvider 兜底。 */
    private var lastApkPath: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .also { ch ->
                ch.setMethodCallHandler { call, result ->
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
                        // 应用内更新的最后一步：把下载好并校验过的 APK 交给系统安装器。
                        // path 兼容 Map {"path": ...} 与裸字符串：call.argument 遇到非 Map
                        // 会抛 ClassCastException，通道里抛出去整条安装就废了。
                        "installApk" -> result.success(
                            installApk((call.arguments as? String) ?: call.argument<String>("path").orEmpty())
                        )
                        else -> result.notImplemented()
                    }
                }
            }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // 安装状态 PendingIntent 把 MainActivity 直接拉起来时（进程可能刚重建），
        // 也要把状态处理掉；否则确认页永远出不来。
        handleInstallStatus(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleInstallStatus(intent)
    }

    private fun packageUri(): Uri = Uri.fromParts("package", packageName, null)

    /**
     * 处理 PackageInstaller 送回来的安装状态。
     *
     * **关键**：普通 App 提交安装会话后，系统不会自己弹安装确认页——它会回一个
     * [PackageInstaller.STATUS_PENDING_USER_ACTION]，要求状态接收方自己启动
     * [Intent.EXTRA_INTENT] 里的确认 Activity。以前这里只 commit 不接状态，
     * 所以安装界面永远不出现（ColorOS 上表现为「点安装没反应」）。
     *
     * 安装结果统一回传 Dart（installResult）：pending / success / failed。
     */
    private fun handleInstallStatus(intent: Intent?) {
        if (intent?.action != ACTION_INSTALL_STATUS) return
        if (!intent.hasExtra(PackageInstaller.EXTRA_STATUS)) return

        val status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)
        val message = intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE)
        val confirm = if (status == PackageInstaller.STATUS_PENDING_USER_ACTION)
            confirmIntent(intent) else null

        // 消费掉状态：Activity 重建 / 旋转时不要把同一次安装结果再报一遍
        intent.removeExtra(PackageInstaller.EXTRA_STATUS)
        intent.removeExtra(PackageInstaller.EXTRA_STATUS_MESSAGE)
        intent.removeExtra(Intent.EXTRA_INTENT)

        when (status) {
            PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                val shown = confirm != null && runCatching { startActivity(confirm) }.isSuccess
                // 极少数 ROM 的安装器没有确认 Activity / 确认页被后台启动限制挡住：
                // 退回 FileProvider 的安装意图，至少别让用户卡在原地。
                val fallback = !shown &&
                    (lastApkPath?.let { startFirstInstallerIntent(it) } ?: false)
                if (shown || fallback) {
                    emitInstallResult("pending", status, null)
                } else {
                    emitInstallResult(
                        "failed",
                        status,
                        if (confirm == null) "系统没有提供安装确认界面" else "无法打开安装确认界面"
                    )
                }
            }
            PackageInstaller.STATUS_SUCCESS -> emitInstallResult("success", status, null)
            else -> emitInstallResult("failed", status, message)
        }
    }

    /** API 33+ 必须用带 Class 的 getParcelableExtra，低版本走旧接口。 */
    private fun confirmIntent(intent: Intent): Intent? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra(Intent.EXTRA_INTENT)
        }

    private fun emitInstallResult(status: String, code: Int, message: String?) {
        runCatching {
            channel?.invokeMethod(
                "installResult",
                mapOf("status" to status, "code" to code, "message" to message)
            )
        }
    }

    /** 确认页拉不起来时的兜底：用 FileProvider 把 APK 交给系统安装器。 */
    private fun startFirstInstallerIntent(path: String): Boolean {
        val file = File(path)
        if (!file.exists() || file.length() == 0L) return false
        val uri = runCatching {
            FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
        }.getOrNull() ?: return false
        for (intent in installerIntents(uri)) {
            if (runCatching { startActivity(intent) }.isSuccess) return true
        }
        return false
    }

    private fun installerIntents(uri: Uri): List<Intent> = listOf(
        Intent(Intent.ACTION_INSTALL_PACKAGE).apply {
            setData(uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        },
        Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        },
    )

    /** 把下载好的 APK 交给系统安装。按兼容性依次尝试：
     *  ① PackageInstaller 会话（API 21+，系统安装服务直装，不走 intent 解析，
     *     各 ROM 拦截差异最小）；② ACTION_INSTALL_PACKAGE；③ ACTION_VIEW。
     *  返回 true = 已拉起；"settings" = Android 8+ 还没授予「安装未知应用」，已跳到
     *  授权页（授权回来 Dart 侧再点一次「安装」）；"missing" / "error: 原因" =
     *  文件不在 / 拉起失败（带上真实原因，便于定位各 ROM 的差异）。 */
    private fun installApk(path: String): Any {
        lastApkPath = path
        val file = File(path)
        if (!file.exists() || file.length() == 0L) return "missing"
        // 个别 ROM 查询授权状态本身也会抛：别让它吞掉后面的安装尝试
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                !packageManager.canRequestPackageInstalls()
            ) {
                open(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, packageUri())
                return "settings"
            }
        } catch (_: Exception) {
        }
        var last: Exception? = null

        // ① PackageInstaller 会话：APK 流式写进系统安装会话，commit 后由系统
        //    弹安装确认。不经过 intent 解析，ColorOS / MIUI 上的拦截差异最小。
        try {
            val installer = packageManager.packageInstaller
            val session = installer.openSession(installer.createSession(
                PackageInstaller.SessionParams(
                    PackageInstaller.SessionParams.MODE_FULL_INSTALL)))
            try {
                session.openWrite("AntiSIT", 0, file.length()).use { out ->
                    file.inputStream().use { it.copyTo(out) }
                    session.fsync(out)
                }
                // Android 12+ 的 commit 必须带可变的 PendingIntent（系统往里写安装结果）；
                // 状态回来后在 handleInstallStatus 里拉起 EXTRA_INTENT 的确认页。
                val intent = Intent(this, MainActivity::class.java).setAction(ACTION_INSTALL_STATUS)
                val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S)
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
                else PendingIntent.FLAG_UPDATE_CURRENT
                session.commit(PendingIntent.getActivity(this, 0, intent, flags).intentSender)
                return true
            } finally {
                session.close()
            }
        } catch (e: Exception) {
            last = e
        }

        // ② / ③ intent 兜底：经 FileProvider 只读共享给系统安装器。
        val uri = try {
            FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
        } catch (e: Exception) {
            return "error: FileProvider(${e.message})"
        }
        for (intent in installerIntents(uri)) {
            try {
                startActivity(intent)
                return true
            } catch (e: Exception) {
                last = e
            }
        }
        return "error: ${last?.message ?: "未知原因"}"
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

    private companion object {
        /** 安装状态 PendingIntent 的动作：用来区分普通启动 / 深链。 */
        const val ACTION_INSTALL_STATUS = "top.anticraft.campus_service.INSTALL_STATUS"
    }
}
