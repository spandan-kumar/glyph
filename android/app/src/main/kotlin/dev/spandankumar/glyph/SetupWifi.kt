package dev.spandankumar.glyph

import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.wifi.WifiInfo
import android.net.wifi.WifiNetworkSpecifier
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PatternMatcher
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** Pure decisions, kept free of Android framework calls so they unit-test on the JVM. */
internal object SetupWifiLogic {
    const val DEFAULT_PREFIX = "WLED"
    const val DEFAULT_PASSWORD = "wled1234"
    const val MIN_SDK = 29

    data class Args(val ssid: String?, val prefix: String, val password: String)

    fun parse(arguments: Any?): Args {
        val m = arguments as? Map<*, *>
        val ssid = (m?.get("ssid") as? String)?.takeIf { it.isNotEmpty() }
        val prefix = (m?.get("prefix") as? String)?.takeIf { it.isNotEmpty() } ?: DEFAULT_PREFIX
        val password = m?.get("password") as? String ?: DEFAULT_PASSWORD
        return Args(ssid, prefix, password)
    }

    /** The SSID to report: the real one when the platform shows it, else what we asked for. */
    fun label(raw: String?, args: Args): String {
        val s = raw?.trim()?.removeSurrounding("\"")
        if (s.isNullOrEmpty() || s == "<unknown ssid>") return args.ssid ?: args.prefix
        return s
    }

    /** Dart treats unavailable and a dismissed system dialog the same (guided fallback). */
    fun unavailableCode() = "unavailable"

    fun supported(sdk: Int) = sdk >= MIN_SDK
}

/** Used only on the main thread, including queued network callbacks. */
internal class SetupWifiRequest {
    var active: Any? = null
    fun run(request: Any, block: () -> Unit) {
        if (active === request) block()
    }
}

/**
 * Joins a WLED setup access point (no internet) with the system's approval dialog and
 * binds the process to it so Dart's HTTP/UDP reach 4.3.2.1. Needs API 29+.
 */
class SetupWifi(private val context: Context, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "glyph/setup_wifi")
    private val cm = context.applicationContext
        .getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
    private val requests = SetupWifiRequest()
    private val main = Handler(Looper.getMainLooper())

    /** Answers the pending connect, if any: replaced or released requests must not leave Dart waiting. */
    private var settle: ((String?) -> Unit)? = null

    init {
        channel.setMethodCallHandler { call, result -> handle(call, result) }
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "connect" -> connect(SetupWifiLogic.parse(call.arguments), result)
            "release" -> { release(); result.success(null) }
            "bindWifi" -> result.success(bindWifi())
            "openSettings" -> try { openSettings(); result.success(null) }
                catch (e: Exception) { result.error("settings", e.message, null) }
            else -> result.notImplemented()
        }
    }

    private fun connect(args: SetupWifiLogic.Args, result: MethodChannel.Result) {
        if (!SetupWifiLogic.supported(Build.VERSION.SDK_INT)) {
            result.error("unsupported", "Needs Android 10 or newer", null)
            return
        }
        release() // a second connect replaces a pending first
        var replied = false
        // Callbacks and release share the main thread so obsolete requests cannot rebind.
        fun reply(block: () -> Unit) {
            if (replied) return
            replied = true
            block()
        }
        settle = { reply { result.error("cancelled", "Released", null) } }
        val cb = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                main.post {
                    requests.run(this) {
                        cm.bindProcessToNetwork(network)
                        val raw = (cm.getNetworkCapabilities(network)?.transportInfo as? WifiInfo)?.ssid
                        reply { result.success(SetupWifiLogic.label(raw, args)) }
                    }
                }
            }

            override fun onUnavailable() {
                main.post {
                    requests.run(this) {
                        reply { result.error(SetupWifiLogic.unavailableCode(), "Network unavailable", null) }
                    }
                }
            }

            override fun onLost(network: Network) {
                main.post { requests.run(this) { cm.bindProcessToNetwork(null) } }
            }
        }
        try {
            val spec = WifiNetworkSpecifier.Builder().apply {
                if (args.ssid != null) setSsid(args.ssid)
                else setSsidPattern(PatternMatcher(args.prefix, PatternMatcher.PATTERN_PREFIX))
                if (args.password.isNotEmpty()) setWpa2Passphrase(args.password)
            }.build()
            val request = NetworkRequest.Builder()
                .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
                .removeCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                .setNetworkSpecifier(spec)
                .build()
            requests.active = cb
            // No app-side timeout: the system dialog runs its own scan with "Try again",
            // and cancelling under it leaves an orphaned "Something came up" dialog.
            cm.requestNetwork(request, cb)
        } catch (e: Exception) {
            requests.active = null
            reply { result.error(if (e is SecurityException) "denied" else "failed", e.javaClass.simpleName, null) }
        }
    }

    /**
     * Guided path: the person joined the setup network in Settings. Android keeps a
     * network with no internet out of the default route (mobile data wins), so bind
     * the app to the Wi-Fi network directly. Works from API 23.
     */
    @Suppress("DEPRECATION")
    private fun bindWifi(): Boolean {
        val wifi = cm.allNetworks.firstOrNull {
            cm.getNetworkCapabilities(it)?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true
        } ?: return false
        return try { cm.bindProcessToNetwork(wifi) } catch (_: Exception) { false }
    }

    private fun release() {
        settle?.invoke(null)
        settle = null
        // Also undoes a guided bindWifi, which has no callback.
        try { cm.bindProcessToNetwork(null) } catch (_: Exception) {}
        val cb = requests.active as? ConnectivityManager.NetworkCallback
        requests.active = null
        if (cb == null) return
        try { cm.unregisterNetworkCallback(cb) } catch (_: IllegalArgumentException) {}
    }

    private fun openSettings() {
        val action = if (Build.VERSION.SDK_INT >= 29) Settings.Panel.ACTION_WIFI
            else Settings.ACTION_WIFI_SETTINGS
        context.startActivity(Intent(action).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }

    fun dispose() {
        release()
        channel.setMethodCallHandler(null)
    }
}
