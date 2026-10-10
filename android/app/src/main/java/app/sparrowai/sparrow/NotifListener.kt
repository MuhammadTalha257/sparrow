package app.sparrowai.sparrow

import android.app.Notification
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

/** Reads new notifications out loud (only when the person turned it on). */
class NotifListener : NotificationListenerService() {
    private var lastKey = ""
    private var lastAt = 0L

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        // WhatsApp chats → leads / autopilot replies (Zuffi Business)
        if (WhatsAppPilot.isWhatsApp(sbn.packageName)) {
            try { WhatsAppPilot.handle(this, sbn) } catch (_: Exception) {}
        }
        if (!Prefs.sp(this).getBoolean("readNotifs", false)) return
        if (sbn.packageName == packageName || sbn.isOngoing) return
        val n = sbn.notification
        if ((n.flags and Notification.FLAG_GROUP_SUMMARY) != 0) return
        val ex = n.extras
        val title = ex.getCharSequence(Notification.EXTRA_TITLE)?.toString().orEmpty()
        val text = ex.getCharSequence(Notification.EXTRA_TEXT)?.toString().orEmpty()
        if (title.isBlank() && text.isBlank()) return
        val key = sbn.packageName + title + text
        val now = System.currentTimeMillis()
        if (key == lastKey && now - lastAt < 10_000) return
        lastKey = key; lastAt = now
        val app = try {
            packageManager.getApplicationLabel(packageManager.getApplicationInfo(sbn.packageName, 0)).toString()
        } catch (e: Exception) { "" }
        Speaker.init(this)
        Speaker.speak(listOf(app, title, text.take(220)).filter { it.isNotBlank() }.joinToString(". "))
    }
}
