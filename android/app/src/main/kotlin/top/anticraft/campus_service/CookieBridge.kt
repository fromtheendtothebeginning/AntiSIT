package top.anticraft.campus_service

import android.webkit.CookieManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * 通用登录页的 Cookie 读取口（通道 `antisit/cookies`）。
 *
 * 拓展通过 `ctx.login.open({url, cookieUrls})` 打开登录页，登录完成后只能拿到
 * **它声明的那些域**的 Cookie；App 不解析、不保存账号密码。是否允许打开由用户在
 * 运行时授权弹窗里决定。
 */
class CookieBridge(private val messenger: BinaryMessenger) {
    fun register() {
        MethodChannel(messenger, "antisit/cookies").setMethodCallHandler { call, result ->
            when (call.method) {
                "get" -> {
                    val urls = call.argument<List<String>>("urls") ?: emptyList()
                    val manager = CookieManager.getInstance()
                    val out = HashMap<String, String>()
                    for (url in urls) {
                        out[url] = manager.getCookie(url) ?: ""
                    }
                    result.success(out)
                }
                "clear" -> {
                    CookieManager.getInstance().removeAllCookies(null)
                    CookieManager.getInstance().flush()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }
}
