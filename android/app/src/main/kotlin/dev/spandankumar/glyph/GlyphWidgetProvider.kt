package dev.spandankumar.glyph

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.SystemClock
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

/**
 * Home-screen widget: the selected matrix's name, a power toggle and a "next preset" button.
 *
 * The Flutter side (lib/features/device/home_widget_bridge.dart) stores the host and name with
 * home_widget. Button presses are handled here with plain HTTP to the WLED JSON API, so they work
 * without starting the app or a Flutter engine:
 *  - power: POST /json/state {"on":"t","v":true} ("t" toggles, json.cpp deserializeState; "v"
 *    returns the new state)
 *  - next: {"np":true} while a device playlist runs, else the next stored preset after the
 *    current one ({"ps":id}), skipping presets that only turn the light off.
 */
class GlyphWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        for (id in appWidgetIds) appWidgetManager.updateAppWidget(id, buildViews(context, widgetData))
    }

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action
        if (action == ACTION_POWER || action == ACTION_NEXT) {
            handle(context, action)
        } else {
            super.onReceive(context, intent)
        }
    }

    private fun handle(context: Context, action: String) {
        val prefs = HomeWidgetPlugin.getData(context)
        val host = prefs.getString(KEY_HOST, null)
        if (host.isNullOrBlank()) {
            prefs.edit().putString(KEY_STATUS, "Open Glyph to pick a matrix").apply()
            refreshAll(context)
            return
        }
        prefs.edit().putString(KEY_STATUS, "…").apply()
        refreshAll(context)
        val pending = goAsync()
        Thread {
            // Broadcast receivers get ~10 s with goAsync(); stay well inside it.
            val deadline = SystemClock.elapsedRealtime() + 8_000
            val edit = prefs.edit()
            try {
                if (action == ACTION_POWER) {
                    val state = JSONObject(request(host, "/json/state", """{"on":"t","v":true}""", deadline))
                    val on = state.optBoolean("on", false)
                    edit.putBoolean(KEY_ON, on).putString(KEY_STATUS, if (on) "On" else "Off")
                } else {
                    edit.putBoolean(KEY_ON, true).putString(KEY_STATUS, nextPreset(host, deadline))
                }
            } catch (e: Exception) {
                edit.putString(KEY_STATUS, "Can't reach the matrix")
            } finally {
                edit.apply()
                refreshAll(context)
                pending.finish()
            }
        }.start()
    }

    private fun nextPreset(host: String, deadline: Long): String {
        val state = JSONObject(request(host, "/json/state", null, deadline))
        // "pl" is -1 without a playlist (0 for one started by a save).
        if (state.optInt("pl", -1) >= 0) {
            request(host, "/json/state", """{"np":true}""", deadline)
            return "Next in playlist"
        }
        val current = state.optInt("ps", -1)
        val presets = JSONObject(request(host, "/presets.json", null, deadline))
        val ids = mutableListOf<Int>()
        val names = mutableMapOf<Int, String>()
        for (key in presets.keys()) {
            val id = key.toIntOrNull() ?: continue
            val body = presets.optJSONObject(key) ?: continue
            if (id !in 1..250 || body.length() == 0) continue
            if (body.has("on") && !body.optBoolean("on", true) && !body.has("seg")) continue
            ids.add(id)
            names[id] = body.optString("n", "Preset $id")
        }
        if (ids.isEmpty()) return "No presets saved"
        ids.sort()
        val next = ids.firstOrNull { it > current } ?: ids.first()
        // WLED ignores {"ps":id} for the preset that is already current.
        if (next != current) request(host, "/json/state", """{"on":true,"ps":$next}""", deadline)
        return names[next] ?: "Preset $next"
    }

    /** GET (body null) or POST JSON; retried while time remains (weak Wi‑Fi drops requests). */
    private fun request(host: String, path: String, body: String?, deadline: Long): String {
        var last: Exception? = null
        while (true) {
            val remaining = deadline - SystemClock.elapsedRealtime()
            if (remaining < 800) throw last ?: java.io.IOException("timeout")
            val conn = URL("http://${authority(host)}$path").openConnection() as HttpURLConnection
            try {
                val t = minOf(remaining, 3_500L).toInt()
                conn.connectTimeout = t
                conn.readTimeout = t
                conn.useCaches = false
                if (body != null) {
                    conn.requestMethod = "POST"
                    conn.doOutput = true
                    conn.setRequestProperty("Content-Type", "application/json")
                    conn.outputStream.use { it.write(body.toByteArray()) }
                }
                if (conn.responseCode != 200) throw java.io.IOException("HTTP ${conn.responseCode}")
                return conn.inputStream.bufferedReader().use { it.readText() }
            } catch (e: Exception) {
                last = e
                // A timed-out POST may still have been applied: never repeat a toggle or a skip.
                if (body != null && (body.contains("\"t\"") || body.contains("\"np\""))) throw e
            } finally {
                conn.disconnect()
            }
        }
    }

    companion object {
        const val ACTION_POWER = "dev.spandankumar.glyph.widget.POWER"
        const val ACTION_NEXT = "dev.spandankumar.glyph.widget.NEXT"

        // Keys written by HomeWidgetBridge (Dart).
        const val KEY_HOST = "glyph_host"
        const val KEY_NAME = "glyph_name"
        const val KEY_ON = "glyph_on"
        const val KEY_STATUS = "glyph_widget_status"

        private fun authority(host: String) =
            if (host.count { it == ':' } > 1 && !host.startsWith("[")) "[$host]" else host

        fun refreshAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, GlyphWidgetProvider::class.java))
            if (ids.isEmpty()) return
            val views = buildViews(context, HomeWidgetPlugin.getData(context))
            for (id in ids) manager.updateAppWidget(id, views)
        }

        fun buildViews(context: Context, prefs: SharedPreferences): RemoteViews {
            val views = RemoteViews(context.packageName, R.layout.glyph_widget)
            val host = prefs.getString(KEY_HOST, null)
            val name = prefs.getString(KEY_NAME, null) ?: if (host == null) "Glyph" else host
            val on = if (prefs.contains(KEY_ON)) prefs.getBoolean(KEY_ON, false) else null
            val status = prefs.getString(KEY_STATUS, null)
                ?: when {
                    host == null -> "No matrix selected"
                    on == true -> "On"
                    on == false -> "Off"
                    else -> host
                }
            views.setTextViewText(R.id.glyph_widget_name, name)
            views.setTextViewText(R.id.glyph_widget_status, status)
            views.setInt(
                R.id.glyph_widget_power, "setColorFilter",
                if (on == true) 0xFF8B7CFF.toInt() else 0xFF8C8CA3.toInt(),
            )

            val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            context.packageManager.getLaunchIntentForPackage(context.packageName)?.let {
                views.setOnClickPendingIntent(
                    R.id.glyph_widget_root, PendingIntent.getActivity(context, 0, it, flags),
                )
            }
            fun broadcast(action: String, code: Int) = PendingIntent.getBroadcast(
                context, code,
                Intent(context, GlyphWidgetProvider::class.java).setAction(action), flags,
            )
            views.setOnClickPendingIntent(R.id.glyph_widget_power, broadcast(ACTION_POWER, 1))
            views.setOnClickPendingIntent(R.id.glyph_widget_next, broadcast(ACTION_NEXT, 2))
            return views
        }
    }
}
