package app.sparrowai.sparrow

import android.content.Context
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import java.util.Locale

/** Text-to-speech with a female / male choice. */
object Speaker : TextToSpeech.OnInitListener {
    private var tts: TextToSpeech? = null
    private var ready = false
    private val pending = mutableListOf<String>()
    var gender = "female"
    var onSpeaking: ((Boolean) -> Unit)? = null

    fun init(c: Context) {
        if (tts == null) tts = TextToSpeech(c.applicationContext, this)
        gender = Prefs.sp(c).getString("gender", "female") ?: "female"
    }

    override fun onInit(status: Int) {
        ready = status == TextToSpeech.SUCCESS
        if (!ready) return
        tts?.language = Locale.getDefault()
        tts?.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
            override fun onStart(utteranceId: String?) { onSpeaking?.invoke(true) }
            override fun onDone(utteranceId: String?) { onSpeaking?.invoke(false) }
            @Deprecated("Deprecated in Java")
            override fun onError(utteranceId: String?) { onSpeaking?.invoke(false) }
        })
        applyVoice()
        pending.forEach { speak(it) }
        pending.clear()
    }

    fun applyVoice() {
        val t = tts ?: return
        if (!ready) return
        val lang = Locale.getDefault().language
        val voices = try {
            t.voices?.filter { it.locale.language == lang && !it.isNetworkConnectionRequired }.orEmpty()
        } catch (e: Exception) { emptyList() }
        // Google TTS voice ids: these are the male ones; everything else is female.
        val maleHints = listOf("-rjs-", "-gbd-", "-iol-", "-iom-", "-tpd-", "-tpf-", "-sfg-", "-ahd-", "-bmh-")
        val pick = voices.sortedByDescending { it.quality }.firstOrNull { v ->
            val male = maleHints.any { v.name.contains(it, ignoreCase = true) } ||
                (v.name.contains("male", true) && !v.name.contains("female", true))
            if (gender == "male") male else !male
        }
        if (pick != null) t.voice = pick
        t.setPitch(if (gender == "male") 0.92f else 1.05f)
        t.setSpeechRate(1.0f)
    }

    fun speak(text: String) {
        val clean = text.replace(Regex("[\\p{So}\\p{Cn}•]"), "").trim()
        if (clean.isEmpty()) return
        val t = tts
        if (!ready || t == null) { pending += clean; return }
        t.speak(clean, TextToSpeech.QUEUE_FLUSH, null, "sp" + System.currentTimeMillis())
    }

    fun stop() { tts?.stop() }
}
