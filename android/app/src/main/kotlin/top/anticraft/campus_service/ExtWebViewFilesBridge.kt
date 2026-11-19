package top.anticraft.campus_service

import android.app.Activity
import android.app.DownloadManager
import android.content.Context
import android.net.Uri
import android.os.Environment
import android.webkit.CookieManager
import android.webkit.DownloadListener
import android.webkit.URLUtil
import android.widget.Toast
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.webviewflutter.WebViewFlutterAndroidExternalApi
import java.io.File

/**
 * 网页下载兼容（通道 `antisit/webview_files`）。
 *
 * webview_flutter 自己挂的 DownloadListener 只把 URL 当成一次导航，二进制文件
 * 在 WebView 里打不开。这里用官方外部 API 拿到原生 WebView，换成系统
 * DownloadManager：通知栏显示进度、下载完可以直接点开，也能带上 WebView 的
 * Cookie / User-Agent，登录后才给的下载链接能正常用。
 *
 * 只处理 http(s)。blob: / data: 这类页面内生成的下载交给拓展页的
 * `ctx.files.save`（见 Cordis 运行时的下载钩子），DownloadManager 不接。
 */
class ExtWebViewFilesBridge(
    private val activity: Activity,
    private val engine: FlutterEngine,
    private val messenger: BinaryMessenger,
) {
    fun register() {
        MethodChannel(messenger, "antisit/webview_files").setMethodCallHandler { call, result ->
            when (call.method) {
                "installDownloadListener" -> {
                    val id = call.argument<Number>("id")?.toLong()
                    if (id == null) {
                        result.error("bad_id", "缺少 WebView id", null)
                        return@setMethodCallHandler
                    }
                    val webView = WebViewFlutterAndroidExternalApi.getWebView(engine, id)
                    if (webView == null) {
                        // WebView 还没创建好：Dart 侧会在页面加载完成后再试一次
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    webView.setDownloadListener(DownloadListener { url, userAgent, contentDisposition, mimeType, _ ->
                        enqueue(url, userAgent, contentDisposition, mimeType)
                    })
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun enqueue(url: String?, userAgent: String?, contentDisposition: String?, mimeType: String?) {
        if (url.isNullOrBlank() || !(url.startsWith("http://") || url.startsWith("https://"))) return
        val name = sanitize(
            URLUtil.guessFileName(url, contentDisposition, mimeType)
        ).ifEmpty { "download" }
        val manager = activity.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager

        fun request(): DownloadManager.Request =
            DownloadManager.Request(Uri.parse(url)).apply {
                mimeType?.takeIf { it.contains("/") }?.let { setMimeType(it) }
                setTitle(name)
                setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
                setAllowedOverMetered(true)
                setAllowedOverRoaming(true)
                userAgent?.takeIf { it.isNotBlank() }?.let { addRequestHeader("User-Agent", it) }
                CookieManager.getInstance().getCookie(url)?.takeIf { it.isNotBlank() }?.let {
                    addRequestHeader("Cookie", it)
                }
            }

        try {
            manager.enqueue(
                request().apply {
                    setDestinationInExternalPublicDir(
                        Environment.DIRECTORY_DOWNLOADS,
                        uniqueName(name),
                    )
                }
            )
            toast("开始下载：$name")
        } catch (e: Exception) {
            // 个别 ROM 不允许直接写公共下载目录：退回 App 自己的外部目录，
            // 通知栏仍然能点开文件。
            try {
                manager.enqueue(
                    request().apply {
                        setDestinationInExternalFilesDir(
                            activity,
                            Environment.DIRECTORY_DOWNLOADS,
                            uniqueName(name),
                        )
                    }
                )
                toast("开始下载：$name")
            } catch (e2: Exception) {
                toast("下载失败：${e2.message ?: e2.javaClass.simpleName}")
            }
        }
    }

    /** 公共下载目录里重名就加（1）（2），避免 DownloadManager 因目标已存在直接失败。 */
    private fun uniqueName(name: String): String {
        val dir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
        if (!File(dir, name).exists()) return name
        val dot = name.lastIndexOf('.')
        val base = if (dot > 0) name.substring(0, dot) else name
        val ext = if (dot > 0) name.substring(dot) else ""
        for (i in 1..99) {
            val candidate = "$base ($i)$ext"
            if (!File(dir, candidate).exists()) return candidate
        }
        return "$base-${System.currentTimeMillis()}$ext"
    }

    private fun sanitize(raw: String): String = raw
        .substringAfterLast('/')
        .substringAfterLast('\\')
        .replace(Regex("[\\x00-\\x1f:*?\"<>|]"), "_")
        .trim()
        .take(120)

    private fun toast(text: String) {
        Toast.makeText(activity, text, Toast.LENGTH_SHORT).show()
    }
}
