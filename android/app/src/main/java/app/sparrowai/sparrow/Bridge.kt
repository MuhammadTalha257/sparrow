package app.sparrowai.sparrow

import android.app.SearchManager
import android.content.ContentValues
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.util.Base64
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
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

    /** "play Tum Hi Ho on Spotify" — Android's own "play from search" command, no API needed. */
    @JavascriptInterface fun playSong(query: String, where: String) {
        a.runOnUiThread {
            val pkgs = when (where) {
                "youtube" -> listOf("com.google.android.apps.youtube.music")
                "music" -> listOf("com.apple.android.music")
                else -> listOf("com.spotify.music")
            }
            for (pkg in pkgs) {
                val i = Intent(MediaStore.INTENT_ACTION_MEDIA_PLAY_FROM_SEARCH)
                    .putExtra(SearchManager.QUERY, query)
                    .putExtra(MediaStore.EXTRA_MEDIA_FOCUS, "vnd.android.cursor.item/*")
                    .setPackage(pkg).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                try { a.startActivity(i); return@runOnUiThread } catch (_: Exception) {}
            }
            if (where == "youtube") {
                try { a.startActivity(Intent(Intent.ACTION_SEARCH).setPackage("com.google.android.youtube").putExtra("query", query).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)); return@runOnUiThread } catch (_: Exception) {}
            }
            try { a.startActivity(Intent(MediaStore.INTENT_ACTION_MEDIA_PLAY_FROM_SEARCH).putExtra(SearchManager.QUERY, query).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)); return@runOnUiThread } catch (_: Exception) {}
            a.openExternal(Uri.parse(if (where == "youtube") "https://www.youtube.com/results?search_query=" + Uri.encode(query) else "https://open.spotify.com/search/" + Uri.encode(query)))
        }
    }

    /** AI requests sent from the phone itself (no browser limits). Result comes back as an "http" event. */
    @JavascriptInterface fun httpPost(id: Int, url: String, headersJson: String, body: String) {
        Thread {
            var status = 0; var text: String
            try {
                val c = URL(url).openConnection() as HttpURLConnection
                c.requestMethod = "POST"; c.doOutput = true; c.connectTimeout = 20000; c.readTimeout = 90000
                val h = JSONObject(headersJson); h.keys().forEach { k -> c.setRequestProperty(k, h.getString(k)) }
                c.outputStream.use { it.write(body.toByteArray()) }
                status = c.responseCode
                text = (if (status in 200..299) c.inputStream else c.errorStream)?.bufferedReader()?.readText().orEmpty()
            } catch (e: Exception) { text = JSONObject().put("error", JSONObject().put("message", "No internet: " + e.message)).toString() }
            a.send(JSONObject().put("type", "http").put("id", id).put("status", status).put("body", text))
        }.start()
    }

    /** Saves a file Sparrow made (PDF, CSV…) to Downloads and offers to share it. */
    @JavascriptInterface fun saveFile(name: String, base64: String, mime: String): Boolean {
        return try {
            val bytes = Base64.decode(base64, Base64.DEFAULT)
            val uri: Uri? = if (Build.VERSION.SDK_INT >= 29) {
                val v = ContentValues().apply {
                    put(MediaStore.Downloads.DISPLAY_NAME, name); put(MediaStore.Downloads.MIME_TYPE, mime)
                    put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS + "/Zuffi")
                }
                a.contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, v)?.also { u -> a.contentResolver.openOutputStream(u)?.use { it.write(bytes) } }
            } else {
                val f = File(a.getExternalFilesDir(Environment.DIRECTORY_DOCUMENTS), name); f.writeBytes(bytes); null
            }
            a.runOnUiThread {
                if (uri != null) Commands.startSafely(a, Intent.createChooser(Intent(Intent.ACTION_SEND).setType(mime).putExtra(Intent.EXTRA_STREAM, uri).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION), name))
                a.send(JSONObject().put("type", "toast").put("text", "Saved to Downloads/Zuffi: $name"))
            }
            true
        } catch (e: Exception) { false }
    }

    @JavascriptInterface fun addToCalendar(title: String, start: Double, end: Double) {
        val i = Intent(Intent.ACTION_INSERT)
            .setData(CalendarContract.Events.CONTENT_URI)
            .putExtra(CalendarContract.Events.TITLE, title)
            .putExtra(CalendarContract.EXTRA_EVENT_BEGIN_TIME, start.toLong())
            .putExtra(CalendarContract.EXTRA_EVENT_END_TIME, end.toLong())
            .putExtra(CalendarContract.Events.DESCRIPTION, "Added by Zuffi 🐰")
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

    /** Zuffi the bunny walking on the screen (shows reminders). */
    @JavascriptInterface fun setPet(on: Boolean) {
        val sp = Prefs.sp(a)
        val e = sp.edit().putBoolean("pet", on)
        if (on && !sp.contains("chargeLight")) e.putBoolean("chargeLight", true)
        e.apply()
        a.runOnUiThread {
            if (on && !Settings.canDrawOverlays(a)) Commands.startSafely(a, Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:" + a.packageName)))
            else PetService.refresh(a)
        }
    }
    /** The light round the screen edge when the phone is plugged in. */
    @JavascriptInterface fun setChargeLight(on: Boolean) {
        Prefs.sp(a).edit().putBoolean("chargeLight", on).apply()
        a.runOnUiThread {
            if (on && !Settings.canDrawOverlays(a)) Commands.startSafely(a, Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:" + a.packageName)))
            else PetService.refresh(a)
        }
    }
    @JavascriptInterface fun nativeCharge(): Boolean = PetService.running && Prefs.sp(a).getBoolean("chargeLight", false)
    @JavascriptInterface fun petSay(text: String) { a.runOnUiThread { PetService.say(a, text) } }

    @JavascriptInterface fun setReadNotifications(on: Boolean) {
        Prefs.sp(a).edit().putBoolean("readNotifs", on).apply()
        if (on && !hasNotificationAccess()) a.runOnUiThread {
            Commands.startSafely(a, Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
        }
    }

    private fun hasNotificationAccess() =
        NotificationManagerCompat.getEnabledListenerPackages(a).contains(a.packageName)

    /** Business info for WhatsApp replies (from Settings → WhatsApp on this phone). */
    @JavascriptInterface fun setBusiness(json: String) {
        val o = try { org.json.JSONObject(json) } catch (e: Exception) { return }
        val e = Prefs.sp(a).edit()
        for (k in listOf("bizName", "bizInfo", "bizToday", "bizTodayDate", "groqKey", "geminiKey")) if (o.has(k)) e.putString(k, o.optString(k))
        if (o.has("waLeads")) e.putBoolean("waLeads", o.optBoolean("waLeads"))
        if (o.has("waPilot")) e.putBoolean("waPilot", o.optBoolean("waPilot"))
        if (o.has("waContactsToo")) e.putBoolean("waContactsToo", o.optBoolean("waContactsToo"))
        e.apply()
        if ((o.optBoolean("waLeads") || o.optBoolean("waPilot")) && !hasNotificationAccess()) a.runOnUiThread {
            try { a.startActivity(android.content.Intent("android.settings.ACTION_NOTIFICATION_LISTENER_SETTINGS")) } catch (_: Exception) {}
        }
    }

    @JavascriptInterface fun waLeads(): String = WhatsAppPilot.leads(a).toString()
    @JavascriptInterface fun waClear() { Prefs.sp(a).edit().putString("waLeadList", "[]").apply() }
    @JavascriptInterface fun hasNotifAccess(): Boolean = hasNotificationAccess()

    @JavascriptInterface fun status(): String {
        val sp = Prefs.sp(a)
        // Start the bubble once overlay permission was granted in Settings
        if (sp.getBoolean("bubble", false) && Settings.canDrawOverlays(a) && !BubbleService.running) {
            a.runOnUiThread { a.startForegroundService(Intent(a, BubbleService::class.java)) }
        }
        if ((sp.getBoolean("pet", false) || sp.getBoolean("chargeLight", false)) && Settings.canDrawOverlays(a) && !PetService.running) {
            a.runOnUiThread { PetService.refresh(a) }
        }
        return JSONObject()
            .put("pet", sp.getBoolean("pet", false))
            .put("chargeLight", sp.getBoolean("chargeLight", false))
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
