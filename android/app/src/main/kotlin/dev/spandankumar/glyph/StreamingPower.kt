package dev.spandankumar.glyph

import android.content.Context
import android.net.wifi.WifiManager
import android.os.PowerManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/** The monitor may stay foreground while idle; only actual work needs locks. */
class StreamingPower(context: Context, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "glyph/power")
    private val cpu = (context.getSystemService(Context.POWER_SERVICE) as PowerManager)
        .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "Glyph:streaming")
        .apply { setReferenceCounted(false) }
    @Suppress("DEPRECATION")
    private val wifi = (context.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager)
        .createWifiLock(WifiManager.WIFI_MODE_FULL_HIGH_PERF, "Glyph:streaming")
        .apply { setReferenceCounted(false) }

    init {
        channel.setMethodCallHandler { call, result ->
            if (call.method != "active") {
                result.notImplemented()
            } else {
                try {
                    if (call.arguments == true) {
                        if (!cpu.isHeld) cpu.acquire()
                        if (!wifi.isHeld) wifi.acquire()
                    } else {
                        release()
                    }
                    result.success(null)
                } catch (e: Exception) {
                    release()
                    result.error("power", e.message, null)
                }
            }
        }
    }

    private fun release() {
        if (wifi.isHeld) wifi.release()
        if (cpu.isHeld) cpu.release()
    }

    fun dispose() {
        release()
        channel.setMethodCallHandler(null)
    }
}
