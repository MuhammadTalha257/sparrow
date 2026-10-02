package app.sparrowai.sparrow

import android.content.Context
import android.content.Intent

/** Finds and opens any installed app by name ("open whatsapp"). */
object Apps {
    data class App(val label: String, val pkg: String)

    private val aliases = mapOf(
        "gallery" to "photos", "pictures" to "photos", "messages" to "messages", "texts" to "messages",
        "dialer" to "phone", "calls" to "phone", "browser" to "chrome", "google chrome" to "chrome",
        "play store" to "play store", "app store" to "play store", "insta" to "instagram", "fb" to "facebook",
        "what's app" to "whatsapp", "whats app" to "whatsapp", "you tube" to "youtube", "mail" to "gmail",
        "email" to "gmail", "music" to "spotify", "sms" to "messages", "x" to "x", "twitter" to "x",
    )

    fun list(c: Context): List<App> {
        val pm = c.packageManager
        val i = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        return pm.queryIntentActivities(i, 0)
            .map { App(it.loadLabel(pm).toString(), it.activityInfo.packageName) }
            .filter { it.pkg != c.packageName }
            .distinctBy { it.pkg }
            .sortedBy { it.label.lowercase() }
    }

    fun find(c: Context, query: String): App? {
        var s = query.lowercase().trim().trim('.', '!', '?')
        listOf("the ", "my ").forEach { if (s.startsWith(it)) s = s.removePrefix(it) }
        listOf(" app", " application").forEach { if (s.endsWith(it)) s = s.removeSuffix(it) }
        s = aliases[s] ?: s
        if (s.isEmpty()) return null
        val all = list(c)
        val squash = s.replace(" ", "")
        return all.firstOrNull { it.label.lowercase() == s }
            ?: all.firstOrNull { it.label.lowercase().replace(" ", "") == squash }
            ?: all.firstOrNull { it.label.lowercase().startsWith(s) }
            ?: all.firstOrNull { s.length >= 3 && it.label.lowercase().contains(s) }
            ?: all.firstOrNull { squash.length >= 4 && it.pkg.lowercase().contains(squash) }
    }

    fun launch(c: Context, pkg: String): Boolean {
        val i = c.packageManager.getLaunchIntentForPackage(pkg) ?: return false
        i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return try { c.startActivity(i); true } catch (e: Exception) { false }
    }

    /** Returns the app's name if it was opened, otherwise null. */
    fun open(c: Context, query: String): String? {
        val a = find(c, query) ?: return null
        return if (launch(c, a.pkg)) a.label else null
    }
}
