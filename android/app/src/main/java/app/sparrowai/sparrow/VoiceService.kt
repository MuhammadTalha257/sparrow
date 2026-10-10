package app.sparrowai.sparrow

import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import org.json.JSONObject
import org.vosk.Model
import org.vosk.Recognizer
import org.vosk.android.RecognitionListener
import org.vosk.android.SpeechService
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.util.zip.ZipInputStream

/**
 * Always-on "Sparrow…" listening, fully offline (Vosk speech model, ~40 MB, downloaded once).
 * Android shows a small notification while this runs.
 */
class VoiceService : Service(), RecognitionListener {
    private var model: Model? = null
    private var speech: SpeechService? = null
    private var awaiting = false
    private val main = Handler(Looper.getMainLooper())

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        val n = Notifs.service(this, "Say “Zuffi…” anytime")
        if (Build.VERSION.SDK_INT >= 30) startForeground(2, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE)
        else startForeground(2, n)
        running = true
        Thread { start() }.start()
    }

    private fun setStatus(text: String) {
        getSystemService(NotificationManager::class.java).notify(2, Notifs.service(this, text))
    }

    private fun start() {
        try {
            val dir = ModelFiles.ensure(this) { setStatus(it) }
            if (dir == null) { setStatus("Couldn't download the voice model — check internet"); return }
            val m = Model(dir.absolutePath)
            model = m
            val rec = Recognizer(m, 16000f)
            val s = SpeechService(rec, 16000f)
            speech = s
            s.startListening(this)
            setStatus("Say “Zuffi…” anytime")
        } catch (e: Exception) {
            Log.e("Sparrow", "voice start failed", e)
            setStatus("Voice listening stopped: ${e.message}")
        }
    }

    override fun onPartialResult(hypothesis: String?) {}
    override fun onResult(hypothesis: String?) { handle(hypothesis) }
    override fun onFinalResult(hypothesis: String?) { handle(hypothesis) }
    override fun onError(exception: Exception?) {
        Log.e("Sparrow", "voice error", exception)
        main.postDelayed({ try { speech?.startListening(this) } catch (_: Exception) {} }, 1500)
    }
    override fun onTimeout() { try { speech?.startListening(this) } catch (_: Exception) {} }

    private fun handle(json: String?) {
        val text = try { JSONObject(json ?: "{}").optString("text") } catch (e: Exception) { "" }.trim()
        if (text.isEmpty()) return
        val lower = text.lowercase()
        val wake = listOf("zuffi", "zuffy", "zoffy", "zoffi", "suffi", "sufi", "zuffie", "zophie", "sophie", "sparrow")
            .map { lower.lastIndexOf(it) to it }.filter { it.first >= 0 }.maxByOrNull { it.first }
        val cmd: String? = when {
            wake != null -> lower.substring(wake.first + wake.second.length).trim(' ', ',', '.')
            awaiting -> lower
            else -> null
        } ?: return
        main.post {
            if (cmd.isNullOrEmpty()) {
                awaiting = true
                Commands.chirp()
                BubbleService.pulse()
                main.postDelayed({ awaiting = false }, 8000)
            } else {
                awaiting = false
                BubbleService.pulse()
                Commands.run(this, cmd)
            }
        }
    }

    override fun onDestroy() {
        running = false
        try { speech?.stop(); speech?.shutdown() } catch (_: Exception) {}
        try { model?.close() } catch (_: Exception) {}
        super.onDestroy()
    }

    companion object {
        @Volatile var running = false
    }
}

/** Downloads & unpacks the small English Vosk model the first time. */
object ModelFiles {
    private const val NAME = "vosk-model-small-en-us-0.15"
    private const val URL_ZIP = "https://alphacephei.com/vosk/models/$NAME.zip"

    fun ensure(c: Context, progress: (String) -> Unit): File? {
        val dir = File(c.filesDir, NAME)
        if (File(dir, "am").exists() || File(dir, "conf").exists()) return dir
        return try {
            progress("Downloading voice model (40 MB, once)…")
            val zip = File(c.cacheDir, "$NAME.zip")
            val conn = URL(URL_ZIP).openConnection() as HttpURLConnection
            conn.connectTimeout = 15000; conn.readTimeout = 30000
            conn.inputStream.use { input -> zip.outputStream().use { input.copyTo(it) } }
            progress("Unpacking voice model…")
            ZipInputStream(zip.inputStream()).use { zin ->
                var e = zin.nextEntry
                while (e != null) {
                    val out = File(c.filesDir, e.name)
                    if (!out.canonicalPath.startsWith(c.filesDir.canonicalPath)) throw SecurityException("bad zip")
                    if (e.isDirectory) out.mkdirs() else { out.parentFile?.mkdirs(); out.outputStream().use { zin.copyTo(it) } }
                    e = zin.nextEntry
                }
            }
            zip.delete()
            dir
        } catch (e: Exception) {
            Log.e("Sparrow", "model download failed", e); null
        }
    }
}
