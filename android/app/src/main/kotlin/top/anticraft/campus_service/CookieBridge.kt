package top.anticraft.campus_service

import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.webkit.CookieManager
import android.webkit.WebStorage
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * 通用登录页的 Cookie 读取口（通道 `antisit/cookies`）。
 *
 * 拓展通过 `ctx.login.open({url, cookieUrls})` 打开登录页，登录完成后只能拿到
 * **它声明的那些域**的 Cookie；App 不解析、不保存账号密码。是否允许打开由用户在
 * 运行时授权弹窗里决定。
 *
 * `remove` 是「退出账号」用的。登录页与所有 WebView 共用同一个浏览数据目录，
 * 只删拓展自己的加密凭据而不清这里，下次打开登录页仍是已登录状态
 * （用户看到的就是「退出了又自动登录」）。
 */
class CookieBridge(private val messenger: BinaryMessenger) {
    private val main = Handler(Looper.getMainLooper())

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
                // 退出登录。**放后台线程**：内部要等 removeAllCookies 的回调，
                // 而 MethodChannel 的处理函数跑在主线程上，在这儿等会卡住界面。
                "remove" -> {
                    val urls = call.argument<List<String>>("urls") ?: emptyList()
                    runOffThread(result) { removeLogin(urls) }
                }
                "clear" -> runOffThread(result) {
                    nukeCookies()
                    wipeWebStorage()
                    mapOf("ok" to true, "scoped" to false)
                }
                else -> result.notImplemented()
            }
        }
    }

    /** 后台线程干活，结果回主线程发（MethodChannel 的 Result 只能在主线程用）。 */
    private fun runOffThread(result: MethodChannel.Result, task: () -> Any?) {
        Thread {
            val value = try {
                task()
            } catch (e: Exception) {
                main.post { result.error("cookie_bridge", e.message ?: e.javaClass.simpleName, null) }
                return@Thread
            }
            main.post { result.success(value) }
        }.start()
    }

    /**
     * 退出登录，返回 `{ok, scoped}`：
     * * `ok`：清完后确实读不到 Cookie 了；
     * * `scoped`：是否只清了声明的那些域（false = 兜底清了整个浏览数据目录）。
     *
     * 做三件事，缺一不可：
     * 1. 按域 + 路径删 Cookie（保住别的 WebView 的登录态）；
     * 2. 清 **WebStorage**——学习通这类站点会把「下次自动登录」也塞进
     *    localStorage；只清 Cookie 时页面看着是登出的，一进首页又自己跳回已登录；
     * 3. 复核，还读得到就 `removeAllCookies` 兜底。
     */
    private fun removeLogin(urls: List<String>): Map<String, Any> {
        val manager = CookieManager.getInstance()
        scopedRemoveCookies(manager, urls)
        wipeWebStorage()
        if (isClean(manager, urls)) return mapOf("ok" to true, "scoped" to true)

        nukeCookies()
        return mapOf("ok" to isClean(manager, urls), "scoped" to false)
    }

    /**
     * 域 Cookie 必须带 `Domain=` 才能删掉：学习通的登录态大多是 `.chaoxing.com`
     * 这种**父域 Cookie**，用 `name=; Max-Age=0` 只写一条 host-only 空 Cookie，
     * 父域那条纹丝不动——这是「清了还是已登录」的第一个根因。
     *
     * 第二个根因是 **Path**：Chromium 只接受「请求路径能匹配 Path 属性」的
     * Set-Cookie，拿 `https://host/` 去删 `Path=/mooc2` 的 Cookie 会被直接丢掉。
     * 所以每条删除都要用**与 Path 对应的 URL**下发。
     */
    private fun scopedRemoveCookies(manager: CookieManager, urls: List<String>) {
        for (url in urls) {
            val host = Uri.parse(url).host ?: continue
            val names = LinkedHashSet<String>()
            for (path in PROBE_PATHS) {
                val raw = manager.getCookie("https://$host$path") ?: continue
                for (part in raw.split(";")) {
                    val name = part.substringBefore("=").trim()
                    if (name.isNotEmpty()) names.add(name)
                }
            }
            if (names.isEmpty()) continue
            for (name in names) {
                for (path in PROBE_PATHS) {
                    // 请求 URL 的路径必须与要删的 Path 一致，否则 Chromium 拒收
                    val target = "https://$host$path"
                    // host-only（不带 Domain）也清一份
                    manager.setCookie(target, expire(name, path, null))
                    for (domain in domainCandidates(host)) {
                        manager.setCookie(target, expire(name, path, domain))
                    }
                }
            }
        }
        manager.flush()
        // setCookie 是异步排队的：立刻回读可能还是旧值，给它几轮时间收敛
        settle()
    }

    private fun expire(name: String, path: String, domain: String?): String {
        val base = "$name=; Max-Age=0; Expires=Thu, 01 Jan 1970 00:00:00 GMT; Path=$path"
        return if (domain == null) base else "$base; Domain=$domain"
    }

    /** 兜底：清空整个 CookieStore（别的 WebView 的登录态也会没了）。 */
    private fun nukeCookies() {
        val manager = CookieManager.getInstance()
        val latch = CountDownLatch(1)
        manager.removeAllCookies { latch.countDown() }
        latch.await(3, TimeUnit.SECONDS)
        manager.flush()
        settle()
    }

    /**
     * 清掉 WebStorage（localStorage / IndexedDB / WebSQL）。
     *
     * 学习通登录成功后会往 localStorage 里写「下次自动登录」的标记：只清 Cookie
     * 的话，用户点「重新登录」看到的是干净登录页，但页面里的脚本凭 localStorage
     * 又把他送回已登录状态——现象就是「登录页显示一会儿，然后自动登录了」。
     */
    private fun wipeWebStorage() {
        try {
            WebStorage.getInstance().deleteAllData()
        } catch (_: Exception) {
            // 极少数 ROM 上 WebStorage 未初始化会抛：不该因此让退出失败
        }
        settle()
    }

    /** 给异步的 setCookie / deleteAllData 一点收敛时间：读得到就不算完。 */
    private fun settle() {
        repeat(4) { Thread.sleep(120) }
    }

    /** 声明的这些域上还读得到任何 Cookie 吗。 */
    private fun isClean(manager: CookieManager, urls: List<String>): Boolean {
        for (url in urls) {
            val host = Uri.parse(url).host ?: continue
            for (path in PROBE_PATHS) {
                val left = manager.getCookie("https://$host$path")
                if (!left.isNullOrBlank()) return false
            }
        }
        return true
    }

    /**
     * URL 主机名对应的可删域：从最长到最短，至少保留两级
     * （`mooc1-api.chaoxing.com` → 它自己、`chaoxing.com`；`chaoxing.com` → 它自己）。
     * 带前导点的写法也来一份：有的站点按 `.chaoxing.com` 下发。
     */
    private fun domainCandidates(host: String): List<String> {
        val parts = host.split('.').filter { it.isNotEmpty() }
        if (parts.size < 2) return listOf(host)
        val out = mutableListOf<String>()
        for (i in 0..parts.size - 2) {
            val domain = parts.subList(i, parts.size).joinToString(".")
            out.add(domain)
            out.add(".$domain")
        }
        return out
    }

    private companion object {
        /** 探测 / 删除时穷举的路径：学习通的登录态会散落在这几个子路径下。 */
        val PROBE_PATHS = listOf(
            "/", "/mooc2", "/mooc2-ans", "/mycourse", "/work", "/visit", "/exam", "/passport",
        )
    }
}
