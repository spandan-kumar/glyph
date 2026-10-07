package dev.spandankumar.glyph

import android.app.Notification

/** Small bounded in-memory filter; never enumerates historical notifications. */
internal class NotificationAlertFilter {
    private var allowed = emptySet<String>()
    private val seen = linkedSetOf<String>()

    fun configure(packages: Set<String>) {
        allowed = packages
        seen.clear()
    }
    fun reset() = seen.clear()
    fun remove(key: String): Boolean = seen.remove(key)

    fun accept(packageName: String, key: String, flags: Int, category: String?): Boolean {
        if (packageName !in allowed ||
            flags and (Notification.FLAG_ONGOING_EVENT or Notification.FLAG_GROUP_SUMMARY or
                Notification.FLAG_FOREGROUND_SERVICE) != 0 ||
            category == Notification.CATEGORY_TRANSPORT || category == Notification.CATEGORY_SERVICE) return false
        if (!seen.add(key)) return false
        if (seen.size > 256) seen.remove(seen.first())
        return true
    }
}
