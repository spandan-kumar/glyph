package dev.spandankumar.glyph

import android.content.ComponentName
import android.provider.Settings
import android.content.Intent
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

/** Also grants media-session access for Now Playing. No notification extras are read. */
class NowPlayingListener : NotificationListenerService() {
    companion object {
        var connected = false
            private set
        var emit: ((Map<String, Any?>) -> Unit)? = null
        private val filter = NotificationAlertFilter()

        fun configure(packages: Set<String>) {
            filter.configure(packages)
        }
    }

    override fun onListenerConnected() {
        connected = true
        filter.reset()
        emit?.invoke(mapOf("access" to true, "connected" to true))
        // Never enumerate activeNotifications: granting access must not replay history.
    }

    override fun onListenerDisconnected() {
        connected = false
        filter.reset()
        val enabled = Settings.Secure.getString(contentResolver, "enabled_notification_listeners")
        val component = ComponentName(this, NowPlayingListener::class.java)
        val access = enabled?.split(':')?.any { ComponentName.unflattenFromString(it) == component } == true
        emit?.invoke(mapOf("access" to access, "connected" to false))
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        configure(emptySet())
        emit?.invoke(mapOf("stopped" to true))
        super.onTaskRemoved(rootIntent)
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        if (!connected || emit == null || sbn.packageName == packageName) return
        val n = sbn.notification
        if (!filter.accept(sbn.packageName, sbn.key, n.flags, n.category)) return
        emit?.invoke(mapOf("package" to sbn.packageName, "key" to sbn.key,
            "time" to System.currentTimeMillis(),
            "icon" to NotificationAlertsBridge.appIcon(this, sbn.packageName)))
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification) {
        if (filter.remove(sbn.key)) emit?.invoke(mapOf("removed" to sbn.key))
    }
}
