package app.sparrowai.sparrow

import android.animation.ObjectAnimator
import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.app.Service
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.graphics.PixelFormat
import android.os.Build
import android.os.Bundle
import android.os.IBinder
import android.provider.Settings
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.view.Gravity
import android.view.MotionEvent
import android.view.WindowManager
import android.widget.ImageView
import kotlin.math.abs

/** The little sparrow floating over other apps. Tap = talk, drag = move, long-press = open Sparrow. */
class BubbleService : Service() {
    private var view: ImageView? = null
    private lateinit var wm: WindowManager
    private var recognizer: SpeechRecognizer? = null

    override fun onBind(intent: Intent?): IBinder? = null

    @SuppressLint("ClickableViewAccessibility")
    override fun onCreate() {
        super.onCreate()
        val n = Notifs.service(this, "Sparrow is floating on your screen")
        if (Build.VERSION.SDK_INT >= 34) startForeground(3, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        else startForeground(3, n)
        if (!Settings.canDrawOverlays(this)) { stopSelf(); return }
        instance = this
        wm = getSystemService(WINDOW_SERVICE) as WindowManager
        val dm = resources.displayMetrics
        val size = (62 * dm.density).toInt()
        val sp = Prefs.sp(this)
        val lp = WindowManager.LayoutParams(
            size, size,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = sp.getInt("bubbleX", dm.widthPixels - size - (12 * dm.density).toInt())
            y = sp.getInt("bubbleY", (dm.heightPixels * 0.35).toInt())
        }
        val iv = ImageView(this).apply {
            setImageResource(R.drawable.bubble)
            elevation = 12f
            contentDescription = "Sparrow"
        }
        var downX = 0f; var downY = 0f; var startX = 0; var startY = 0; var moved = false; var downAt = 0L
        iv.setOnTouchListener { v, e ->
            when (e.action) {
                MotionEvent.ACTION_DOWN -> {
                    downX = e.rawX; downY = e.rawY; startX = lp.x; startY = lp.y; moved = false; downAt = System.currentTimeMillis(); true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = (e.rawX - downX).toInt(); val dy = (e.rawY - downY).toInt()
                    if (abs(dx) > 12 || abs(dy) > 12) moved = true
                    if (moved) { lp.x = startX + dx; lp.y = startY + dy; wm.updateViewLayout(v, lp) }
                    true
                }
                MotionEvent.ACTION_UP -> {
                    if (moved) {
                        // snap to the nearest side
                        lp.x = if (lp.x + size / 2 < dm.widthPixels / 2) 0 else dm.widthPixels - size
                        wm.updateViewLayout(v, lp)
                        sp.edit().putInt("bubbleX", lp.x).putInt("bubbleY", lp.y).apply()
                    } else if (System.currentTimeMillis() - downAt > 600) {
                        Commands.startSafely(this, Intent(this, MainActivity::class.java))
                    } else {
                        v.performClick(); listen()
                    }
                    true
                }
                else -> false
            }
        }
        wm.addView(iv, lp)
        view = iv
        // gentle idle bob
        ObjectAnimator.ofFloat(iv, "translationY", 0f, -6f).apply {
            duration = 1600; repeatCount = ValueAnimator.INFINITE; repeatMode = ValueAnimator.REVERSE; start()
        }
    }

    private fun listen() {
        if (checkSelfPermission(android.Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED ||
            !SpeechRecognizer.isRecognitionAvailable(this)) {
            Commands.startSafely(this, Intent(this, MainActivity::class.java).putExtra("listen", true)); return
        }
        Commands.chirp()
        pulse()
        recognizer?.destroy()
        val r = SpeechRecognizer.createSpeechRecognizer(this)
        recognizer = r
        r.setRecognitionListener(object : RecognitionListener {
            override fun onResults(results: Bundle?) {
                val text = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull().orEmpty()
                view?.alpha = 1f
                if (text.isNotBlank()) Commands.run(this@BubbleService, text.replace(Regex("^(hey )?sparrow[, ]*", RegexOption.IGNORE_CASE), ""))
            }
            override fun onError(error: Int) { view?.alpha = 1f }
            override fun onReadyForSpeech(params: Bundle?) { view?.alpha = 0.75f }
            override fun onBeginningOfSpeech() {}
            override fun onRmsChanged(rmsdB: Float) { view?.scaleX = 1f + (rmsdB.coerceIn(0f, 10f) / 60f); view?.scaleY = view?.scaleX ?: 1f }
            override fun onBufferReceived(buffer: ByteArray?) {}
            override fun onEndOfSpeech() { view?.scaleX = 1f; view?.scaleY = 1f }
            override fun onPartialResults(partialResults: Bundle?) {}
            override fun onEvent(eventType: Int, params: Bundle?) {}
        })
        r.startListening(Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, false)
        })
    }

    fun doPulse() {
        val v = view ?: return
        v.animate().scaleX(1.25f).scaleY(1.25f).setDuration(140).withEndAction {
            v.animate().scaleX(1f).scaleY(1f).setDuration(180).start()
        }.start()
    }

    override fun onDestroy() {
        instance = null
        recognizer?.destroy()
        view?.let { try { wm.removeView(it) } catch (_: Exception) {} }
        super.onDestroy()
    }

    companion object {
        var instance: BubbleService? = null
        fun pulse() { instance?.doPulse() }
        val running: Boolean get() = instance != null
    }
}
