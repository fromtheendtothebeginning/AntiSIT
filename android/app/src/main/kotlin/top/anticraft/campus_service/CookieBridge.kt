package top.anticraft.campus_service

import android.net.Uri
import android.webkit.CookieManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * 通用登录页的 Cookie 读取口（通道 `antisit/cookies`）。
 *
 * 拓展通过 `ctx.login.open({url, cookieUrls})` 打开登录页，登录完成后只能拿到
 * **它声明的那些域**的 Cookie；App 不解析、不保存账号密码。是否允许打开由用户在
 * 运行时授权弹窗里决定。
 *
 * `remove` 是「退出账号」用的：登录页与所有 WebView 共用同一个 CookieStore，
 * 只删拓展自己的加密凭据而不清这里，下次打开登录页仍是已登录状态
 * （用户看到的就是「退出了又自动登录」）。
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
                // 退出登录：删掉这些域的 Cookie。返回 true 表示已经确认清干净。
                "remove" -> result.success(removeCookies(call.argument<List<String>>("urls") ?: emptyList()))
                "clear" -> {
                    CookieManager.getInstance().removeAllCookies(null)
                    CookieManager.getInstance().flush()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    /**
     * 域 Cookie 必须带 `Domain=` 才能删掉：学习通的登录态大多是 `.chaoxing.com`
     * 这种**父域 Cookie**，用 `name=; Max-Age=0` 只会写一条 host-only 的空 Cookie，
     * 父域那条纹丝不动——这是「清了还是已登录」的根因。
     *
     * 所以这里对每个 URL 枚举它可能对应的父域与常见 Path，逐个下发删除；
     * 最后再读一遍，确认真的没剩东西（返回 false 让拓展如实提示用户）。
     */
    private fun removeCookies(urls: List<String>): Boolean {
        val manager = CookieManager.getInstance()
        val paths = listOf("/", "/mooc2", "/mooc2-ans", "/mycourse", "/work", "/visit", "/exam")
        for (url in urls) {
            val host = Uri.parse(url).host ?: continue
            // 先按几个常见 Path 读一遍，把这条站上出现过的 Cookie 名收集齐
            // （getCookie 受 Path 影响，只读根路径会漏掉 /mooc2 下的那些）
            val names = LinkedHashSet<String>()
            for (path in paths) {
                val probe = "https://$host$path"
                val raw = manager.getCookie(probe) ?: continue
                for (part in raw.split(";")) {
                    val name = part.substringBefore("=").trim()
                    if (name.isNotEmpty()) names.add(name)
                }
            }
            if (names.isEmpty()) continue
            val domains = domainCandidates(host)
            for (name in names) {
                // host-only（不带 Domain）也要清一份
                for (path in paths) {
                    manager.setCookie(url, "$name=; Max-Age=0; Expires=Thu, 01 Jan 1970 00:00:00 GMT; Path=$path")
                }
                for (domain in domains) {
                    for (path in paths) {
                        manager.setCookie(
                            url,
                            "$name=; Max-Age=0; Expires=Thu, 01 Jan 1970 00:00:00 GMT; Path=$path; Domain=$domain"
                        )
                    }
                }
            }
        }
        manager.flush()
        // 复核：还读得到任何 Cookie 就说明没清干净
        for (url in urls) {
            val host = Uri.parse(url).host ?: continue
            for (path in paths) {
                val left = manager.getCookie("https://$host$path")
                if (!left.isNullOrBlank()) return false
            }
        }
        return true
    }

    /**
     * URL 主机名对应的可删域：从最长到最短，至少保留两级
     * （`mooc1-api.chaoxing.com` → 它自己、`chaoxing.com`；`chaoxing.com` → 它自己）。
     */
    private fun domainCandidates(host: String): List<String> {
        val parts = host.split('.').filter { it.isNotEmpty() }
        if (parts.size < 2) return listOf(host)
        val out = mutableListOf<String>()
        for (i in 0..parts.size - 2) {
            out.add(parts.subList(i, parts.size).joinToString("."))
        }
        return out
    }
}
