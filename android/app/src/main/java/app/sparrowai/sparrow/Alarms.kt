package app.sparrowai.sparrow

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import org.json.JSONArray
import org.json.JSONObject

/** Real alarms for reminders & meetings — they ring even when Sparrow is closed. */
object Alarms {
    /** json: [{ "id", "at": epochMillis, "title", "type": reminder|meeting|briefing|checkin, "say", "head", "open", "again" }] */
    fun sync(c: Context, json: String) {
        val am = c.getSystemService(AlarmManager::class.java)
        val sp = Prefs.sp(c)
        sp.getStringSet("alarmIds", emptySet())?.forEach { am.cancel(pending(c, it, JSONObject())) }
        val ids = mutableSetOf<String>()
        val arr = try { JSONArray(json) } catch (e: Exception) { JSONArray() }
        val now = System.currentTimeMillis()
        for (i in 0 until arr.length()) {
            val o = arr.getJSONObject(i)
            val at = o.optLong("at")
            if (at <= now) continue
            val id = o.getString("id")
            ids += id
            arm(c, am, at, pending(c, id, o))
        }
        sp.edit().putStringSet("alarmIds", ids).putString("alarmsJson", json).apply()
    }

    fun arm(c: Context, am: AlarmManager, at: Long, p: PendingIntent) {
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

    fun pending(c: Context, id: String, o: JSONObject): PendingIntent {
        val i = Intent(c, AlarmReceiver::class.java)
            .setAction("app.sparrowai.sparrow.ALARM.$id")
            .putExtra("id", id)
            .putExtra("title", o.optString("title"))
            .putExtra("type", o.optString("type"))
            .putExtra("say", o.optString("say"))
            .putExtra("head", o.optString("head"))
            .putExtra("open", o.optString("open"))
            .putExtra("again", o.optString("again"))
        return PendingIntent.getBroadcast(c, id.hashCode(), i, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }
}

class AlarmReceiver : BroadcastReceiver() {
    override fun onReceive(c: Context, intent: Intent) {
        val id = intent.getStringExtra("id") ?: "x"
        val title = intent.getStringExtra("title") ?: "Reminder"
        val type = intent.getStringExtra("type") ?: "reminder"
        val head = intent.getStringExtra("head").takeUnless { it.isNullOrBlank() }
            ?: if (type == "meeting") "Meeting" else "Reminder"
        val say = intent.getStringExtra("say").takeUnless { it.isNullOrBlank() } ?: "$head: $title"
        val open = intent.getStringExtra("open").takeUnless { it.isNullOrBlank() }
        val body = if (type == "briefing" || type == "checkin") say else title
        Notifs.reminder(c, id.hashCode(), head, body, open)
        // Zuffi the bunny walks onto the screen with it (if she's switched on)
        if (type == "reminder" || type == "meeting") PetService.remind(c, id, head, title)
        // Daily ones repeat tomorrow (the app refreshes the words whenever it's opened).
        if (type == "briefing" || type == "checkin") {
            val again = intent.getStringExtra("again").takeUnless { it.isNullOrBlank() } ?: say
            val o = JSONObject().put("title", title).put("type", type).put("head", head)
                .put("say", again).put("open", open ?: "").put("again", again)
            Alarms.arm(c, c.getSystemService(AlarmManager::class.java),
                System.currentTimeMillis() + 24 * 3600_000L, Alarms.pending(c, id, o))
        }
        // Keep the receiver alive long enough to start speaking.
        val done = goAsync()
        Speaker.init(c)
        Speaker.speak(say)
        Handler(Looper.getMainLooper()).postDelayed({ done.finish() }, 9000)
    }
}

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(c: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return
        PetService.refresh(c)
        val json = Prefs.sp(c).getString("alarmsJson", null) ?: return
        Alarms.sync(c, json)
    }
}
