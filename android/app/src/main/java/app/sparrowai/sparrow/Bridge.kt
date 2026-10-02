package app.sparrowai.sparrow

import android.content.Intent
import android.net.Uri
import android.provider.CalendarContract
import android.provider.Settings
import android.webkit.JavascriptInterface
import androidx.core.app.NotificationManagerCompat
import org.json.JSONArray
import org.json.JSONObject

/** What the Sparrow web app can ask the phone to do (window.SparrowNative). */
class Bridge(private val a: MainActivity) {

    @JavascriptInterface fun platform(): String = "android"

    @JavascriptInterface fun speak(text: String, gender: String) {
        Speaker.gender = gender
        Prefs.sp(a).edit().putString("gender", gender).apply()
        Speaker.applyVoice()
        Speaker.speak(text)
    }

    @JavascriptInterface fun stopSpeaking() { Speaker.stop() }

    @JavascriptInterface fun listen() { a.runOnUiThread { a.startListening() } }

    @JavascriptInterface fun openApp(name: String): Boolean = Apps.open(a, name) != null

    @JavascriptInterface fun listApps(): String {
        val arr = JSONArray()
        Apps.list(a).forEach { arr.put(JSONObject().put("name", it.label).put("pkg", it.pkg)) }
        return arr.toString()
    }

    @JavascriptInterface fun syncAlarms(json: String) { Alarms.sync(a, json) }

    @JavascriptInterface fun addToCalendar(title: String, start: Double, end: Double) {
        val i = Intent(Intent.ACTION_INSERT)
            .setData(CalendarContract.Events.CONTENT_URI)
            .putExtra(CalendarContract.Events.TITLE, title)
            .putExtra(CalendarContract.EXTRA_EVENT_BEGIN_TIME, start.toLong())
            .putExtra(CalendarContract.EXTRA_EVENT_END_TIME, end.toLong())
            .putExtra(CalendarContract.Events.DESCRIPTION, "Added by Sparrow 🐦")
            .putExtra(CalendarContract.Events.HAS_ALARM, 1)
        a.runOnUiThread { Commands.startSafely(a, i) }
    }

    @JavascriptInterface fun setWakeWord(on: Boolean) {
        Prefs.sp(a).edit().putBoolean("wakeWord", on).apply()
        a.runOnUiThread {
            val svc = Intent(a, VoiceService::class.java)
            if (on) a.withMic { a.startForegroundService(svc); a.send(JSONObject().put("type", "status")) }
            else { a.stopService(svc); a.send(JSONObject().put("type", "status")) }
        }
    }

    @JavascriptInterface fun setBubble(on: Boolean) {
        Prefs.sp(a).edit().putBoolean("bubble", on).apply()
        a.runOnUiThread {
            val svc = Intent(a, BubbleService::class.java)
            if (!on) { a.stopService(svc); return@runOnUiThread }
            if (!Settings.canDrawOverlays(a)) {
                Commands.startSafely(a, Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:" + a.packageName)))
            } else a.startForegroundService(svc)
        }
    }

    @JavascriptInterface fun setReadNotifications(on: Boolean) {
        Prefs.sp(a).edit().putBoolean("readNotifs", on).apply()
        if (on && !hasNotificationAccess()) a.runOnUiThread {
            Commands.startSafely(a, Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
        }
    }

    private fun hasNotificationAccess() =
        NotificationManagerCompat.getEnabledListenerPackages(a).contains(a.packageName)

    @JavascriptInterface fun status(): String {
        val sp = Prefs.sp(a)
        // Start the bubble once overlay permission was granted in Settings
        if (sp.getBoolean("bubble", false) && Settings.canDrawOverlays(a) && !BubbleService.running) {
            a.runOnUiThread { a.startForegroundService(Intent(a, BubbleService::class.java)) }
        }
        return JSONObject()
            .put("wakeWord", sp.getBoolean("wakeWord", false))
            .put("listening", VoiceService.running)
            .put("bubble", sp.getBoolean("bubble", false))
            .put("overlay", Settings.canDrawOverlays(a))
            .put("readNotifs", sp.getBoolean("readNotifs", false))
            .put("notifAccess", hasNotificationAccess())
            .put("mic", a.hasMic())
            .toString()
    }
}
