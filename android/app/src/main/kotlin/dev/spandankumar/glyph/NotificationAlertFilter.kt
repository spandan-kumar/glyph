package dev.spandankumar.glyph

import android.app.Notification

/** Small bounded in-memory filter; never enumerates historical notifications. */
internal class NotificationAlertFilter {
    private var allowed = emptySet<String>()
    private val seen = linkedSetOf<String>()

    @Synchronized fun configure(packages: Set<String>) {
        allowed = packages
        seen.clear()
    }
    @Synchronized fun reset() = seen.clear()
    @Synchronized fun remove(key: String): Boolean = seen.remove(key)

    @Synchronized fun accept(packageName: String, key: String, flags: Int, category: String?): Boolean {
        if (packageName !in allowed ||
            flags and (Notification.FLAG_ONGOING_EVENT or Notification.FLAG_GROUP_SUMMARY or
                Notification.FLAG_FOREGROUND_SERVICE) != 0 ||
            category == Notification.CATEGORY_TRANSPORT || category == Notification.CATEGORY_SERVICE) return false
        if (!seen.add(key)) return false
        if (seen.size > 256) seen.remove(seen.first())
        return true
    }
}

/** Event sink shared by the listener service; only its latest owner may clear it. */
internal class AlertSinkOwner {
    @Volatile private var owner: Any? = null
    @Volatile private var sink: ((Map<String, Any?>) -> Unit)? = null
    val active: Boolean get() = sink != null

    @Synchronized fun attach(owner: Any, sink: (Map<String, Any?>) -> Unit) {
        this.owner = owner
        this.sink = sink
    }
    /** Returns false (and changes nothing) when [owner] was already replaced. */
    @Synchronized fun detach(owner: Any): Boolean {
        if (this.owner !== owner) return false
        this.owner = null
        sink = null
        return true
    }
    @Synchronized fun owns(owner: Any) = this.owner === owner
    fun emit(event: Map<String, Any?>) { sink?.invoke(event) }
}

/** Tiny access-ordered LRU; an entry is replaced when its [version] (e.g. app update time) changes. */
internal class IconCache<T : Any>(private val capacity: Int) {
    private val map = object : LinkedHashMap<String, Pair<Long, T>>(16, 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, Pair<Long, T>>) = size > capacity
    }
    @Synchronized fun get(key: String, version: Long, render: () -> T?): T? {
        map[key]?.let { (v, value) -> if (v == version) return value }
        val value = render() ?: return null.also { map.remove(key) }
        map[key] = version to value
        return value
    }
}
