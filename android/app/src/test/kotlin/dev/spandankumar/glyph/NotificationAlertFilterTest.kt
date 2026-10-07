package dev.spandankumar.glyph

import android.app.Notification
import org.junit.Assert.*
import org.junit.Test

class NotificationAlertFilterTest {
    @Test fun defaultsOffAndFiltersBeforeAnyIconWork() {
        val f = NotificationAlertFilter()
        assertFalse(f.accept("chat", "a", 0, null))
        f.configure(setOf("chat"))
        assertFalse(f.accept("other", "a", 0, null))
        assertTrue(f.accept("chat", "a", 0, null))
    }
    @Test fun skipsOngoingServicesMediaAndSummaries() {
        val f = NotificationAlertFilter()
        f.configure(setOf("chat"))
        for (flag in listOf(Notification.FLAG_ONGOING_EVENT, Notification.FLAG_GROUP_SUMMARY,
            Notification.FLAG_FOREGROUND_SERVICE)) assertFalse(f.accept("chat", "$flag", flag, null))
        assertFalse(f.accept("chat", "music", 0, Notification.CATEGORY_TRANSPORT))
        assertFalse(f.accept("chat", "service", 0, Notification.CATEGORY_SERVICE))
        assertTrue(f.accept("chat", "message", 0, Notification.CATEGORY_MESSAGE))
    }
    @Test fun coalescesUpdatesUntilRemovalAndClearsWhenDisabled() {
        val f = NotificationAlertFilter()
        f.configure(setOf("chat"))
        assertTrue(f.accept("chat", "key", 0, null))
        assertFalse(f.accept("chat", "key", 0, null))
        assertTrue(f.remove("key"))
        assertTrue(f.accept("chat", "key", 0, null))
        f.configure(emptySet())
        assertFalse(f.accept("chat", "new", 0, null))
    }
    @Test fun boundsTrackingAndResetsAcrossListenerConnections() {
        val f = NotificationAlertFilter()
        f.configure(setOf("chat"))
        for (i in 0..256) assertTrue(f.accept("chat", "$i", 0, null))
        assertFalse(f.remove("0"))
        assertTrue(f.remove("1"))
        f.reset()
        assertTrue(f.accept("chat", "256", 0, null))
    }
}
