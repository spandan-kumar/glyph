package dev.spandankumar.glyph

import android.service.notification.NotificationListenerService

/**
 * Exists so the person can grant Glyph "Notification access": Android only
 * hands out other apps' media sessions (what's playing, its cover, the
 * position) to an enabled notification listener. Glyph never reads the
 * notifications themselves.
 */
class NowPlayingListener : NotificationListenerService()
