package app.sparrowai.sparrow

import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.app.AlarmManager
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.PixelFormat
import android.graphics.RectF
import android.graphics.SweepGradient
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.BatteryManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.Settings
import android.view.Gravity
import android.view.MotionEvent
import android.view.RoundedCorner
import android.view.View
import android.view.WindowManager
import android.view.animation.DecelerateInterpolator
import android.view.animation.LinearInterpolator
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import org.json.JSONObject
import kotlin.math.abs
import kotlin.random.Random

/**
 * Zuffi the bunny lives at the bottom of the phone screen, over every app.
 *  • She wanders left and right, stands, breathes and hops now and then.
 *  • When a reminder is due she walks to the middle and shows it — Done / Snooze 10 min.
 *  • Tap her: she says what's next. Hold: opens Zuffi. Drag: move her.
 *  • Plug the phone in: a light runs round the edge of the screen with the battery %.
 */
class PetService : Service() {
    private lateinit var wm: WindowManager
    private val h = Handler(Looper.getMainLooper())
    private var pet: FrameLayout? = null
    private var img: ImageView? = null
    private var lp: WindowManager.LayoutParams? = null
    private var card: View? = null
    private var glow: View? = null
    private var walking = false
    private var frame = 0
    private var facingLeft = false
    private var hiddenUntil = 0L
    private var lastPlugged: Boolean? = null
    private var toldFull = false
    private val dm get() = resources.displayMetrics
    private fun dp(v: Float) = (v * dm.density).toInt()
    private val petOn get() = Prefs.sp(this).getBoolean("pet", false)
    private val glowOn get() = Prefs.sp(this).getBoolean("chargeLight", false)

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        val n = Notifs.service(this, "Zuffi is on your screen")
        if (Build.VERSION.SDK_INT >= 34) startForeground(4, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE) else startForeground(4, n)
        if (!Settings.canDrawOverlays(this)) { stopSelf(); return }
        instance = this
        wm = getSystemService(WINDOW_SERVICE) as WindowManager
        if (petOn) addPet()
        val f = IntentFilter().apply { addAction(Intent.ACTION_POWER_CONNECTED); addAction(Intent.ACTION_POWER_DISCONNECTED); addAction(Intent.ACTION_BATTERY_CHANGED) }
        if (Build.VERSION.SDK_INT >= 33) registerReceiver(power, f, RECEIVER_NOT_EXPORTED) else registerReceiver(power, f)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == "remind") {
            showReminder(intent.getStringExtra("id") ?: "r", intent.getStringExtra("head") ?: "Reminder", intent.getStringExtra("title") ?: "")
        } else if (intent?.action == "refresh") {
            if (petOn && pet == null) addPet()
            if (!petOn && pet != null) removePet()
            if (!petOn && !glowOn) stopSelf()
        } else if (intent?.action == "say") {
            say(intent.getStringExtra("text") ?: "", 6000)
        }
        return START_STICKY
    }

    // ───────────────────────── the bunny ─────────────────────────

    @SuppressLint("ClickableViewAccessibility")
    private fun addPet() {
        val w = dp(74f); val hgt = dp(132f)
        val p = WindowManager.LayoutParams(w, hgt, WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS, PixelFormat.TRANSLUCENT).apply {
            gravity = Gravity.TOP or Gravity.START
            x = Prefs.sp(this@PetService).getInt("petX", dm.widthPixels - w - dp(24f))
            y = groundY(hgt)
        }
        val box = FrameLayout(this)
        val iv = ImageView(this).apply { setImageResource(R.drawable.pet_stand); scaleType = ImageView.ScaleType.FIT_END; contentDescription = "Zuffi" }
        box.addView(iv, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))
        var downX = 0f; var downY = 0f; var sx = 0; var sy = 0; var moved = false; var downAt = 0L
        box.setOnTouchListener { v, e ->
            when (e.action) {
                MotionEvent.ACTION_DOWN -> { downX = e.rawX; downY = e.rawY; sx = p.x; sy = p.y; moved = false; downAt = System.currentTimeMillis(); stopWalk(); true }
                MotionEvent.ACTION_MOVE -> {
                    val dx = (e.rawX - downX).toInt(); val dy = (e.rawY - downY).toInt()
                    if (abs(dx) > 14 || abs(dy) > 14) moved = true
                    if (moved) { p.x = (sx + dx).coerceIn(0, dm.widthPixels - w); p.y = (sy + dy).coerceIn(0, dm.heightPixels - hgt); safeUpdate(v, p); moveCard() }
                    true
                }
                MotionEvent.ACTION_UP -> {
                    if (moved) {
                        Prefs.sp(this).edit().putInt("petX", p.x).apply()
                        // drop back down to the ground
                        ValueAnimator.ofInt(p.y, groundY(hgt)).apply { duration = 420; interpolator = DecelerateInterpolator()
                            addUpdateListener { p.y = it.animatedValue as Int; safeUpdate(v, p); moveCard() }; start() }
                    } else if (System.currentTimeMillis() - downAt > 600) {
                        Commands.startSafely(this, Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    } else { v.performClick(); hop(); tapped() }
                    true
                }
                else -> false
            }
        }
        try { wm.addView(box, p) } catch (_: Exception) { return }
        pet = box; img = iv; lp = p
        breathe()
        h.postDelayed(life, 3000)
    }

    private fun removePet() {
        h.removeCallbacks(life); stopWalk()
        hideCard()
        pet?.let { try { wm.removeView(it) } catch (_: Exception) {} }
        pet = null; img = null; lp = null
    }

    private fun groundY(hgt: Int): Int {
        val navBar = resources.getIdentifier("navigation_bar_height", "dimen", "android").let { if (it > 0) resources.getDimensionPixelSize(it) else dp(48f) }
        return dm.heightPixels - hgt - navBar + dp(10f)
    }

    private fun safeUpdate(v: View, p: WindowManager.LayoutParams) { try { wm.updateViewLayout(v, p) } catch (_: Exception) {} }

    private fun breathe() {
        img?.let { iv ->
            iv.pivotY = dp(132f).toFloat(); iv.pivotX = dp(37f).toFloat()
            iv.animate().scaleY(1.03f).setDuration(1400).withEndAction { iv.animate().scaleY(1f).setDuration(1400).withEndAction { if (!walking) breathe() }.start() }.start()
        }
    }

    private fun hop() {
        val iv = img ?: return
        iv.animate().translationY(-dp(22f).toFloat()).setDuration(160).setInterpolator(DecelerateInterpolator())
            .withEndAction { iv.animate().translationY(0f).setDuration(220).start() }.start()
    }

    /** What she does when left alone: wander, stand, hop. */
    private val life = object : Runnable {
        override fun run() {
            if (pet == null) return
            if (System.currentTimeMillis() < hiddenUntil) { pet?.visibility = View.GONE; h.postDelayed(this, 30_000); return }
            pet?.visibility = View.VISIBLE
            if (card == null) when (Random.nextInt(10)) {
                in 0..5 -> walkTo(Random.nextInt(dp(8f), dm.widthPixels - dp(82f)))
                6 -> hop()
                else -> {}
            }
            h.postDelayed(this, Random.nextLong(7000, 16000))
        }
    }

    private var walkAnim: ValueAnimator? = null
    private val stepTick = object : Runnable {
        override fun run() {
            if (!walking) return
            frame = (frame + 1) % 4
            img?.setImageResource(when (frame) { 0 -> R.drawable.pet_walk1; 1 -> R.drawable.pet_walk2; 2 -> R.drawable.pet_walk3; else -> R.drawable.pet_walk2 })
            img?.translationY = if (frame % 2 == 0) 0f else -dp(3f).toFloat()
            h.postDelayed(this, 130)
        }
    }

    private fun walkTo(x: Int, then: (() -> Unit)? = null) {
        val p = lp ?: return; val v = pet ?: return
        stopWalk()
        val dist = abs(x - p.x)
        if (dist < dp(12f)) { then?.invoke(); return }
        facingLeft = x < p.x
        img?.scaleX = if (facingLeft) -1f else 1f
        walking = true; h.post(stepTick)
        walkAnim = ValueAnimator.ofInt(p.x, x).apply {
            duration = (dist / (dm.density * 70f) * 1000).toLong().coerceIn(500, 9000)
            interpolator = LinearInterpolator()
            addUpdateListener { p.x = it.animatedValue as Int; safeUpdate(v, p); moveCard() }
            addListener(object : android.animation.AnimatorListenerAdapter() {
                override fun onAnimationEnd(a: android.animation.Animator) { stand(); Prefs.sp(this@PetService).edit().putInt("petX", p.x).apply(); then?.invoke() }
            })
            start()
        }
    }

    private fun stopWalk() { walkAnim?.removeAllListeners(); walkAnim?.cancel(); walkAnim = null; if (walking) stand() }
    private fun stand() {
        walking = false; h.removeCallbacks(stepTick)
        img?.apply { setImageResource(R.drawable.pet_stand); scaleX = 1f; translationY = 0f }
        breathe()
    }

    // ───────────────────────── speech card ─────────────────────────

    private fun tapped() {
        val next = nextReminder()
        say(next ?: listOf("Hi! I'm here 💗", "Hold me to open Zuffi.", "Need anything? Hold me and talk.", "Drink some water 💧").random(), 5000, hide = true)
    }

    private fun nextReminder(): String? {
        val json = Prefs.sp(this).getString("alarmsJson", null) ?: return null
        val arr = try { org.json.JSONArray(json) } catch (_: Exception) { return null }
        val now = System.currentTimeMillis()
        var best: JSONObject? = null
        for (i in 0 until arr.length()) { val o = arr.optJSONObject(i) ?: continue; val at = o.optLong("at"); if (at > now && (best == null || at < best.optLong("at"))) best = o }
        val b = best ?: return null
        val t = java.text.DateFormat.getTimeInstance(java.text.DateFormat.SHORT).format(java.util.Date(b.optLong("at")))
        val sameDay = android.text.format.DateUtils.isToday(b.optLong("at"))
        return "Next: ${b.optString("title")} · ${if (sameDay) "" else "tomorrow "}$t"
    }

    fun say(text: String, ms: Long, hide: Boolean = false) {
        if (text.isBlank()) return
        if (pet == null && petOn) addPet()
        showCard(text, null, null, ms, hide)
    }

    private fun showReminder(id: String, head: String, title: String) {
        if (pet == null) { if (petOn) addPet() else return }
        hiddenUntil = 0; pet?.visibility = View.VISIBLE
        h.removeCallbacks(life)
        walkTo(dm.widthPixels / 2 - dp(37f)) {
            hop()
            showCard(title.ifBlank { head }, head, id, 120_000, false)
        }
        h.postDelayed(life, 125_000)
    }

    private fun showCard(text: String, head: String?, reminderId: String?, ms: Long, hideBtn: Boolean) {
        hideCard()
        val col = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(16f), dp(12f), dp(16f), dp(12f))
            background = GradientDrawable().apply {
                cornerRadius = dp(22f).toFloat()
                colors = intArrayOf(Color.parseColor("#F2241A44"), Color.parseColor("#F2160F30"))
                orientation = GradientDrawable.Orientation.TOP_BOTTOM
                setStroke(dp(1f), Color.parseColor("#55FFFFFF"))
            }
            elevation = dp(10f).toFloat()
        }
        if (head != null) col.addView(TextView(this).apply { this.text = "⏰  $head"; setTextColor(Color.parseColor("#F58FA8")); textSize = 12f; typeface = Typeface.DEFAULT_BOLD })
        col.addView(TextView(this).apply { this.text = text; setTextColor(Color.WHITE); textSize = if (head != null) 17f else 15f; typeface = Typeface.create("sans-serif-medium", Typeface.BOLD); maxWidth = dp(260f) })
        val row = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL; setPadding(0, dp(10f), 0, 0) }
        fun btn(t: String, solid: Boolean, onTap: () -> Unit) = TextView(this).apply {
            this.text = t; textSize = 13.5f; typeface = Typeface.DEFAULT_BOLD
            setTextColor(if (solid) Color.parseColor("#1A1008") else Color.WHITE)
            setPadding(dp(14f), dp(8f), dp(14f), dp(8f))
            background = GradientDrawable().apply {
                cornerRadius = dp(18f).toFloat()
                if (solid) { colors = intArrayOf(Color.parseColor("#FBC56A"), Color.parseColor("#F28A3C")) } else { setColor(Color.parseColor("#22FFFFFF")); setStroke(dp(1f), Color.parseColor("#33FFFFFF")) }
            }
            setOnClickListener { onTap() }
            layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply { marginEnd = dp(8f) }
        }
        if (reminderId != null) {
            row.addView(btn("Done", true) { hideCard(); hop() })
            row.addView(btn("Snooze 10 min", false) { snooze(reminderId, head ?: "Reminder", text); hideCard() })
            col.addView(row)
        } else if (hideBtn) {
            row.addView(btn("Open Zuffi", true) { hideCard(); Commands.startSafely(this, Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) })
            row.addView(btn("Hide 1 hour", false) { hideCard(); hiddenUntil = System.currentTimeMillis() + 3600_000; pet?.visibility = View.GONE })
            col.addView(row)
        }
        val p = WindowManager.LayoutParams(WindowManager.LayoutParams.WRAP_CONTENT, WindowManager.LayoutParams.WRAP_CONTENT, WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS, PixelFormat.TRANSLUCENT).apply { gravity = Gravity.TOP or Gravity.START }
        col.alpha = 0f; col.scaleX = 0.85f; col.scaleY = 0.85f
        try { wm.addView(col, p) } catch (_: Exception) { return }
        card = col; cardLp = p
        col.post { moveCard(); col.animate().alpha(1f).scaleX(1f).scaleY(1f).setDuration(220).start() }
        h.removeCallbacks(autoHide); h.postDelayed(autoHide, ms)
    }
    private var cardLp: WindowManager.LayoutParams? = null
    private val autoHide = Runnable { hideCard() }
    private fun moveCard() {
        val c = card ?: return; val p = cardLp ?: return
        val px = lp?.x ?: (dm.widthPixels / 2); val py = lp?.y ?: (dm.heightPixels - dp(200f))
        p.x = (px + dp(37f) - c.width / 2).coerceIn(dp(8f), (dm.widthPixels - c.width - dp(8f)).coerceAtLeast(dp(8f)))
        p.y = (py - c.height - dp(4f)).coerceAtLeast(dp(40f))
        safeUpdate(c, p)
    }
    private fun hideCard() { h.removeCallbacks(autoHide); card?.let { try { wm.removeView(it) } catch (_: Exception) {} }; card = null }

    private fun snooze(id: String, head: String, title: String) {
        val o = JSONObject().put("title", title).put("type", "reminder").put("head", head).put("say", "$head: $title")
        Alarms.arm(this, getSystemService(AlarmManager::class.java), System.currentTimeMillis() + 10 * 60_000L, Alarms.pending(this, "$id-snz", o))
    }

    // ───────────────────────── charging light ─────────────────────────

    private val power = object : BroadcastReceiver() {
        override fun onReceive(c: Context, i: Intent) {
            when (i.action) {
                Intent.ACTION_POWER_CONNECTED -> plugged(true)
                Intent.ACTION_POWER_DISCONNECTED -> plugged(false)
                Intent.ACTION_BATTERY_CHANGED -> {
                    val st = i.getIntExtra(BatteryManager.EXTRA_STATUS, -1)
                    val on = st == BatteryManager.BATTERY_STATUS_CHARGING || st == BatteryManager.BATTERY_STATUS_FULL
                    if (lastPlugged == null) lastPlugged = on
                    val pct = level()
                    if (on && pct >= 100 && !toldFull) { toldFull = true; if (glowOn) showGlow(true, 100, full = true); say("I'm full! 100% 💗 You can unplug me.", 6000) }
                    if (pct < 97) toldFull = false
                }
            }
        }
    }

    private fun level(): Int {
        val bm = getSystemService(BATTERY_SERVICE) as BatteryManager
        return bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY).coerceIn(0, 100)
    }

    private fun plugged(on: Boolean) {
        if (lastPlugged == on) return
        lastPlugged = on
        val pct = level()
        if (glowOn) showGlow(on, pct)
        if (pet != null) { hop(); say(if (on) "Yum, charging ⚡ $pct%" else "Unplugged at $pct%", 3500) }
    }

    private fun showGlow(charging: Boolean, pct: Int, full: Boolean = false) {
        glow?.let { try { wm.removeView(it) } catch (_: Exception) {} }
        val radius = if (Build.VERSION.SDK_INT >= 31) {
            (wm.currentWindowMetrics.windowInsets.getRoundedCorner(RoundedCorner.POSITION_TOP_LEFT)?.radius ?: dp(36f)).toFloat()
        } else dp(36f).toFloat()
        val root = FrameLayout(this)
        val edge = GlowEdge(this, radius, when { full -> intArrayOf(0xFFFBC56A.toInt(), 0xFFF58FA8.toInt(), 0xFF7C5CFF.toInt(), 0xFFFBC56A.toInt())
            charging -> intArrayOf(0xFF34D399.toInt(), 0xFFA7F3D0.toInt(), 0xFF22D3EE.toInt(), 0x0034D399, 0xFF34D399.toInt())
            else -> intArrayOf(0xFF9CA3AF.toInt(), 0x009CA3AF, 0xFF9CA3AF.toInt()) })
        root.addView(edge, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))
        // the pill in the middle: bunny · 62% Charging · battery
        val pill = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(12f), dp(10f), dp(20f), dp(10f))
            background = GradientDrawable().apply { cornerRadius = dp(40f).toFloat(); setColor(Color.parseColor("#E00A0E18")); setStroke(dp(1f), Color.parseColor("#40FFFFFF")) }
            elevation = dp(16f).toFloat()
        }
        pill.addView(ImageView(this).apply { setImageResource(R.drawable.pet_walk2) }, LinearLayout.LayoutParams(dp(34f), dp(56f)))
        val txt = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(dp(10f), 0, dp(14f), 0) }
        txt.addView(TextView(this).apply { text = "$pct%"; setTextColor(Color.WHITE); textSize = 24f; typeface = Typeface.DEFAULT_BOLD })
        txt.addView(TextView(this).apply { text = when { full -> "Fully charged 💗"; charging -> "Charging ⚡"; else -> "Unplugged" }; setTextColor(Color.parseColor("#CCFFFFFF")); textSize = 12.5f })
        pill.addView(txt)
        val bat = FrameLayout(this).apply { background = GradientDrawable().apply { cornerRadius = dp(6f).toFloat(); setStroke(dp(2f), Color.parseColor("#DDFFFFFF")) }; setPadding(dp(3f), dp(3f), dp(3f), dp(3f)) }
        val fill = View(this).apply { background = GradientDrawable().apply { cornerRadius = dp(3f).toFloat(); colors = intArrayOf(Color.parseColor(if (charging || full) "#34D399" else "#9CA3AF"), Color.parseColor(if (charging || full) "#A7F3D0" else "#D1D5DB")); orientation = GradientDrawable.Orientation.LEFT_RIGHT } }
        bat.addView(fill, FrameLayout.LayoutParams((dp(40f) * pct.coerceAtLeast(6) / 100), FrameLayout.LayoutParams.MATCH_PARENT))
        pill.addView(bat, LinearLayout.LayoutParams(dp(46f), dp(22f)))
        root.addView(pill, FrameLayout.LayoutParams(FrameLayout.LayoutParams.WRAP_CONTENT, FrameLayout.LayoutParams.WRAP_CONTENT, Gravity.CENTER))
        val p = WindowManager.LayoutParams(WindowManager.LayoutParams.MATCH_PARENT, WindowManager.LayoutParams.MATCH_PARENT, WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT).apply {
            alpha = 0.8f   // Android lets touches pass through see-through overlays
            if (Build.VERSION.SDK_INT >= 28) layoutInDisplayCutoutMode = WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
        }
        root.alpha = 0f; pill.scaleX = 0.8f; pill.scaleY = 0.8f
        try { wm.addView(root, p) } catch (_: Exception) { return }
        glow = root
        root.animate().alpha(1f).setDuration(350).start()
        pill.animate().scaleX(1f).scaleY(1f).setDuration(450).setInterpolator(android.view.animation.OvershootInterpolator()).start()
        h.postDelayed({
            root.animate().alpha(0f).setDuration(500).withEndAction { try { wm.removeView(root) } catch (_: Exception) {}; if (glow === root) glow = null }.start()
        }, if (charging) 3600 else 2200)
    }

    /** A bright line that runs round the rounded edge of the screen. */
    private class GlowEdge(c: Context, private val radius: Float, colors: IntArray) : View(c) {
        private val d = c.resources.displayMetrics.density
        private val paints = listOf(22f to 60, 12f to 110, 5f to 255).map { (w, a) ->
            Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE; strokeWidth = w * d; alpha = a }
        }
        private val cols = colors
        private var angle = 0f
        private val m = Matrix()
        private val anim = ValueAnimator.ofFloat(0f, 360f).apply { duration = 2400; repeatCount = ValueAnimator.INFINITE; interpolator = LinearInterpolator(); addUpdateListener { angle = it.animatedValue as Float; invalidate() } }
        override fun onAttachedToWindow() { super.onAttachedToWindow(); anim.start() }
        override fun onDetachedFromWindow() { anim.cancel(); super.onDetachedFromWindow() }
        override fun onDraw(canvas: Canvas) {
            val sg = SweepGradient(width / 2f, height / 2f, cols, null)
            m.setRotate(angle, width / 2f, height / 2f); sg.setLocalMatrix(m)
            for (p in paints) {
                p.shader = sg
                val inset = 2f * d
                canvas.drawRoundRect(RectF(inset, inset, width - inset, height - inset), radius, radius, p)
            }
        }
    }

    override fun onDestroy() {
        instance = null
        try { unregisterReceiver(power) } catch (_: Exception) {}
        removePet()
        glow?.let { try { wm.removeView(it) } catch (_: Exception) {} }
        h.removeCallbacksAndMessages(null)
        super.onDestroy()
    }

    companion object {
        var instance: PetService? = null
        val running get() = instance != null

        /** Start / stop to match the settings (pet on screen, charging light). */
        fun refresh(c: Context) {
            val sp = Prefs.sp(c)
            val want = (sp.getBoolean("pet", false) || sp.getBoolean("chargeLight", false)) && Settings.canDrawOverlays(c)
            if (want) Commands.startFgSafely(c, Intent(c, PetService::class.java).setAction("refresh"))
            else c.stopService(Intent(c, PetService::class.java))
        }

        /** A reminder is due: Zuffi walks to the middle and shows it. Returns true if she did. */
        fun remind(c: Context, id: String, head: String, title: String): Boolean {
            val sp = Prefs.sp(c)
            if (!sp.getBoolean("pet", false) || !Settings.canDrawOverlays(c)) return false
            Commands.startFgSafely(c, Intent(c, PetService::class.java).setAction("remind").putExtra("id", id).putExtra("head", head).putExtra("title", title))
            return true
        }

        fun say(c: Context, text: String) {
            if (instance != null) Commands.startFgSafely(c, Intent(c, PetService::class.java).setAction("say").putExtra("text", text))
        }
    }
}
