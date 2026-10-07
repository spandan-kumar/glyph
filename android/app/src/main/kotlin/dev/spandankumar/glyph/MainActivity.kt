package dev.spandankumar.glyph

import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var alerts: NotificationAlertsBridge? = null
    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        alerts?.dispose()
        alerts = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
}
