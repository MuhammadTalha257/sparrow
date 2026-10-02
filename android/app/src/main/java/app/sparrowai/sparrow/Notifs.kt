package app.sparrowai.sparrow

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.RingtoneManager

object Notifs {
    const val REMINDERS = "reminders"
    const val SERVICE = "service"

    fun createChannels(c: Context) {
        val nm = c.getSystemService(NotificationManager::class.java)
        val rem = NotificationChannel(REMINDERS, "Reminders & meetings", NotificationManager.IMPORTANCE_HIGH).apply {
            description = "Alarms for your reminders and meetings"
            enableVibration(true)
            setSound(RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM),
                AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ALARM).build())
        }
        val svc = NotificationChannel(SERVICE, "Sparrow running", NotificationManager.IMPORTANCE_MIN).apply {
            description = "Shown while Sparrow listens or floats on screen"
        }
        nm.createNotificationChannel(rem)
        nm.createNotificationChannel(svc)
    }

    private fun openApp(c: Context, extra: String? = null, open: String? = null): PendingIntent {
        val i = Intent(c, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        if (extra != null) i.putExtra("ask", extra)
        if (open != null) i.putExtra("open", open)
        return PendingIntent.getActivity(c, (extra ?: open)?.hashCode() ?: 0, i, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }

    fun service(c: Context, text: String): Notification =
        Notification.Builder(c, SERVICE)
            .setSmallIcon(R.drawable.ic_stat)
            .setContentTitle("Sparrow")
            .setContentText(text)
            .setOngoing(true)
            .setContentIntent(openApp(c))
            .build()

    fun reminder(c: Context, id: Int, title: String, text: String, open: String? = null) {
        val n = Notification.Builder(c, REMINDERS)
            .setSmallIcon(R.drawable.ic_stat)
            .setContentTitle(title)
            .setContentText(text)
            .setStyle(Notification.BigTextStyle().bigText(text))
            .setCategory(Notification.CATEGORY_REMINDER)
            .setAutoCancel(true)
            .setContentIntent(openApp(c, null, open))
            .build()
        try { c.getSystemService(NotificationManager::class.java).notify(id, n) } catch (_: SecurityException) {}
    }

    fun answer(c: Context, question: String) {
        val n = Notification.Builder(c, REMINDERS)
            .setSmallIcon(R.drawable.ic_stat)
            .setContentTitle("Sparrow")
            .setContentText("Tap to see the answer: $question")
            .setAutoCancel(true)
            .setContentIntent(openApp(c, question))
            .build()
        try { c.getSystemService(NotificationManager::class.java).notify(7, n) } catch (_: SecurityException) {}
    }
}
