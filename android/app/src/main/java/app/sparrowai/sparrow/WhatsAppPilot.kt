package app.sparrowai.sparrow

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.RemoteInput
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.service.notification.StatusBarNotification
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * WhatsApp on this phone → leads + replies, even with the phone in your pocket.
 * Android lets an app with "Notification access" read a notification and answer it with the
 * notification's own Reply button (the same thing a smartwatch does). No WhatsApp login, no Meta setup.
 *  - every new chat is saved as a lead (name + message), visible in Zuffi → WhatsApp
 *  - with Autopilot on, Zuffi answers using your business info and today's update
 *  - bargaining, complaints, "call me", or anything it doesn't know → it doesn't guess: it tells you
 */
object WhatsAppPilot {
    private val packages = setOf("com.whatsapp", "com.whatsapp.w4b")
    private var lastKey = ""
    private var lastAt = 0L
    private const val CHANNEL = "zuffi_whatsapp"

    fun isWhatsApp(pkg: String) = pkg in packages

    fun handle(c: Context, sbn: StatusBarNotification) {
        val sp = Prefs.sp(c)
        if (!sp.getBoolean("waLeads", false) && !sp.getBoolean("waPilot", false)) return
        val n = sbn.notification
        if ((n.flags and Notification.FLAG_GROUP_SUMMARY) != 0) return
        val ex = n.extras
        if (ex.getBoolean(Notification.EXTRA_IS_GROUP_CONVERSATION, false)) return
        // The newest message in the chat (MessagingStyle), else the plain text.
        var sender = ex.getCharSequence(Notification.EXTRA_TITLE)?.toString().orEmpty()
        var text = ex.getCharSequence(Notification.EXTRA_TEXT)?.toString().orEmpty()
        val msgs = ex.getParcelableArray(Notification.EXTRA_MESSAGES)
        if (msgs != null && msgs.isNotEmpty()) {
            (msgs.last() as? Bundle)?.let { b ->
                b.getCharSequence("text")?.toString()?.let { text = it }
                b.getCharSequence("sender")?.toString()?.takeIf { it.isNotBlank() }?.let { sender = it }
            }
        }
        if (sender.isBlank() || text.isBlank()) return
        if (Regex("(?i)^(whatsapp|whatsapp business)$").matches(sender)) return
        if (Regex("(?i)\\d+ new messages|checking for new messages|^(you|aap)$").containsMatchIn(text + " " + sender)) return
        if (sender.contains(" @ ") || Regex("^[^:]{1,30}:\\s").containsMatchIn(text)) return   // a group chat line
        val key = sender + "|" + text
        val now = System.currentTimeMillis()
        if (key == lastKey && now - lastAt < 60_000) return
        lastKey = key; lastAt = now

        val voice = Regex("(?i)voice message|🎤|audio").containsMatchIn(text)
        val lead = saveLead(c, sender, text)
        if (!sp.getBoolean("waPilot", false) || voice) {
            if (voice && sp.getBoolean("waPilot", false)) notifyOwner(c, "$sender sent a voice note", "Open WhatsApp to listen — I can't hear voice notes from a notification.")
            return
        }
        // Max 12 automatic replies a day to the same person.
        val countKey = "waCount|" + sender + "|" + SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())
        val count = sp.getInt(countKey, 0)
        if (count >= 12) return
        val reply = n.actions?.firstOrNull { a -> a.remoteInputs?.isNotEmpty() == true && (a.title?.toString()?.contains("reply", true) == true || a.remoteInputs.size == 1) }
            ?: Notification.WearableExtender(n).actions.firstOrNull { it.remoteInputs?.isNotEmpty() == true }
        Thread {
            val r = think(c, sender, text, lead.optJSONArray("history"))
            if (r == null) { notifyOwner(c, "New WhatsApp: $sender", text.take(120)); return@Thread }
            if (r.second != null) {
                updateLead(c, sender, r.first, "needs you: ${r.second}")
                notifyOwner(c, "$sender needs you", r.second!!)
                return@Thread
            }
            if (reply == null) { updateLead(c, sender, r.first, "draft (no reply button)"); notifyOwner(c, "Reply ready for $sender", r.first); return@Thread }
            if (send(c, reply, r.first)) {
                sp.edit().putInt(countKey, count + 1).apply()
                updateLead(c, sender, r.first, "sent")
            } else updateLead(c, sender, r.first, "draft")
        }.start()
    }

    private fun send(c: Context, action: Notification.Action, text: String): Boolean = try {
        val intent = Intent()
        val results = Bundle()
        for (ri in action.remoteInputs) results.putCharSequence(ri.resultKey, text)
        RemoteInput.addResultsToIntent(action.remoteInputs, intent, results)
        action.actionIntent.send(c, 0, intent)
        true
    } catch (e: Exception) { false }

    // ---------- leads stored on the phone ----------

    fun leads(c: Context): JSONArray = try { JSONArray(Prefs.sp(c).getString("waLeadList", "[]")) } catch (e: Exception) { JSONArray() }

    private fun saveLead(c: Context, sender: String, text: String): JSONObject {
        val list = leads(c)
        val stamp = SimpleDateFormat("yyyy-MM-dd HH:mm", Locale.US).format(Date())
        var found: JSONObject? = null
        for (i in 0 until list.length()) if (list.getJSONObject(i).optString("name") == sender) { found = list.getJSONObject(i); break }
        val lead = found ?: JSONObject().put("name", sender).put("added", stamp).put("history", JSONArray()).also { list.put(it) }
        lead.put("last", text).put("at", stamp)
        lead.getJSONArray("history").put(JSONObject().put("in", text).put("at", stamp))
        trim(lead.getJSONArray("history"), 12)
        store(c, list)
        return lead
    }

    private fun updateLead(c: Context, sender: String, reply: String, status: String) {
        val list = leads(c)
        for (i in 0 until list.length()) {
            val l = list.getJSONObject(i)
            if (l.optString("name") == sender) {
                l.put("reply", reply).put("status", status)
                if (status == "sent") l.getJSONArray("history").put(JSONObject().put("out", reply))
                trim(l.getJSONArray("history"), 12)
            }
        }
        store(c, list)
    }

    private fun trim(a: JSONArray, max: Int) { while (a.length() > max) a.remove(0) }
    private fun store(c: Context, list: JSONArray) {
        while (list.length() > 300) list.remove(0)
        Prefs.sp(c).edit().putString("waLeadList", list.toString()).apply()
    }

    // ---------- the reply ----------

    /** (reply, handoff reason or null). null = no AI key / no answer. */
    private fun think(c: Context, sender: String, text: String, history: JSONArray?): Pair<String, String?>? {
        val sp = Prefs.sp(c)
        val biz = sp.getString("bizName", "").orEmpty()
        val info = sp.getString("bizInfo", "").orEmpty()
        val today = if (sp.getString("bizTodayDate", "") == SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())) sp.getString("bizToday", "").orEmpty() else ""
        val past = StringBuilder()
        if (history != null) for (i in 0 until history.length() - 1) {
            val h = history.getJSONObject(i)
            if (h.has("in")) past.append("Client: ").append(h.optString("in")).append('\n')
            if (h.has("out")) past.append("Business: ").append(h.optString("out")).append('\n')
        }
        val system = "You are the WhatsApp assistant of ${biz.ifBlank { "a small business" }}. You write as the business (\"we\"). " +
            "Never give yourself a personal name, never say you are an AI, never invent facts. Reply with one JSON object only."
        val prompt = """
            BUSINESS FACTS (the only facts you may use):
            ${info.ifBlank { "(none written yet — greet politely and ask how you can help)" }.take(5000)}
            ${if (today.isNotBlank()) "TODAY'S UPDATE: $today" else ""}
            CLIENT: $sender
            ${if (past.isNotEmpty()) "EARLIER IN THIS CHAT:\n$past" else ""}
            CLIENT'S NEW MESSAGE: $text

            Write "reply": 1-2 short natural WhatsApp sentences in the client's own language and script (English, Urdu or Roman Urdu).
            Set "needs_human" true ONLY if they bargain or ask for a discount not in today's update, complain, ask for a person or a call,
            raise payment / refund / legal issues, or the answer isn't in the facts. Then "reply" is a short holding message and "why" a 3-6 word reason.
            JSON: {"reply":"","needs_human":false,"why":""}
        """.trimIndent()
        val groq = sp.getString("groqKey", "").orEmpty()
        val gemini = sp.getString("geminiKey", "").orEmpty()
        val raw = when {
            groq.isNotBlank() -> post("https://api.groq.com/openai/v1/chat/completions", mapOf("Authorization" to "Bearer $groq"),
                JSONObject().put("model", "llama-3.3-70b-versatile").put("temperature", 0.3).put("max_tokens", 400)
                    .put("response_format", JSONObject().put("type", "json_object"))
                    .put("messages", JSONArray().put(JSONObject().put("role", "system").put("content", system)).put(JSONObject().put("role", "user").put("content", prompt))))
                ?.let { JSONObject(it).getJSONArray("choices").getJSONObject(0).getJSONObject("message").getString("content") }
            gemini.isNotBlank() -> post("https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent", mapOf("x-goog-api-key" to gemini),
                JSONObject().put("system_instruction", JSONObject().put("parts", JSONArray().put(JSONObject().put("text", system))))
                    .put("contents", JSONArray().put(JSONObject().put("role", "user").put("parts", JSONArray().put(JSONObject().put("text", prompt)))))
                    .put("generationConfig", JSONObject().put("temperature", 0.3).put("responseMimeType", "application/json")))
                ?.let { JSONObject(it).getJSONArray("candidates").getJSONObject(0).getJSONObject("content").getJSONArray("parts").getJSONObject(0).getString("text") }
            else -> null
        } ?: return null
        val j = firstJson(raw) ?: return null
        val reply = j.optString("reply").trim()
        if (reply.isBlank() || reply.startsWith("{") || reply.contains("\"reply\"")) return null
        val human = j.optBoolean("needs_human", false) || j.optString("needs_human") == "true"
        val why = j.optString("why").trim()
        return reply to (if (human) why.ifBlank { "needs a person" } else null)
    }

    private fun firstJson(s: String): JSONObject? {
        val a = s.indexOf('{'); if (a < 0) return null
        var depth = 0; var inStr = false; var esc = false
        for (i in a until s.length) {
            val ch = s[i]
            if (inStr) { if (esc) esc = false else if (ch == '\\') esc = true else if (ch == '"') inStr = false; continue }
            if (ch == '"') inStr = true else if (ch == '{') depth++ else if (ch == '}' && --depth == 0) {
                return try { JSONObject(s.substring(a, i + 1)) } catch (e: Exception) { null }
            }
        }
        return null
    }

    private fun post(url: String, headers: Map<String, String>, body: JSONObject): String? = try {
        val conn = URL(url).openConnection() as HttpURLConnection
        conn.requestMethod = "POST"; conn.connectTimeout = 10_000; conn.readTimeout = 20_000; conn.doOutput = true
        conn.setRequestProperty("Content-Type", "application/json")
        headers.forEach { (k, v) -> conn.setRequestProperty(k, v) }
        conn.outputStream.use { it.write(body.toString().toByteArray()) }
        if (conn.responseCode in 200..299) conn.inputStream.bufferedReader().use { it.readText() } else null
    } catch (e: Exception) { null }

    private fun notifyOwner(c: Context, title: String, text: String) {
        val nm = c.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26) nm.createNotificationChannel(NotificationChannel(CHANNEL, "WhatsApp leads", NotificationManager.IMPORTANCE_HIGH))
        val open = PendingIntent.getActivity(c, 7, Intent(c, MainActivity::class.java).putExtra("open", "whatsapp").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val n = Notification.Builder(c, CHANNEL).setSmallIcon(R.drawable.ic_stat).setContentTitle(title).setContentText(text)
            .setStyle(Notification.BigTextStyle().bigText(text)).setContentIntent(open).setAutoCancel(true).build()
        nm.notify((title + text).hashCode(), n)
    }
}
