package top.anticraft.campus_service

import android.content.Context
import android.content.Intent
import android.os.Build
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/** `ctx.background.keepAlive` 的原生入口（通道 `antisit/ext_background`）。 */
class ExtBackgroundBridge(
    private val context: Context,
    private val messenger: BinaryMessenger,
) {
    fun register() {
        MethodChannel(messenger, "antisit/ext_background").setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    val title = call.argument<String>("title")?.takeIf { it.isNotBlank() }
                        ?: "拓展后台运行"
                    val text = call.argument<String>("text")?.takeIf { it.isNotBlank() }
                        ?: "点按回到 App"
                    val intent = Intent(context, ExtBackgroundService::class.java).apply {
                        putExtra(ExtBackgroundService.EXTRA_TITLE, title)
                        putExtra(ExtBackgroundService.EXTRA_TEXT, text)
                    }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        context.startForegroundService(intent)
                    } else {
                        context.startService(intent)
                    }
                    result.success(true)
                }
                "stop" -> {
                    context.stopService(Intent(context, ExtBackgroundService::class.java))
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }
}
