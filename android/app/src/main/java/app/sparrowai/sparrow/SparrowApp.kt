package app.sparrowai.sparrow

import android.app.Application
import android.content.Context
import android.content.SharedPreferences

class SparrowApp : Application() {
    override fun onCreate() {
        super.onCreate()
        Notifs.createChannels(this)
        Speaker.init(this)
    }
}

object Prefs {
    fun sp(c: Context): SharedPreferences = c.getSharedPreferences("sparrow", Context.MODE_PRIVATE)
}
