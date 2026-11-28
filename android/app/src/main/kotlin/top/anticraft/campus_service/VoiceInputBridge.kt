package top.anticraft.campus_service

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * 语音输入：系统 `SpeechRecognizer` 的极薄封装（通道 `antisit/voice`）。
 *
 * 只做一件事——把用户说的话识别成文字回填输入框。录音不落盘、不上传：
 * 识别由系统服务完成（多数 ROM 在本机跑，是否联网由系统的识别服务自己决定，
 * 这一点在设置页文案里写清楚）。
 *
 * 权限：RECORD_AUDIO 属于运行时权限，第一次点麦克风时向用户申请；
 * 拒绝后返回 false，网页侧提示去设置里开。
 */
class VoiceInputBridge(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "antisit/voice")
    private val main = Handler(Looper.getMainLooper())
    private var recognizer: SpeechRecognizer? = null

    /** 正在等权限回调的那次 start：授权后自己接着开识别。 */
    private var pendingStart = false

    fun register() {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> result.success(start())
                "stop" -> {
                    runCatching { recognizer?.stopListening() }
                    result.success(true)
                }
                "cancel" -> {
                    cancel()
                    result.success(true)
                }
                "available" -> result.success(SpeechRecognizer.isRecognitionAvailable(activity))
                else -> result.notImplemented()
            }
        }
    }

    private fun hasMicPermission(): Boolean =
        ContextCompat.checkSelfPermission(activity, Manifest.permission.RECORD_AUDIO) ==
            PackageManager.PERMISSION_GRANTED

    private fun start(): Boolean {
        if (!SpeechRecognizer.isRecognitionAvailable(activity)) {
            emitError("这台设备没有可用的语音识别服务")
            return false
        }
        if (!hasMicPermission()) {
            pendingStart = true
            ActivityCompat.requestPermissions(
                activity,
                arrayOf(Manifest.permission.RECORD_AUDIO),
                REQ_MIC,
            )
            return false
        }
        return startRecognizer()
    }

    private fun startRecognizer(): Boolean {
        val rec = recognizer ?: SpeechRecognizer.createSpeechRecognizer(activity).also {
            it.setRecognitionListener(listener)
            recognizer = it
        }
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(
                RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                RecognizerIntent.LANGUAGE_MODEL_FREE_FORM,
            )
            // 中文优先：系统识别器按这个提示挑语言包
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, "zh-CN")
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
        }
        return runCatching {
            rec.startListening(intent)
            true
        }.getOrElse { e ->
            emitError(e.message ?: "语音识别启动失败")
            false
        }
    }

    private fun cancel() {
        pendingStart = false
        runCatching { recognizer?.cancel() }
    }

    /** 权限回调：用户点了允许就接着开识别，拒绝就明确回报一句。 */
    fun onRequestPermissionsResult(requestCode: Int, granted: Boolean) {
        if (requestCode != REQ_MIC) return
        val wants = pendingStart
        // 守住时序：Activity 的 requestPermissions 可能和 start 不在同一帧，
        // 用 pendingStart 记住这次是不是为了开识别才弹的权限。
        pendingStart = false
        if (!wants) return
        if (granted) {
            startRecognizer()
        } else {
            emitError("没有麦克风权限：请在系统设置里允许 AntiSIT 录音")
        }
    }

    private val listener = object : RecognitionListener {
        override fun onReadyForSpeech(params: Bundle?) = Unit
        override fun onBeginningOfSpeech() = Unit
        override fun onRmsChanged(rmsdB: Float) = Unit
        override fun onBufferReceived(buffer: ByteArray?) = Unit
        override fun onEndOfSpeech() = Unit
        override fun onEvent(eventType: Int, params: Bundle?) = Unit
        override fun onPartialResults(partialResults: Bundle?) {
            emitText(firstResult(partialResults), false)
        }

        override fun onResults(results: Bundle?) {
            emitText(firstResult(results), true)
            emitEnd()
        }

        override fun onError(error: Int) {
            // 用户主动取消 / 没说话不算错误，别弹红字
            val message = when (error) {
                SpeechRecognizer.ERROR_NO_MATCH,
                SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> "没听到声音";
                SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> "没有麦克风权限";
                SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> "识别服务忙，等会儿再试";
                SpeechRecognizer.ERROR_CLIENT -> "识别被取消";
                else -> "识别出错（$error）";
            }
            emitError(message)
            emitEnd()
        }
    }

    private fun firstResult(bundle: Bundle?): String {
        val list = bundle?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
        return list?.firstOrNull()?.trim().orEmpty()
    }

    private fun emitText(text: String, isFinal: Boolean) {
        if (text.isEmpty() && !isFinal) return
        post(
            "result",
            mapOf("text" to text, "isFinal" to isFinal),
        )
    }

    private fun emitError(message: String) {
        post("error", message)
    }

    private fun emitEnd() {
        post("end", null)
    }

    private fun post(method: String, args: Any?) {
        main.post { runCatching { channel.invokeMethod(method, args) } }
    }

    companion object {
        const val REQ_MIC = 4451
    }
}
