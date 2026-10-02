package app.sparrowai.sparrow

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import org.json.JSONArray

/** Real alarms for reminders & meetings — they ring even when Sparrow is closed. */
object Alarms {
    /** json: [{ "id": "...", "at": epochMillis, "title": "...", "type": "reminder"|"meeting" }] */
    fun sync(c: Context, json: String) {
        val am = c.getSystemService(AlarmManager::class.java)
        val sp = Prefs.sp(c)
        sp.getStringSet("alarmIds", emptySet())?.forEach { am.cancel(pending(c, it, "", "")) }
        val ids = mutableSetOf<String>()
        val arr = try { JSONArray(json) } catch (e: Exception) { JSONArray() }
        val now = System.currentTimeMillis()
        for (i in 0 until arr.length()) {
            val o = arr.getJSONObject(i)
            val at = o.optLong("at")
            if (at <= now) continue
            val id = o.getString("id")
            ids += id
            val p = pending(c, id, o.optString("title"), o.optString("type"))
            try {
                if (Build.VERSION.SDK_INT >= 31 && !am.canScheduleExactAlarms()) {
                    am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, p)
                } else {
                    am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, p)
                }
            } catch (_: SecurityException) {
                am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, p)
            }
        }
        sp.edit().putStringSet("alarmIds", ids).putString("alarmsJson", json).apply()
    }

    private fun pending(c: Context, id: String, title: String, type: String): PendingIntent {
        val i = Intent(c, AlarmReceiver::class.java)
            .setAction("app.sparrowai.sparrow.ALARM.$id")
            .putExtra("title", title).putExtra("type", type).putExtra("id", id)
        return PendingIntent.getBroadcast(c, id.hashCode(), i, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }
}

class AlarmReceiver : BroadcastReceiver() {
    override fun onReceive(c: Context, intent: Intent) {
        val title = intent.getStringExtra("title") ?: "Reminder"
        val meeting = intent.getStringExtra("type") == "meeting"
        val head = if (meeting) "Meeting in 10 minutes" else "Reminder"
        Notifs.reminder(c, (intent.getStringExtra("id") ?: title).hashCode(), "⏰ $head", title)
        Speaker.init(c)
        Speaker.speak("$head: $title")
    }
}

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(c: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return
        val json = Prefs.sp(c).getString("alarmsJson", null) ?: return
        Alarms.sync(c, json)
    }
}
