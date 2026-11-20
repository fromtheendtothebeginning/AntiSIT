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
                // 退出登录：只删这些域的 Cookie。WebView 与登录页共用同一个
                // CookieStore，不清掉的话下次打登录页仍是已登录状态。
                "remove" -> {
                    val urls = call.argument<List<String>>("urls") ?: emptyList()
                    val manager = CookieManager.getInstance()
                    for (url in urls) {
                        val cookies = manager.getCookie(url) ?: continue
                        for (part in cookies.split(";")) {
                            val name = part.substringBefore("=").trim()
                            if (name.isEmpty()) continue
                            manager.setCookie(url, "$name=; Max-Age=0; Path=/")
                            // 部分站点 Cookie 只在子路径下：顺手把常见路径也清一遍
                            manager.setCookie(url, "$name=; Max-Age=0; Path=/mooc2")
                        }
                    }
                    manager.flush()
                    result.success(true)
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
