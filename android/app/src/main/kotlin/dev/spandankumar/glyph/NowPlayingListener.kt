package dev.spandankumar.glyph

import android.content.ComponentName
import android.provider.Settings
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

/** Also grants media-session access for Now Playing. No notification extras are read. */
class NowPlayingListener : NotificationListenerService() {
    companion object {
        @Volatile var connected = false
            private set
        private val sink = AlertSinkOwner()
        private val filter = NotificationAlertFilter()

        /** The newest bridge owns the event sink; an older one can't clear it later. */
        fun attach(owner: Any, emit: (Map<String, Any?>) -> Unit) {
            sink.attach(owner, emit)
            filter.configure(emptySet())
        }

        /** No-op unless [owner] is still the current owner. */
        fun detach(owner: Any) {
            if (sink.detach(owner)) filter.configure(emptySet())
        }

        fun configure(owner: Any, packages: Set<String>) {
            if (sink.owns(owner)) filter.configure(packages)
        }
    }

    override fun onListenerConnected() {
        connected = true
        filter.reset()
        sink.emit(mapOf("access" to true, "connected" to true))
        // Never enumerate activeNotifications: granting access must not replay history.
    }

    override fun onListenerDisconnected() {
        connected = false
        filter.reset()
        val enabled = Settings.Secure.getString(contentResolver, "enabled_notification_listeners")
        val component = ComponentName(this, NowPlayingListener::class.java)
        val access = enabled?.split(':')?.any { ComponentName.unflattenFromString(it) == component } == true
        sink.emit(mapOf("access" to access, "connected" to false))
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        if (!connected || !sink.active || sbn.packageName == packageName) return
        val n = sbn.notification
        if (!filter.accept(sbn.packageName, sbn.key, n.flags, n.category)) return
        sink.emit(mapOf("package" to sbn.packageName, "key" to sbn.key,
            "time" to System.currentTimeMillis(),
            "icon" to NotificationAlertsBridge.appIcon(this, sbn.packageName)))
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification) {
        if (filter.remove(sbn.key)) sink.emit(mapOf("removed" to sbn.key))
    }
}
