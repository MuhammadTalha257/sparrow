package app.sparrowai.sparrow

import android.Manifest
import android.annotation.SuppressLint
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.webkit.WebViewAssetLoader
import org.json.JSONObject

class MainActivity : Activity() {
    lateinit var web: WebView
    private var pageReady = false
    private val queued = mutableListOf<JSONObject>()
    private var recognizer: SpeechRecognizer? = null
    private var listenAfterPermission = false
    var afterMicPermission: (() -> Unit)? = null

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val loader = WebViewAssetLoader.Builder()
            .addPathHandler("/assets/", WebViewAssetLoader.AssetsPathHandler(this))
            .build()
        web = WebView(this)
        web.setBackgroundColor(0xFF140D09.toInt())
        setContentView(web)
        web.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            mediaPlaybackRequiresUserGesture = false
            setSupportMultipleWindows(false)
            javaScriptCanOpenWindowsAutomatically = true
        }
        web.webViewClient = object : WebViewClient() {
            override fun shouldInterceptRequest(view: WebView, request: WebResourceRequest): WebResourceResponse? =
                loader.shouldInterceptRequest(request.url)

            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                val u = request.url
                if (u.host == "appassets.androidplatform.net") return false
                openExternal(u)
                return true
            }

            override fun onPageFinished(view: WebView, url: String) {
                pageReady = true
                queued.forEach { send(it) }
                queued.clear()
            }
        }
        web.webChromeClient = WebChromeClient()
        web.addJavascriptInterface(Bridge(this), "SparrowNative")
        Speaker.onSpeaking = { on -> send(JSONObject().put("type", "speaking").put("on", on)) }
        web.loadUrl("https://appassets.androidplatform.net/assets/www/index.html")

        if (Build.VERSION.SDK_INT >= 33 &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 2)
        }
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(i: Intent?) {
        i ?: return
        i.getStringExtra("ask")?.let {
            send(JSONObject().put("type", "ask").put("text", it).put("voice", i.getBooleanExtra("voice", false)))
            i.removeExtra("ask")
        }
        if (i.getBooleanExtra("listen", false)) { i.removeExtra("listen"); startListening() }
    }

    /** Sends an event to the web app: window.sparrowEvent(json) */
    fun send(o: JSONObject) {
        runOnUiThread {
            if (!pageReady) { queued += o; return@runOnUiThread }
            web.evaluateJavascript("window.sparrowEvent && window.sparrowEvent(${JSONObject.quote(o.toString())})", null)
        }
    }

    fun openExternal(u: Uri) {
        val i = if (u.scheme == "intent") Intent.parseUri(u.toString(), Intent.URI_INTENT_SCHEME) else Intent(Intent.ACTION_VIEW, u)
        i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        try { startActivity(i) } catch (e: Exception) {
            send(JSONObject().put("type", "toast").put("text", "No app can open that link"))
        }
    }

    fun hasMic() = checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED

    fun withMic(then: () -> Unit) {
        if (hasMic()) { then(); return }
        afterMicPermission = then
        requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), 1)
    }

    fun startListening() {
        withMic {
            if (!SpeechRecognizer.isRecognitionAvailable(this)) {
                send(JSONObject().put("type", "toast").put("text", "Speech recognition isn't available on this phone"))
                return@withMic
            }
            Speaker.stop()
            recognizer?.destroy()
            val r = SpeechRecognizer.createSpeechRecognizer(this)
            recognizer = r
            r.setRecognitionListener(object : RecognitionListener {
                override fun onReadyForSpeech(params: Bundle?) { send(JSONObject().put("type", "listening").put("on", true)) }
                override fun onPartialResults(partialResults: Bundle?) {
                    val t = partialResults?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull() ?: return
                    send(JSONObject().put("type", "partial").put("text", t))
                }
                override fun onResults(results: Bundle?) {
                    val t = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull().orEmpty()
                    send(JSONObject().put("type", "listening").put("on", false))
                    if (t.isNotBlank()) send(JSONObject().put("type", "speech").put("text", t))
                }
                override fun onError(error: Int) { send(JSONObject().put("type", "listening").put("on", false)) }
                override fun onBeginningOfSpeech() {}
                override fun onRmsChanged(rmsdB: Float) {}
                override fun onBufferReceived(buffer: ByteArray?) {}
                override fun onEndOfSpeech() {}
                override fun onEvent(eventType: Int, params: Bundle?) {}
            })
            r.startListening(Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            })
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 1) {
            val ok = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
            val then = afterMicPermission
            afterMicPermission = null
            if (ok) then?.invoke()
            else send(JSONObject().put("type", "toast").put("text", "Sparrow needs the microphone to hear you"))
        }
        send(JSONObject().put("type", "status"))
    }

    override fun onResume() {
        super.onResume()
        send(JSONObject().put("type", "status"))   // permissions may have changed in Settings
    }

    @Deprecated("Deprecated in Java")
    override fun onBackPressed() {
        if (web.canGoBack()) web.goBack() else super.onBackPressed()
    }

    override fun onDestroy() {
        recognizer?.destroy()
        Speaker.onSpeaking = null
        super.onDestroy()
    }
}
