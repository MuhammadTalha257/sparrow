# Sparrow 🐦

Your little AI helper for meetings, tasks, reminders and notes — free, private, on your phone.

## 📲 Get it

**Download page:** https://muhammadtalha257.github.io/sparrow/get.html

| Device | How |
|---|---|
| **Mac** | Download **[Sparrow.dmg](https://github.com/MuhammadTalha257/sparrow/releases/download/mac-latest/Sparrow.dmg)** → drag to Applications → first open: System Settings → Privacy & Security → **Open Anyway** |
| **iPhone** | Open **https://muhammadtalha257.github.io/sparrow/** in Safari → **Share** → **Add to Home Screen** |
| **Android** | Download **[Sparrow.apk](https://github.com/MuhammadTalha257/sparrow/releases/download/latest/Sparrow.apk)** → open it → allow “Install unknown apps” if asked |
| **Windows** | Download **[Sparrow-Setup.exe](https://github.com/MuhammadTalha257/sparrow/releases/download/windows-latest/Sparrow-Setup.exe)** → open it → if Windows warns: **More info → Run anyway** |

## ✨ What it does

- 🗓️ **Meetings** — “meeting with Ali Friday 3pm”
- ✅ **Tasks** — “add task buy milk”, then tick it off
- ⏰ **Reminders** — “remind me to call mum at 6pm tomorrow” (real alarms on Android, phone calendar on iPhone)
- ☀️ **Morning briefing** — greeting, time, weather and your day, spoken in a female or male voice
- 📝 **Notes**, 📱 **quick actions** (“open WhatsApp”, “call 07…”, “directions to the station”)
- 💬 **Chat** — free AI that runs on the phone (no key, works offline), or your own Gemini / ChatGPT / Claude key

**Android extras:** a floating sparrow over any app, hands-free “Sparrow, open Chrome…” (offline), open any installed app, notifications read aloud.

Everything is stored only on your phone.

## 🛠 For developers

- The web app (iPhone + Android browser) is the repo root: `index.html`, `app.js`, `brain.js`, `ai.js`, `store.js`.
- The Mac app is in `mac/` (Swift / SwiftUI). Every push builds `Sparrow.dmg` automatically (Releases → *mac-latest*).
- The Windows app is in `windows/` (Electron, wraps the same web app + offline Vosk voice). Every push builds `Sparrow-Setup.exe` (Releases → *windows-latest*).
- The Android app is in `android/` — it bundles the web app and adds native powers (`Bridge.kt`).
- Every push to `main` builds a new `Sparrow.apk` automatically (GitHub Actions → *Releases*).
- After changing the web app, bump `VERSION` in `sw.js` so installed iPhones refresh.
