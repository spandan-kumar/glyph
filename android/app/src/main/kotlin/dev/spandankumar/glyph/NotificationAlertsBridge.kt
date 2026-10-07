package dev.spandankumar.glyph

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.database.ContentObserver
import android.graphics.Bitmap
import android.graphics.Canvas
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/** Only installed app icons cross this bridge; notification contents never do. */
class NotificationAlertsBridge(private val context: Context, messenger: BinaryMessenger) :
    EventChannel.StreamHandler {
    private val methods = MethodChannel(messenger, "glyph/notifications")
    private val events = EventChannel(messenger, "glyph/notifications/events")
    private val listener = ComponentName(context, NowPlayingListener::class.java)
    private var sink: EventChannel.EventSink? = null
    private val main = Handler(Looper.getMainLooper())
    // Listing every launcher app and its label is slow; keep it off the main thread.
    private val worker: ExecutorService = Executors.newSingleThreadExecutor()

    // Android can disconnect the listener before committing its access setting.
    private val accessObserver = object : ContentObserver(Handler(Looper.getMainLooper())) {
        override fun onChange(selfChange: Boolean) {
            val current = status()
            if (current["access"] == false) NowPlayingListener.configure(this@NotificationAlertsBridge, emptySet())
            sink?.success(current)
        }
    }

    init {
        context.contentResolver.registerContentObserver(
            Settings.Secure.getUriFor("enabled_notification_listeners"), false, accessObserver)

        methods.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "apps" -> worker.execute {
                        val reply = try {
                            val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
                            @Suppress("DEPRECATION")
                            val apps = context.packageManager.queryIntentActivities(intent, 0)
                                .filter { it.activityInfo.packageName != context.packageName }
                                .distinctBy { it.activityInfo.packageName }
                                .map { mapOf("package" to it.activityInfo.packageName,
                                    "name" to it.loadLabel(context.packageManager).toString()) }
                                .sortedBy { it["name"]?.lowercase() }
                            Result.success(apps)
                        } catch (e: Exception) { Result.failure(e) }
                        main.post {
                            reply.fold({ result.success(it) },
                                { result.error("notifications", "Couldn't list apps", null) })
                        }
                    }
                    "icon" -> result.success(appIcon(context, call.arguments as String))
                    "status" -> result.success(status())
                    "configure" -> {
                        val packages = (call.arguments as? List<*>)?.filterIsInstance<String>() ?: emptyList()
                        NowPlayingListener.configure(this, if (sink == null) emptySet() else
                            packages.filter { it != context.packageName }.toSet())
                        result.success(status())
                    }
                    "openSettings" -> {
                        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                            Intent(Settings.ACTION_NOTIFICATION_LISTENER_DETAIL_SETTINGS).putExtra(
                                Settings.EXTRA_NOTIFICATION_LISTENER_COMPONENT_NAME, listener.flattenToString())
                        } else Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
                        try {
                            context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                        } catch (_: Exception) {
                            context.startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
                                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("notifications", "Couldn't access app icons or notification settings", null)
            }
        }
        events.setStreamHandler(this)
    }

    private fun status(): Map<String, Boolean> {
        val enabled = Settings.Secure.getString(context.contentResolver, "enabled_notification_listeners")
        val access = enabled?.split(':')?.any { ComponentName.unflattenFromString(it) == listener } == true
        return mapOf("access" to access, "connected" to (access && NowPlayingListener.connected))
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        sink = events
        NowPlayingListener.attach(this) { event -> sink?.success(event) }
        events.success(status())
    }

    override fun onCancel(arguments: Any?) {
        sink = null
        NowPlayingListener.detach(this)
    }

    fun dispose() {
        context.contentResolver.unregisterContentObserver(accessObserver)
        onCancel(null)
        methods.setMethodCallHandler(null)
        events.setStreamHandler(null)
        worker.shutdownNow()
    }

    companion object {
        const val ICON_SIZE = 32
        private val icons = IconCache<ByteArray>(8)

        /** Rendered 32x32 RGB, cached per package and invalidated when the app is updated. */
        fun appIcon(context: Context, packageName: String): ByteArray? {
            val version = try {
                context.packageManager.getPackageInfo(packageName, 0).lastUpdateTime
            } catch (_: Exception) { return null }
            return icons.get(packageName, version) { renderIcon(context, packageName) }
        }

        private fun renderIcon(context: Context, packageName: String): ByteArray? {
            return try {
                val drawable = context.packageManager.getApplicationIcon(packageName)
                val bitmap = Bitmap.createBitmap(ICON_SIZE, ICON_SIZE, Bitmap.Config.ARGB_8888)
                val canvas = Canvas(bitmap)
                canvas.drawColor(android.graphics.Color.BLACK)
                drawable.setBounds(0, 0, ICON_SIZE, ICON_SIZE)
                drawable.draw(canvas)
                val pixels = IntArray(ICON_SIZE * ICON_SIZE)
                bitmap.getPixels(pixels, 0, ICON_SIZE, 0, 0, ICON_SIZE, ICON_SIZE)
                bitmap.recycle()
                ByteArray(pixels.size * 3).also { bytes ->
                    pixels.forEachIndexed { i, c ->
                        bytes[i * 3] = (c shr 16).toByte()
                        bytes[i * 3 + 1] = (c shr 8).toByte()
                        bytes[i * 3 + 2] = c.toByte()
                    }
                }
            } catch (_: Exception) { null }
        }
    }
}
