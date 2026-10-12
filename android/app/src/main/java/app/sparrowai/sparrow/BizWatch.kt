package app.sparrowai.sparrow

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.service.notification.StatusBarNotification
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Zuffi Business on the phone, beyond the chats themselves:
 *  • WhatsApp group posts that look like property listings → stock (read only, never replies in groups)
 *  • missed calls → a lead + a ready WhatsApp reply
 *  • speed-to-lead: buzz at 5 min, again at 15 min, if a new enquiry is still unanswered
 *  • a 10-second "Stop" before every automatic reply
 */
object BizWatch {
    private const val CHANNEL = "zuffi_biz"
    private val main = Handler(Looper.getMainLooper())
    private val pending = mutableMapOf<Int, Runnable>()

    fun on(c: Context, k: String, def: Boolean = false) = Prefs.sp(c).getBoolean("biz_$k", def)
    private fun stamp() = SimpleDateFormat("yyyy-MM-dd HH:mm", Locale.US).format(Date())

    /** What the web app shows in More → This phone. */
    fun status(c: Context): String {
        val sp = Prefs.sp(c)
        val o = JSONObject()
        for (k in listOf("speedAlarm", "missedCall", "groupListings", "workCharging", "hub")) o.put(k, sp.getBoolean("biz_$k", false))
        o.put("undo", sp.getBoolean("biz_undo", true))
        o.put("petSize", sp.getString("petSize", "medium")).put("petMode", sp.getString("petMode", "walk"))
        return o.toString()
    }
    fun set(c: Context, json: String) {
        val o = try { JSONObject(json) } catch (_: Exception) { return }
        val e = Prefs.sp(c).edit()
        for (k in listOf("speedAlarm", "missedCall", "groupListings", "workCharging", "hub", "undo")) if (o.has(k)) e.putBoolean("biz_$k", o.optBoolean(k))
        for (k in listOf("petSize", "petMode", "missedText")) if (o.has(k)) e.putString(k, o.optString(k))
        // These need Zuffi reading WhatsApp notifications too
        if (o.optBoolean("groupListings") || o.optBoolean("speedAlarm") || o.optBoolean("hub")) e.putBoolean("waLeads", true)
        e.apply()
        PetService.refresh(c)
    }

    // ───────────────────────── WhatsApp group posts → listings ─────────────────────────

    private val LISTING = Regex("(?i)\\b(marla|kanal|sq\\.? ?ft|sqft|sq yd|square feet|plot|house|flat|apartment|shop|file|portion|villa|bed(room)?s?|bhk|studio)\\b")
    private val PRICE = Regex("(?i)(?:demand|price|rent|asking|dem|rs\\.?|pkr|£|aed|₹)?\\s*(\\d+(?:[.,]\\d+)?)\\s*(crore|cr|lakh|lac|lacs|lakhs|k|million|m)\\b|(?:rs\\.?|pkr|£|aed|₹)\\s?(\\d[\\d,]{3,})")
    private val SIZE = Regex("(?i)(\\d+(?:\\.\\d+)?)\\s*(marla|kanal|sq\\.? ?ft|sqft|sq yd|bed(?:room)?s?|bhk)")
    private val AREA = Regex("(?i)\\b(dha|bahria|gulberg|johar town|model town|defence|clifton|f-?\\d+|g-?\\d+|e-?\\d+|i-?\\d+|phase\\s*\\d+|sector\\s*[a-z0-9-]+|block\\s*[a-z0-9-]+|[A-Z][a-z]+ (?:Town|City|Gardens|Enclave|Valley|Housing))\\b[^,\\n]{0,24}")
    private val PHONE = Regex("(\\+?\\d[\\d\\s-]{8,14}\\d)")

    fun groupPost(c: Context, group: String, sender: String, text: String) {
        if (!on(c, "groupListings")) return
        if (text.length < 15 || !LISTING.containsMatchIn(text) || !PRICE.containsMatchIn(text)) return
        val list = listings(c)
        val key = text.take(60)
        for (i in 0 until list.length()) if (list.getJSONObject(i).optString("text").take(60) == key) return
        val size = SIZE.find(text)?.value.orEmpty()
        val price = PRICE.find(text)?.value?.replace(Regex("(?i)^(demand|price|rent|asking|dem)\\s*:?\\s*"), "")?.trim().orEmpty()
        val type = Regex("(?i)\\b(plot|house|flat|apartment|shop|file|portion|villa|office|studio)\\b").find(text)?.value?.replaceFirstChar { it.uppercase() }.orEmpty()
        val purpose = if (Regex("(?i)\\b(rent|to let|for rent|monthly)\\b").containsMatchIn(text)) "Rent" else "Sale"
        list.put(JSONObject().put("group", group).put("sender", sender).put("text", text.take(600)).put("at", stamp())
            .put("size", size).put("price", price).put("type", type).put("purpose", purpose)
            .put("area", AREA.find(text)?.value?.trim().orEmpty()).put("phone", PHONE.find(text)?.value?.replace(Regex("[\\s-]"), "").orEmpty()))
        while (list.length() > 300) list.remove(0)
        Prefs.sp(c).edit().putString("waListings", list.toString()).apply()
    }
    fun listings(c: Context): JSONArray = try { JSONArray(Prefs.sp(c).getString("waListings", "[]")) } catch (_: Exception) { JSONArray() }
    fun clearListings(c: Context) { Prefs.sp(c).edit().putString("waListings", "[]").apply() }

    // ───────────────────────── missed call → WhatsApp ─────────────────────────

    private val DIALERS = setOf("com.google.android.dialer", "com.android.dialer", "com.samsung.android.dialer", "com.samsung.android.incallui",
        "com.android.server.telecom", "com.android.phone", "com.android.incallui", "com.oneplus.dialer", "com.miui.securitycenter", "com.android.contacts",
        "com.transsion.contacts", "com.coloros.phonemanager", "com.oplus.dialer", "com.asus.contacts", "com.motorola.dialer")

    fun maybeMissedCall(c: Context, sbn: StatusBarNotification): Boolean {
        val n = sbn.notification
        val ex = n.extras
        val title = ex.getCharSequence(Notification.EXTRA_TITLE)?.toString().orEmpty()
        val text = ex.getCharSequence(Notification.EXTRA_TEXT)?.toString().orEmpty()
        val missed = (android.os.Build.VERSION.SDK_INT >= 31 && n.category == Notification.CATEGORY_MISSED_CALL) ||
            (sbn.packageName in DIALERS && Regex("(?i)missed call|missed|مس کال|ছুটে|nicht angenommen|appel manqué").containsMatchIn("$title $text"))
        if (!missed || !on(c, "missedCall")) return missed
        // The caller is whichever line isn't the words "missed call"
        val who = listOf(title, text).map { it.replace(Regex("(?i)\\d+ missed calls?|missed calls?( from)?|:"), "").trim() }.firstOrNull { it.isNotBlank() }.orEmpty()
        if (who.isBlank()) return true
        val phone = PHONE.find("$title $text")?.value?.replace(Regex("[\\s-]"), "").orEmpty()
        val key = "missed|$who|" + stamp().take(15)
        val sp = Prefs.sp(c)
        if (sp.getString("lastMissed", "") == key) return true
        sp.edit().putString("lastMissed", key).apply()
        WhatsAppPilot.addLead(c, who, phone, "📞 Missed call", "Missed call")
        val msg = sp.getString("missedText", "").orEmpty().ifBlank { "Sorry I missed your call — I'm with a client. How can I help? 🙂" }
        val target = phone.ifBlank { who.filter { it.isDigit() || it == '+' } }
        if (target.count { it.isDigit() } >= 9) {
            val url = "https://wa.me/" + target.trimStart('+').let { if (it.startsWith("0") && it.length == 11) "92" + it.drop(1) else it } + "?text=" + Uri.encode(msg)
            notify(c, "Missed call from $who", "Tap to send: “${msg.take(60)}”", Intent(Intent.ACTION_VIEW, Uri.parse(url)))
        } else notify(c, "Missed call from $who", "Saved as a lead. Open WhatsApp to send: “${msg.take(60)}”", null)
        PetService.island(c, "📞 Missed call", "$who — tap to WhatsApp them")
        return true
    }

    // ───────────────────────── speed-to-lead ─────────────────────────

    /** Called every minute by PetService. */
    fun checkWaiting(c: Context) {
        if (!on(c, "speedAlarm")) return
        val list = WhatsAppPilot.leads(c)
        val now = System.currentTimeMillis()
        var changed = false
        for (i in 0 until list.length()) {
            val l = list.getJSONObject(i)
            val inAt = l.optLong("inAt", 0L)
            if (inAt == 0L || l.optBoolean("answered") || l.optString("status") == "sent") continue
            val mins = (now - inAt) / 60000
            if (mins > 24 * 60) continue
            val told = l.optInt("told", 0)
            val stage = if (mins >= 15) 15 else if (mins >= 5) 5 else 0
            if (stage == 0 || told >= stage) continue
            l.put("told", stage); changed = true
            val name = l.optString("name")
            val head = if (stage == 15) "⏱️ $name has waited $mins min" else "⏱️ $name is waiting for a reply"
            val body = if (stage == 15) "Reply now or they'll go elsewhere: “${l.optString("last").take(60)}”" else "“${l.optString("last").take(80)}”"
            notify(c, head, body, c.packageManager.getLaunchIntentForPackage("com.whatsapp") ?: c.packageManager.getLaunchIntentForPackage("com.whatsapp.w4b"))
            PetService.island(c, head, body)
        }
        if (changed) Prefs.sp(c).edit().putString("waLeadList", list.toString()).apply()
    }

    // ───────────────────────── 10-second undo before auto-replies ─────────────────────────

    fun sendWithUndo(c: Context, who: String, text: String, send: () -> Unit) {
        if (!on(c, "undo", true)) { send(); return }
        val id = (who + text).hashCode()
        val r = Runnable { pending.remove(id); cancel(c, id); send() }
        pending[id] = r
        val stop = PendingIntent.getBroadcast(c, id, Intent(c, StopReplyReceiver::class.java).putExtra("id", id), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        channel(c)
        val n = Notification.Builder(c, CHANNEL).setSmallIcon(R.drawable.ic_stat).setContentTitle("Replying to $who in 10 s")
            .setContentText(text).setStyle(Notification.BigTextStyle().bigText(text)).setOngoing(true).setTimeoutAfter(11_000)
            .addAction(Notification.Action.Builder(null as android.graphics.drawable.Icon?, "Stop", stop).build()).build()
        try { c.getSystemService(NotificationManager::class.java).notify(id, n) } catch (_: SecurityException) {}
        main.postDelayed(r, 10_000)
    }
    fun stop(c: Context, id: Int) { pending.remove(id)?.let { main.removeCallbacks(it) }; cancel(c, id) }
    private fun cancel(c: Context, id: Int) { try { c.getSystemService(NotificationManager::class.java).cancel(id) } catch (_: Exception) {} }

    // ───────────────────────── helpers ─────────────────────────

    private fun channel(c: Context) {
        c.getSystemService(NotificationManager::class.java).createNotificationChannel(NotificationChannel(CHANNEL, "Business alerts", NotificationManager.IMPORTANCE_HIGH))
    }
    fun notify(c: Context, title: String, text: String, tap: Intent?) {
        channel(c)
        val intent = tap ?: Intent(c, MainActivity::class.java).putExtra("open", "whatsapp")
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        val pi = PendingIntent.getActivity(c, (title + text).hashCode(), intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val n = Notification.Builder(c, CHANNEL).setSmallIcon(R.drawable.ic_stat).setContentTitle(title).setContentText(text)
            .setStyle(Notification.BigTextStyle().bigText(text)).setContentIntent(pi).setAutoCancel(true).build()
        try { c.getSystemService(NotificationManager::class.java).notify((title + text).hashCode(), n) } catch (_: SecurityException) {}
    }
}

class StopReplyReceiver : BroadcastReceiver() {
    override fun onReceive(c: Context, i: Intent) { BizWatch.stop(c, i.getIntExtra("id", 0)) }
}
