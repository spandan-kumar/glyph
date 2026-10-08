package dev.spandankumar.glyph

import android.content.Intent
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var alerts: NotificationAlertsBridge? = null
    private var power: StreamingPower? = null
    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        power?.dispose()
        power = null
        alerts?.dispose()
        alerts = null
        // The Dart isolate (and so every retainer/streamer) dies with the engine;
        // the foreground notification must not outlive it.
        try {
            applicationContext.stopService(
                Intent().setClassName(applicationContext.packageName, FOREGROUND_SERVICE))
        } catch (_: Exception) {}
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        power = StreamingPower(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
        NowPlayingBridge(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
        alerts = NotificationAlertsBridge(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
        // Phone model and Android version for feedback reports (lib/app/community.dart);
        // a whole device-info plugin would be overkill for two strings.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "glyph/platform")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "phone" -> result.success(
                        mapOf(
                            "model" to "${Build.MANUFACTURER} ${Build.MODEL}",
                            "android" to Build.VERSION.RELEASE,
                            "sdk" to Build.VERSION.SDK_INT,
                        )
                    )
                    else -> result.notImplemented()
                }
            }
    }

    private companion object {
        const val FOREGROUND_SERVICE = "com.pravera.flutter_foreground_task.service.ForegroundService"
    }
}
