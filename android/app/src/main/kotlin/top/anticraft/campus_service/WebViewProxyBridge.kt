package top.anticraft.campus_service

import android.app.Activity
import androidx.core.content.ContextCompat
import androidx.webkit.ProxyConfig
import androidx.webkit.ProxyController
import androidx.webkit.WebViewFeature
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * WebView 进程级代理（通道 `antisit/webview`）。
 *
 * 服务器模式的评教页要在内嵌 WebView 里打开教务系统——手机在外网到不了校园内网，
 * 只能把 WebView 的流量指向该账号校园隧道容器的 HTTP 代理（WebView 自己不会走系统
 * 代理，也没有 Dart 侧 API 可设）。这里只做「设 / 清」两件事，代理地址由 Dart 侧
 * 从服务器状态里取。
 *
 * 注意：ProxyController 是进程级的，调用方用完必须清掉（Dart 侧 WebViewHost.dispose
 * 会发 url=null），否则其它 WebView 也会继续走校园隧道。
 */
class WebViewProxyBridge(
    private val activity: Activity,
    private val messenger: BinaryMessenger,
) {
    fun register() {
        MethodChannel(messenger, "antisit/webview").setMethodCallHandler { call, result ->
            when (call.method) {
                "setProxy" -> {
                    if (!WebViewFeature.isFeatureSupported(WebViewFeature.PROXY_OVERRIDE)) {
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    val url = call.argument<String>("url")
                    val controller = ProxyController.getInstance()
                    val executor = ContextCompat.getMainExecutor(activity)
                    if (url.isNullOrBlank()) {
                        controller.clearProxyOverride(executor) { result.success(true) }
                    } else {
                        val config = ProxyConfig.Builder().addProxyRule(url).build()
                        controller.setProxyOverride(config, executor) { result.success(true) }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
