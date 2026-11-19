package top.anticraft.campus_service

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * 拓展文件保存（通道 `antisit/ext_files`）。
 *
 * 拓展的 `ctx.files.save` 只走系统「保存到」界面（ACTION_CREATE_DOCUMENT）：
 * 用户自己挑位置，App 不需要任何存储权限，也不会去读写其它文件。
 * 读取（`ctx.files.pick`）由 Dart 侧的 file_selector 处理，这里只管保存。
 *
 * 结果通过 MainActivity.onActivityResult 转回来：Activity 重建 / 用户取消时
 * 回 false，写入失败回 error，Dart 侧原样变成 Promise 的结果 / 异常。
 */
class ExtFilesBridge(
    private val activity: Activity,
    private val messenger: BinaryMessenger,
) {
    private data class PendingSave(
        val result: MethodChannel.Result,
        val bytes: ByteArray,
    )

    private var pending: PendingSave? = null

    fun register() {
        MethodChannel(messenger, "antisit/ext_files").setMethodCallHandler { call, result ->
            when (call.method) {
                "save" -> save(call, result)
                else -> result.notImplemented()
            }
        }
    }

    private fun save(call: MethodCall, result: MethodChannel.Result) {
        if (pending != null) {
            result.error("busy", "正在保存另一个文件，请先完成或取消", null)
            return
        }
        val bytes = call.argument<ByteArray>("bytes")
        if (bytes == null) {
            result.error("empty", "没有要保存的内容", null)
            return
        }
        if (bytes.size > MAX_BYTES) {
            result.error("too_large", "文件太大（上限 ${MAX_BYTES / 1024 / 1024} MB）", null)
            return
        }
        val name = sanitizeName(call.argument<String>("name").orEmpty())
        val mime = call.argument<String>("mime")
            ?.takeIf { it.contains("/") }
            ?: "application/octet-stream"
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = mime
            putExtra(Intent.EXTRA_TITLE, name)
        }
        pending = PendingSave(result, bytes)
        try {
            activity.startActivityForResult(intent, REQUEST_SAVE)
        } catch (e: ActivityNotFoundException) {
            pending = null
            result.error("no_picker", "系统没有文件保存界面", null)
        } catch (e: Exception) {
            pending = null
            result.error("start_failed", e.message ?: "打不开保存界面", null)
        }
    }

    /** MainActivity.onActivityResult 转发进来；返回 true = 这条结果由本通道消费。 */
    fun handleActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_SAVE) return false
        val save = pending ?: return true
        pending = null
        if (resultCode != Activity.RESULT_OK) {
            save.result.success(false)
            return true
        }
        val uri = data?.data
        if (uri == null) {
            save.result.error("no_uri", "系统没有返回保存位置", null)
            return true
        }
        try {
            activity.contentResolver.openOutputStream(uri, "wt")?.use { out ->
                out.write(save.bytes)
                out.flush()
            } ?: throw IllegalStateException("无法写入这个位置")
            save.result.success(true)
        } catch (e: Exception) {
            save.result.error("write_failed", e.message ?: "写入失败", null)
        }
        return true
    }

    /** 文件名只留最后一段，去掉路径分隔符 / 控制字符；空名给默认值。 */
    private fun sanitizeName(raw: String): String {
        val cleaned = raw
            .substringAfterLast('/')
            .substringAfterLast('\\')
            .replace(Regex("[\\x00-\\x1f:*?\"<>|]"), "_")
            .trim()
        return cleaned.ifEmpty { "文件.txt" }.take(120)
    }

    private companion object {
        const val REQUEST_SAVE = 0x5A17
        const val MAX_BYTES = 12 * 1024 * 1024
    }
}
