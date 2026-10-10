package app.sparrowai.sparrow

import android.content.Context
import android.content.Intent
import android.media.AudioManager
import android.media.ToneGenerator
import android.net.Uri
import android.os.Handler
import android.os.Looper

/** Runs a spoken command. Simple ones happen right away; everything else goes to the app. */
object Commands {
    private val main = Handler(Looper.getMainLooper())

    fun chirp() {
        try {
            val tg = ToneGenerator(AudioManager.STREAM_NOTIFICATION, 70)
            tg.startTone(ToneGenerator.TONE_PROP_BEEP2, 140)
            main.postDelayed({ tg.release() }, 400)
        } catch (_: Exception) {}
    }

    fun run(c: Context, raw: String) {
        val t = raw.lowercase().trim().trim('.', '!', '?', ',')
        if (t.isEmpty()) return
        // open / launch an app
        Regex("^(?:open|launch|start|run|show me)\\s+(.+)$").find(t)?.let { m ->
            val name = m.groupValues[1]
            val opened = Apps.open(c, name)
            if (opened != null) { chirp(); return }
            Speaker.speak("I couldn't find $name on your phone.")
            return
        }
        // call a number
        Regex("^(?:call|ring|phone)\\s+([+\\d][\\d\\s()-]{5,})$").find(t)?.let { m ->
            val num = m.groupValues[1].filter { it.isDigit() || it == '+' }
            startSafely(c, Intent(Intent.ACTION_DIAL, Uri.parse("tel:$num")))
            return
        }
        // directions
        Regex("^(?:directions|navigate|take me|route) to\\s+(.+)$").find(t)?.let { m ->
            startSafely(c, Intent(Intent.ACTION_VIEW, Uri.parse("google.navigation:q=" + Uri.encode(m.groupValues[1]))))
            return
        }
        // everything else (reminders, meetings, tasks, questions…) → the Sparrow app
        val i = Intent(c, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            .putExtra("ask", raw).putExtra("voice", true)
        val started = startSafely(c, i)
        // Android only lets apps pop up from the background when "display over other apps" is allowed
        if (!started || !android.provider.Settings.canDrawOverlays(c)) Notifs.answer(c, raw)
    }

    fun startFgSafely(c: Context, i: Intent): Boolean =
        try { c.startForegroundService(i); true } catch (e: Exception) { false }

    fun startSafely(c: Context, i: Intent): Boolean {
        i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return try { c.startActivity(i); true } catch (e: Exception) { false }
    }
}
