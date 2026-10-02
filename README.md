# Sparrow 🐦

Your friendly little helper for meetings, tasks, reminders, files and more — on Mac, Windows, iPhone and Android.
Free, private (everything stays on your device) and works offline. Just say “Sparrow…”.

## 📲 Get it

**Download page:** https://muhammadtalha257.github.io/sparrow/get.html

| Device | How |
|---|---|
| **Mac** (Intel + Apple silicon) | Download **[Sparrow.dmg](https://github.com/MuhammadTalha257/sparrow/releases/download/mac-latest/Sparrow.dmg)** → drag to Applications → first open: System Settings → Privacy & Security → **Open Anyway** |
| **Windows 10/11** | Download **[Sparrow-Setup.exe](https://github.com/MuhammadTalha257/sparrow/releases/download/windows-latest/Sparrow-Setup.exe)** → open it → if Windows warns: **More info → Run anyway** |
| **Android** | Download **[Sparrow.apk](https://github.com/MuhammadTalha257/sparrow/releases/download/latest/Sparrow.apk)** → open it → allow “Install unknown apps” if asked |
| **iPhone / iPad** | Open **https://muhammadtalha257.github.io/sparrow/** in Safari → **Share** → **Add to Home Screen** |

## ✨ What it does (no AI key needed)

- 🗣️ Hands-free: “Sparrow, open Chrome” · conversation mode · mic button optional
- ⏰ Spoken reminders & meetings (“Talha, you have a meeting in 5 minutes”), repeating reminders, snooze
- ☀️ Morning briefing · 🌙 evening check-in (tick what's done, move the rest to tomorrow)
- 🕌 Prayer times (calculated offline) · 💧 habits (water, medicine…) · 🌍 English, Urdu, Hindi, Arabic
- 🧠 Private memory (“which file did I send on 12 September?”) · 📄 ask your documents (PDF, Word, Excel)
- 👤 Customers & follow-ups · 🧾 quotes & invoices (PDF) · ⏱️ time tracking · 💸 expenses (CSV) · 📊 daily report
- 🎤 Meeting notes with action items · 📑 PDF tools (merge, photos → PDF, keep pages, rotate) · 📋 snippets
- 💻 On Mac/Windows: find files by voice, tidy Downloads, folder alerts, clipboard history, Mail replies (Mac), media & volume
- 🎵 “Play Tum Hi Ho on Spotify” · 🔁 phone ↔ laptop sync by QR code, no account
- 🎨 Themes: Daylight, Midnight, Pop, Sage, Sunset · 🔠 Simple mode for parents

**AI for open questions (optional):** Ollama on your computer (free), a free model that runs on the phone, or your own key for
Groq, OpenRouter, Gemini, ChatGPT, Claude, Grok, DeepSeek, Mistral or Perplexity.

## 🛠 For developers

- **Web app (shared by every device):** repo root — `index.html`, `app.js` (UI), `brain.js` (offline commands), `ai.js`, `store.js`,
  `memory.js` (IndexedDB memory + file text), `tools.js` (PDFs, invoices, time, expenses), `prayer.js`, `i18n.js`, `sync.js`.
- **Mac + Windows app:** `desktop/` (Electron). It wraps the web app and adds computer powers (`main.js`, `preload.js`, `desktop.js`)
  plus offline voice (Vosk). Every push builds `Sparrow.dmg` and `Sparrow-Setup.exe` (Releases → *mac-latest* / *windows-latest*).
- **Android app:** `android/` — bundles the web app and adds native powers (`Bridge.kt`: alarms, voice, bubble, play song…). Every push builds `Sparrow.apk`.
- **Website section** for lisansystems.com: `website/`.
- After changing the web app, bump `VERSION` in `sw.js`.

Third-party libraries in `lib/` keep their own licences (see `LICENSE`).
