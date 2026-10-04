package dev.spandankumar.glyph

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.MediaMetadata
import android.media.session.MediaController
import android.media.session.MediaSessionManager
import android.media.session.PlaybackState
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * What's playing on the phone, for the Now Playing tool: follows every
 * active media session (Spotify, YouTube Music, podcasts…) and reports the
 * one that's playing — title, artist, timing and its cover, shrunk to
 * [ART] px square RGB — to Dart whenever it changes.
 *
 * Needs Notification access ([NowPlayingListener]); without it the stream
 * reports `access: false` and Dart offers the settings page.
 */
class NowPlayingBridge(private val context: Context, messenger: BinaryMessenger) :
    EventChannel.StreamHandler {

    companion object {
        const val ART = 64
        private const val CHANNEL = "glyph/now_playing"
    }

    private val main = Handler(Looper.getMainLooper())
    private val listener = ComponentName(context, NowPlayingListener::class.java)
    private val sessions = context.getSystemService(MediaSessionManager::class.java)
    private val callbacks = mutableMapOf<MediaController, MediaController.Callback>()
    private var sink: EventChannel.EventSink? = null

    // The last cover sent, so unchanged art isn't re-encoded on every tick.
    private var artSource: Bitmap? = null
    private var artBytes: ByteArray? = null

    init {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "hasAccess" -> result.success(hasAccess())
                "openSettings" -> {
                    openSettings()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        EventChannel(messenger, "$CHANNEL/events").setStreamHandler(this)
    }

    private fun hasAccess(): Boolean {
        val enabled = Settings.Secure.getString(context.contentResolver, "enabled_notification_listeners")
        return enabled?.split(':')?.any { ComponentName.unflattenFromString(it) == listener } == true
    }

    private fun openSettings() {
        // Android 11+ can open Glyph's own switch; older versions the list.
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            Intent(Settings.ACTION_NOTIFICATION_LISTENER_DETAIL_SETTINGS)
                .putExtra(Settings.EXTRA_NOTIFICATION_LISTENER_COMPONENT_NAME, listener.flattenToString())
        } else {
            Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
        }
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        try {
            context.startActivity(intent)
        } catch (_: Exception) {
            context.startActivity(
                Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
        }
    }

    private val sessionsChanged = MediaSessionManager.OnActiveSessionsChangedListener { list ->
        follow(list ?: emptyList())
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        sink = events
        if (!hasAccess()) {
            events.success(mapOf("access" to false))
            return
        }
        try {
            sessions.addOnActiveSessionsChangedListener(sessionsChanged, listener, main)
            follow(sessions.getActiveSessions(listener))
        } catch (e: SecurityException) {
            // Access was revoked between the check and the call.
            events.success(mapOf("access" to false))
        }
    }

    override fun onCancel(arguments: Any?) {
        sink = null
        try {
            sessions.removeOnActiveSessionsChangedListener(sessionsChanged)
        } catch (_: Exception) {
        }
        unfollowAll()
        artSource = null
        artBytes = null
    }

    private fun follow(list: List<MediaController>) {
        unfollowAll()
        for (c in list) {
            val cb = object : MediaController.Callback() {
                override fun onPlaybackStateChanged(state: PlaybackState?) = emit()
                override fun onMetadataChanged(metadata: MediaMetadata?) = emit()
                override fun onSessionDestroyed() = emit()
            }
            c.registerCallback(cb, main)
            callbacks[c] = cb
        }
        emit()
    }

    private fun unfollowAll() {
        for ((c, cb) in callbacks) c.unregisterCallback(cb)
        callbacks.clear()
    }

    /** The playing session, else the most recent one (the list is ordered). */
    private fun current(): MediaController? {
        val all = callbacks.keys.toList()
        return all.firstOrNull { it.playbackState?.state == PlaybackState.STATE_PLAYING }
            ?: all.firstOrNull { it.metadata != null }
    }

    private fun emit() {
        val out = sink ?: return
        val c = current()
        val meta = c?.metadata
        if (c == null || meta == null) {
            out.success(mapOf("access" to true))
            return
        }
        val state = c.playbackState
        val playing = state?.state == PlaybackState.STATE_PLAYING
        val speed = if (playing) (state?.playbackSpeed ?: 1f).toDouble() else 0.0
        // Bring the position up to now, so Dart only extrapolates from here.
        var position = state?.position ?: 0L
        if (playing && state != null && state.lastPositionUpdateTime > 0) {
            position += ((SystemClock.elapsedRealtime() - state.lastPositionUpdateTime) * speed).toLong()
        }
        val art = art(meta)
        out.success(
            mapOf(
                "access" to true,
                "app" to appName(c.packageName),
                "package" to c.packageName,
                "title" to (meta.getString(MediaMetadata.METADATA_KEY_TITLE)
                    ?: meta.getString(MediaMetadata.METADATA_KEY_DISPLAY_TITLE)),
                "artist" to (meta.getString(MediaMetadata.METADATA_KEY_ARTIST)
                    ?: meta.getString(MediaMetadata.METADATA_KEY_ALBUM_ARTIST)
                    ?: meta.getString(MediaMetadata.METADATA_KEY_DISPLAY_SUBTITLE)),
                "album" to meta.getString(MediaMetadata.METADATA_KEY_ALBUM),
                "durationMs" to meta.getLong(MediaMetadata.METADATA_KEY_DURATION),
                "positionMs" to position.coerceAtLeast(0L),
                "atMs" to System.currentTimeMillis(),
                "speed" to speed,
                "playing" to playing,
                "art" to art,
                "artSize" to if (art != null) ART else 0,
            )
        )
    }

    private fun appName(pkg: String): String = try {
        val pm = context.packageManager
        pm.getApplicationLabel(pm.getApplicationInfo(pkg, 0)).toString()
    } catch (_: Exception) {
        pkg
    }

    private fun art(meta: MediaMetadata): ByteArray? {
        val bmp = meta.getBitmap(MediaMetadata.METADATA_KEY_ALBUM_ART)
            ?: meta.getBitmap(MediaMetadata.METADATA_KEY_ART)
            ?: meta.getBitmap(MediaMetadata.METADATA_KEY_DISPLAY_ICON)
            ?: loadUri(
                meta.getString(MediaMetadata.METADATA_KEY_ALBUM_ART_URI)
                    ?: meta.getString(MediaMetadata.METADATA_KEY_ART_URI)
                    ?: meta.getString(MediaMetadata.METADATA_KEY_DISPLAY_ICON_URI)
            )
            ?: return null
        if (bmp === artSource) return artBytes
        val bytes = try {
            rgbSquare(bmp)
        } catch (_: Exception) {
            null
        }
        artSource = bmp
        artBytes = bytes
        return bytes
    }

    /** Local (content/file) art only: network covers come as bitmaps anyway. */
    private fun loadUri(uri: String?): Bitmap? {
        if (uri == null) return null
        val u = Uri.parse(uri)
        if (u.scheme != "content" && u.scheme != "file" && u.scheme != "android.resource") return null
        return try {
            context.contentResolver.openInputStream(u)?.use { BitmapFactory.decodeStream(it) }
        } catch (_: Exception) {
            null
        }
    }

    /** Centre square of [src], halved down then scaled to ART×ART, as RGB. */
    private fun rgbSquare(src: Bitmap): ByteArray {
        var bmp = if (src.config == Bitmap.Config.HARDWARE) src.copy(Bitmap.Config.ARGB_8888, false) else src
        val side = minOf(bmp.width, bmp.height)
        if (bmp.width != bmp.height) {
            bmp = Bitmap.createBitmap(bmp, (bmp.width - side) / 2, (bmp.height - side) / 2, side, side)
        }
        // Halving steps average 2×2 blocks, so big covers don't alias.
        var s = side
        while (s / 2 >= ART * 2) {
            s /= 2
            bmp = Bitmap.createScaledBitmap(bmp, s, s, true)
        }
        if (s != ART) bmp = Bitmap.createScaledBitmap(bmp, ART, ART, true)
        val px = IntArray(ART * ART)
        bmp.getPixels(px, 0, ART, 0, 0, ART, ART)
        val out = ByteArray(ART * ART * 3)
        for (i in px.indices) {
            val c = px[i]
            out[i * 3] = (c shr 16 and 0xFF).toByte()
            out[i * 3 + 1] = (c shr 8 and 0xFF).toByte()
            out[i * 3 + 2] = (c and 0xFF).toByte()
        }
        return out
    }
}
