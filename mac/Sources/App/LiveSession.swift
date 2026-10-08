import Foundation
import AppKit
import AVFoundation
import ScreenCaptureKit

// =====================================================================
// MARK: - Live conversation ("Jarvis mode")
// Say "Zuffi…" once and just talk. Zuffi listens and answers in one
// continuous conversation — no name needed again — until you say
// "thank you", "bye" or go quiet. It hears and speaks in one step
// (Gemini Live, native audio): fast, natural, any language (it answers
// in the language you speak), you can interrupt it, and it acts while you
// talk by calling Zuffi's own agents (apps, Mac control, reminders, email,
// WhatsApp, jobs, camera, screen, web search).
// Needs internet and a Gemini key (Settings → AI). Without them Zuffi
// uses its offline voice as before.
// =====================================================================

@MainActor
final class LiveSession: NSObject {
    static let shared = LiveSession()

    private(set) var active = false
    private var ready = false

    // connection
    private var ws: URLSessionWebSocketTask?
    private var session: URLSession?
    private let wire = LiveWire()
    private var attempts: [(model: String, search: Bool)] = []
    private var attempt = 0
    private var connectGen = 0

    // audio
    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private let outFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 24000, channels: 1, interleaved: false)!
    private var playingUntil = Date.distantPast
    private var echoCancel = false

    // conversation
    private var firstText: String?
    private var firstImage: Data?
    private var userText = ""
    private var agentText = ""
    private var lastActivity = Date()
    private var endAfterTurn = false
    private var pendingTools = 0

    // For Zuffi's face (the bunny reads these ~20×/s).
    var speakingNow: Bool { active && Date() < playingUntil }
    var workingNow: Bool { active && pendingTools > 0 }
    var listeningNow: Bool { active && ready && !speakingNow && pendingTools == 0 }
    private var ticker: Timer?
    private var startedAt = Date()

    static let models = ["gemini-3.8-live", "gemini-3.1-flash-live-preview", "gemini-2.5-flash-native-audio-preview-12-2025"]

    // MARK: When to use it

    private var key: String? {
        guard let k = KeychainStore.shared.get("gemini-api-key"), !k.isEmpty else { return nil }
        return k
    }
    /// Jarvis mode is on (default), there's internet and a Gemini key.
    private var disabledUntil = Date.distantPast
    var usable: Bool {
        (UserDefaults.standard.object(forKey: "liveMode") as? Bool ?? true) && NetStatus.shared.online && key != nil && Date() > disabledUntil
    }

    // MARK: Start / stop

    /// Starts a conversation. `text` = what was already said with "Zuffi, …" (answered straight away).
    func start(text: String? = nil, image: Data? = nil) {
        guard VoiceEngine.micOn else { VoiceEngine.shared.speak("Your mic is off. Turn it on with the mic button and I'll listen."); return }
        if active {
            if let image { sendImage(image) }
            if let text, !text.isEmpty { sendText(text) }
            return
        }
        guard let key else { return }
        active = true; ready = false; endAfterTurn = false
        firstText = text; firstImage = image
        userText = ""; agentText = ""
        lastActivity = Date(); startedAt = Date()
        VoiceEngine.shared.suspendForLive()
        SoundEngine.shared.play("question")
        NotificationCenter.default.post(name: .hookReveal, object: nil)
        NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.surprised)
        let preferred = UserDefaults.standard.string(forKey: "liveModel") ?? ""
        let order = (preferred.isEmpty ? [] : [preferred]) + Self.models.filter { $0 != preferred }
        let searchOK = UserDefaults.standard.object(forKey: "liveSearchOK") as? Bool
        attempts = order.flatMap { m -> [(String, Bool)] in
            if m == preferred, let ok = searchOK { return ok ? [(m, true), (m, false)] : [(m, false)] }
            return [(m, true), (m, false)]
        }
        attempt = 0
        appendAppLog("voice.log", "live: start (\(text ?? "just the name"))")
        Task { await self.connect(key: key) }
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            MainActor.assumeIsolated { LiveSession.shared.tick() }
        }
    }

    /// Ends the conversation and goes back to listening for "Zuffi…".
    func stop(_ why: String) {
        guard active else { return }
        active = false; ready = false
        appendAppLog("voice.log", "live: end (\(why)) after \(Int(Date().timeIntervalSince(startedAt)))s")
        ticker?.invalidate(); ticker = nil
        connectGen += 1
        wire.set(nil)
        ws?.cancel(with: .normalClosure, reason: nil); ws = nil
        session?.invalidateAndCancel(); session = nil
        stopAudio()
        VoiceEngine.shared.noteLevel(0)
        NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.happy)
        VoiceEngine.shared.resumeAfterLive()
    }

    private func tick() {
        guard active else { return }
        let quiet = Date().timeIntervalSince(lastActivity)
        let talking = Date() < playingUntil
        if endAfterTurn, !talking, pendingTools == 0, quiet > 0.8 { stop("goodbye"); return }
        // Nobody said anything for a while → the conversation is over (quietly).
        if ready, !talking, pendingTools == 0, quiet > (UserDefaults.standard.object(forKey: "liveIdleSeconds") as? Double ?? 20) {
            SoundEngine.shared.play("approve")
            stop("quiet")
        }
        // Couldn't connect at all within 12 s → fall back to the offline voice for this request.
        if !ready, Date().timeIntervalSince(startedAt) > 12 { fallback("timeout") }
    }

    private func fallback(_ why: String) {
        let t = firstText
        stop("fallback: \(why)")
        if let t, !t.isEmpty { Task { await Assistant.run(t, spoken: true) } }
        else { VoiceEngine.shared.listenOffline() }
    }

    // MARK: Connection

    private func connect(key: String) async {
        guard active, attempt < attempts.count else { fallback("no model available"); return }
        connectGen += 1
        let gen = connectGen
        let (model, search) = attempts[attempt]
        // Everything for the first message is ready before the line opens, so setup goes out instantly.
        let setup = await setupMessage(model: model, search: search)
        guard active, gen == connectGen else { return }
        var c = URLComponents(string: "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent")!
        c.queryItems = [URLQueryItem(name: "key", value: key)]
        let delegate = LiveSocketDelegate { code, reason in
            Task { @MainActor in LiveSession.shared.socketClosed(gen: gen, code: code, reason: reason) }
        }
        let s = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        let task = s.webSocketTask(with: c.url!)
        task.maximumMessageSize = 16 * 1024 * 1024
        session = s; ws = task
        task.resume()
        receive(task, gen: gen)
        send(["setup": setup])
        appendAppLog("voice.log", "live: connecting \(model)\(search ? " + search" : "")")
    }

    private func socketClosed(gen: Int, code: Int, reason: String) {
        guard active, gen == connectGen else { return }
        appendAppLog("voice.log", "live: socket closed \(code) \(reason.prefix(200))")
        connectGen += 1          // one close = one retry (the socket can report the same close twice)
        if !ready {
            // The model isn't available for this key (or didn't like a setting) → try the next one.
            attempt += 1
            ws = nil; session?.invalidateAndCancel(); session = nil
            if let key { Task { await self.connect(key: key) } }
        } else if code == 1000 || reason.lowercased().contains("goaway") || reason.isEmpty {
            stop("closed")
        } else {
            stop("error \(code)")
        }
    }

    private func receive(_ task: URLSessionWebSocketTask, gen: Int) {
        task.receive { result in
            Task { @MainActor in
                let me = LiveSession.shared
                guard me.active, gen == me.connectGen else { return }
                switch result {
                case .success(let msg):
                    switch msg {
                    case .string(let s): me.handle(Data(s.utf8))
                    case .data(let d): me.handle(d)
                    @unknown default: break
                    }
                    me.receive(task, gen: gen)
                case .failure(let e):
                    appendAppLog("voice.log", "live: receive failed \(e.localizedDescription)")
                    me.socketClosed(gen: gen, code: -1, reason: e.localizedDescription)
                }
            }
        }
    }

    private func send(_ obj: [String: Any]) {
        guard let d = try? JSONSerialization.data(withJSONObject: obj), let s = String(data: d, encoding: .utf8) else { return }
        ws?.send(.string(s)) { _ in }
    }

    func sendText(_ text: String) {
        guard ready else { firstText = [firstText, text].compactMap { $0 }.joined(separator: ". "); return }
        lastActivity = Date()
        send(["realtimeInput": ["text": text]])
    }

    func sendImage(_ jpeg: Data) {
        guard ready else { firstImage = jpeg; return }
        lastActivity = Date()
        send(["realtimeInput": ["video": ["data": jpeg.base64EncodedString(), "mimeType": "image/jpeg"]]])
    }

    // MARK: The setup: who Zuffi is, how it talks, what it can do

    private func setupMessage(model: String, search: Bool) async -> [String: Any] {
        var gen: [String: Any] = [
            "responseModalities": ["AUDIO"],
            "speechConfig": ["voiceConfig": ["prebuiltVoiceConfig": ["voiceName": UserDefaults.standard.string(forKey: "liveVoice") ?? "Kore"]]],
        ]
        if model.contains("3.1-flash-live") { gen["thinkingConfig"] = ["thinkingLevel": "minimal"] }
        var tools: [[String: Any]] = [["functionDeclarations": LiveTools.declarations]]
        if search { tools.append(["googleSearch": [String: Any]()]) }
        return [
            "model": "models/\(model)",
            "generationConfig": gen,
            "systemInstruction": ["parts": [["text": await systemPrompt()]]],
            "tools": tools,
            "inputAudioTranscription": [String: Any](),
            "outputAudioTranscription": [String: Any](),
            "realtimeInputConfig": ["automaticActivityDetection": ["disabled": false, "prefixPaddingMs": 120, "silenceDurationMs": 650]],
            "contextWindowCompression": ["slidingWindow": [String: Any]()],
        ]
    }

    private func systemPrompt() async -> String {
        let name = AssistantPrefs.displayName
        let f = DateFormatter(); f.dateFormat = "EEEE d MMMM yyyy, HH:mm"
        let tz = TimeZone.current.identifier
        let items = await WebHub.shared.callJS("return window.Sparrow.listItems ? JSON.stringify(window.Sparrow.listItems()) : '[]'") as? String ?? "[]"
        let front = AppState.shared.lastExternalApp?.localizedName ?? "unknown"
        return """
        You are Zuffi, \(name.isEmpty ? "the user's" : name + "'s") personal assistant living on their Mac — like JARVIS: calm, quick, warm, a little witty, always useful. You have a team of agents (tools) that do real things on this Mac.
        Now: \(f.string(from: Date())) (\(tz)). Front app: \(front).
        Their reminders, meetings and tasks (JSON, id = what tools need): \(items.prefix(4000))

        HOW YOU TALK
        - This is a live voice conversation. Reply in 1–2 short spoken sentences unless they ask for detail. No lists, no markdown, no emojis.
        - Detect the language they speak and ALWAYS answer in that same language: Urdu → Urdu, Roman Urdu/Hindi mix → the same mix, Punjabi, Hindi, Arabic, Spanish, French, Brazilian Portuguese, Turkish, English… If they switch, you switch.
        - If they ask you to translate, say the translation clearly (and slowly enough to repeat).
        - They may interrupt you: stop and listen. If you didn't understand, ask one short question.

        HOW YOU ACT
        - When they ask for something, call the right tool immediately — even mid-sentence. For several steps ("open Notes and make a note called hello, then open x.com"), do each step as soon as it's clear, in order.
        - run_command does almost anything on the Mac in plain English: open/quit apps and websites, play/pause music, volume, brightness, Wi-Fi, Bluetooth, dark mode, lock, sleep, shut down (it asks to confirm), split windows, Shortcuts, type text, notes ("note <text>" or "open Notes and create a note titled X"), Google/YouTube searches, weather, prayer times, battery, meeting notes, timers, focus mode.
        - Reminders: add_reminder with an exact ISO date-time you work out from "now" (e.g. "coming Monday at 10" = the next Monday 10:00). To delete or finish one, pick the matching id from the list above (match by day, time or words — "the Monday one" = the one due next Monday); if two match, ask which.
        - Email (their Mail app): check_email, read_latest_email, read_email_from. To reply: draft_email_reply, read the draft to them, ask "Shall I send it?" and only call send_email after a clear yes. Never send without a yes.
        - WhatsApp: check_whatsapp; whatsapp_draft then send_whatsapp only after a clear yes.
        - Hands: operate_screen does anything on the screen step by step (it can see, click, type and scroll in any app or website) — use it when no other tool fits, e.g. "play the latest X on YouTube", "fill this form", "click Sign in". If it returns a question ("Shall I click Send?"), ask the user and pass their answer with screen_answer. "stop" while it works → stop_screen.
        - Eyes: "what is this", "what am I holding", "what do you see", "look at this", "how do I look", "yeh kya hai" → look_through_camera (they are showing something to the camera). "What's on my screen", "read this page", "what is this error/window" → look_at_screen. take_photo to take a picture. After the image arrives, name the thing plainly first, then one useful detail (brand, what it's for, any text on it). If the picture is too dark or blurry, say so and ask them to hold it closer.
        - Writing: make_note to write and save a note in Notes (compose the full text yourself from what they said — e.g. "make notes on today's meeting: …" or "write a shopping list: milk, eggs"); type_text to type into whatever they're working in.
        - Facts, news, prices → use Google Search; combine several sources and say where it's from in a few words.
        - Jobs: find_jobs (role, location, level: internship/apprentice, entry, mid, senior, lead). It searches job boards, ranks by their CV and adds LinkedIn and Indeed searches with the same filters.
        - Never pretend: only say something is done if the tool result says so. If a tool fails, say so simply and offer another way.

        ENDING
        - When they say thanks / thank you / bye / that's all / khuda hafiz / shukriya / bas, answer with a very short goodbye and call end_conversation.
        """
    }

    // MARK: Messages from Zuffi's voice brain

    private func handle(_ data: Data) {
        guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        if o["setupComplete"] != nil { setupDone(); return }
        if let sc = o["serverContent"] as? [String: Any] { content(sc) }
        if let tc = o["toolCall"] as? [String: Any], let calls = tc["functionCalls"] as? [[String: Any]] { toolCalls(calls) }
        if o["goAway"] != nil { endAfterTurn = true }
    }

    private func setupDone() {
        ready = true
        let (model, search) = attempts[attempt]
        UserDefaults.standard.set(model, forKey: "liveModel")
        UserDefaults.standard.set(search, forKey: "liveSearchOK")
        appendAppLog("voice.log", "live: connected \(model)\(search ? " + search" : "") in \(String(format: "%.1f", Date().timeIntervalSince(startedAt)))s")
        startAudio()
        if let img = firstImage { firstImage = nil; sendImage(img) }
        if let t = firstText, !t.isEmpty { firstText = nil; sendText(t) }
        else { sendText("(The user just said your name to start talking. Answer with a very short, warm 'yes?' in their language — two or three words — and listen.)") }
    }

    private func content(_ sc: [String: Any]) {
        if sc["interrupted"] as? Bool == true {
            // They started talking — stop speaking at once.
            player?.stop(); player?.play()
            playingUntil = Date()
            agentText = ""
        }
        if let t = (sc["inputTranscription"] as? [String: Any])?["text"] as? String, !t.isEmpty {
            userText += t
            lastActivity = Date()
            checkGoodbye()
        }
        if let t = (sc["outputTranscription"] as? [String: Any])?["text"] as? String { agentText += t }
        if let turn = sc["modelTurn"] as? [String: Any], let parts = turn["parts"] as? [[String: Any]] {
            for p in parts {
                if let inline = p["inlineData"] as? [String: Any], let b64 = inline["data"] as? String, let pcm = Data(base64Encoded: b64) {
                    play(pcm)
                }
            }
        }
        if sc["turnComplete"] as? Bool == true {
            let u = userText.trimmingCharacters(in: .whitespacesAndNewlines), a = agentText.trimmingCharacters(in: .whitespacesAndNewlines)
            // Kept in the chat history (not shown on screen while talking).
            let st = AppState.shared
            if !u.isEmpty { st.chatHistory.append(ChatMessage(role: .user, content: u)) }
            if !a.isEmpty { st.chatHistory.append(ChatMessage(role: .assistant, content: a)) }
            if !u.isEmpty || !a.isEmpty { appendAppLog("voice.log", "live: \"\(u)\" → \"\(a.prefix(160))\"") }
            userText = ""; agentText = ""
            lastActivity = Date()
        }
    }

    private func checkGoodbye() {
        let t = userText.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: " .!?,"))
        let words = t.split(separator: " ").count
        if words <= 6, t.range(of: #"(^|\b)(bye|bye bye|goodbye|good bye|good night|goodnight|thank you|thanks|thank u|that'?s all|that is all|stop listening|go to sleep|you can go|khuda hafiz|allah hafiz|shukriya|shukria|bas|bas karo|theek hai bas|ok bye)\.?$"#, options: .regularExpression) != nil {
            endAfterTurn = true
        }
    }

    // MARK: Tools (Zuffi's agents)

    private func toolCalls(_ calls: [[String: Any]]) {
        lastActivity = Date()
        for call in calls {
            let id = call["id"] as? String ?? ""
            let name = call["name"] as? String ?? ""
            let args = call["args"] as? [String: Any] ?? [:]
            pendingTools += 1
            NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.happy)
            Task { @MainActor in
                let result = await LiveTools.run(name, args)
                self.pendingTools -= 1
                self.lastActivity = Date()
                guard self.active else { return }
                appendAppLog("agents.log", "live tool \(name)(\(args)) → \(String(describing: result["result"] ?? result).prefix(200))")
                self.send(["toolResponse": ["functionResponses": [["id": id, "name": name, "response": result]]]])
                if name == "end_conversation" { self.endAfterTurn = true }
            }
        }
    }

    // MARK: Audio in/out (one engine, with echo cancellation so Zuffi doesn't hear itself)

    /// Some Macs (or mic/speaker combinations) refuse Apple's echo cancellation — remembered so it isn't tried again.
    private static var echoBroken = UserDefaults.standard.bool(forKey: "liveEchoBroken")

    private func startAudio() {
        if !Self.echoBroken, startEngine(echo: true) { return }
        if !Self.echoBroken {
            Self.echoBroken = true
            UserDefaults.standard.set(true, forKey: "liveEchoBroken")
            appendAppLog("voice.log", "live: echo cancellation unavailable on this Mac — using plain audio")
        }
        if startEngine(echo: false) { return }
        audioFailed()
    }

    /// Starts mic + speaker. false = couldn't (everything is cleaned up again).
    private func startEngine(echo: Bool) -> Bool {
        let e = AVAudioEngine()
        let p = AVAudioPlayerNode()
        let input = e.inputNode
        echoCancel = false
        if echo {
            do { try input.setVoiceProcessingEnabled(true); echoCancel = true } catch { return false }
            // Don't make the rest of the Mac's sound quiet while we talk.
            input.voiceProcessingOtherAudioDuckingConfiguration = .init(enableAdvancedDucking: false, duckingLevel: .min)
        }
        e.attach(p)
        e.connect(p, to: e.mainMixerNode, format: outFormat)
        let hw = input.outputFormat(forBus: 0)
        guard hw.sampleRate > 0, hw.channelCount > 0 else {
            appendAppLog("voice.log", "live: no microphone format (echo \(echo))")
            if echo { try? input.setVoiceProcessingEnabled(false) }
            return false
        }
        wire.set(ws)
        wire.setMuted(false)
        Self.installMicTap(input, format: hw, wire: wire)
        do {
            e.prepare()
            try e.start()
        } catch {
            appendAppLog("voice.log", "live: audio start failed (echo \(echo)) \(error.localizedDescription)")
            input.removeTap(onBus: 0)
            e.stop()
            if echo { try? input.setVoiceProcessingEnabled(false) }
            wire.set(nil)
            return false
        }
        p.volume = 1; e.mainMixerNode.outputVolume = 1
        p.play()
        engine = e; player = p
        appendAppLog("voice.log", "live: audio on (echo cancellation \(echoCancel ? "on" : "off"), mic \(Int(hw.sampleRate)) Hz × \(hw.channelCount))")
        return true
    }

    /// The live voice can't use the audio right now → the normal voice answers instead (never silence).
    private func audioFailed() {
        disabledUntil = Date().addingTimeInterval(10 * 60)
        appendAppLog("voice.log", "live: audio unavailable — normal voice for the next 10 minutes")
        fallback("audio")
    }

    private func stopAudio() {
        wire.set(nil)
        if let e = engine {
            e.inputNode.removeTap(onBus: 0)
            player?.stop()
            e.stop()
            try? e.inputNode.setVoiceProcessingEnabled(false)
        }
        engine = nil; player = nil
        playingUntil = .distantPast
    }

    private func play(_ pcm: Data) {
        guard let p = player, engine?.isRunning == true else { return }
        let n = pcm.count / 2
        guard n > 0, let buf = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: AVAudioFrameCount(n)) else { return }
        buf.frameLength = AVAudioFrameCount(n)
        let out = buf.floatChannelData![0]
        var peak: Float = 0
        pcm.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            let s = raw.bindMemory(to: Int16.self)
            for i in 0..<n { let v = Float(Int16(littleEndian: s[i])) / 32768; out[i] = v; peak = max(peak, abs(v)) }
        }
        p.scheduleBuffer(buf, completionHandler: nil)
        let dur = Double(n) / 24000
        playingUntil = max(playingUntil, Date()).addingTimeInterval(dur)
        lastActivity = Date()
        VoiceEngine.shared.noteLevel(peak * 0.35)
        // Without echo cancellation, don't send the mic while Zuffi talks (it would hear itself).
        if !echoCancel {
            wire.setMuted(true)
            let until = playingUntil
            DispatchQueue.main.asyncAfter(deadline: .now() + max(0, until.timeIntervalSinceNow) + 0.35) {
                MainActor.assumeIsolated { if Date() >= LiveSession.shared.playingUntil { LiveSession.shared.wire.setMuted(false) } }
            }
        }
    }

    /// Microphone → 16 kHz 16-bit mono → Gemini, straight from the audio thread.
    nonisolated private static func installMicTap(_ node: AVAudioInputNode, format hw: AVAudioFormat, wire: LiveWire) {
        let rate = hw.sampleRate
        nonisolated(unsafe) let target = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true)!
        // Voice processing can give several channels; take the first one as mono.
        nonisolated(unsafe) let mono = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false)!
        guard let conv = AVAudioConverter(from: mono, to: target) else { return }
        nonisolated(unsafe) let converter = conv
        node.installTap(onBus: 0, bufferSize: 1600, format: hw) { buffer, _ in
            guard !wire.muted, let ch = buffer.floatChannelData?[0] else { return }
            let frames = buffer.frameLength
            guard let m = AVAudioPCMBuffer(pcmFormat: mono, frameCapacity: frames) else { return }
            m.frameLength = frames
            m.floatChannelData![0].update(from: ch, count: Int(frames))
            let cap = AVAudioFrameCount(Double(frames) * 16000 / rate) + 32
            guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: cap) else { return }
            let fed = FedFlag()
            var err: NSError?
            converter.convert(to: out, error: &err) { _, status in
                if fed.done { status.pointee = .noDataNow; return nil }
                fed.done = true; status.pointee = .haveData; return m
            }
            guard err == nil, out.frameLength > 0, let p = out.int16ChannelData?[0] else { return }
            wire.sendAudio(Data(bytes: p, count: Int(out.frameLength) * 2))
            // orb level
            var sum: Float = 0
            for i in stride(from: 0, to: Int(frames), by: 8) { sum += ch[i] * ch[i] }
            let rms = (sum / Float(max(1, Int(frames) / 8))).squareRoot()
            Task { @MainActor in VoiceEngine.shared.noteLevel(rms) }
        }
    }
}

final class FedFlag: @unchecked Sendable { var done = false }

// MARK: - Thread-safe pipe from the audio thread to the socket

final class LiveWire: @unchecked Sendable {
    private let lock = NSLock()
    private var task: URLSessionWebSocketTask?
    private var _muted = false
    func set(_ t: URLSessionWebSocketTask?) { lock.lock(); task = t; lock.unlock() }
    func setMuted(_ m: Bool) { lock.lock(); _muted = m; lock.unlock() }
    var muted: Bool { lock.lock(); defer { lock.unlock() }; return _muted }
    func sendAudio(_ pcm: Data) {
        lock.lock(); let t = task; lock.unlock()
        guard let t else { return }
        let msg = "{\"realtimeInput\":{\"audio\":{\"data\":\"\(pcm.base64EncodedString())\",\"mimeType\":\"audio/pcm;rate=16000\"}}}"
        t.send(.string(msg)) { _ in }
    }
}

final class LiveSocketDelegate: NSObject, URLSessionWebSocketDelegate, @unchecked Sendable {
    private let onClose: @Sendable (Int, String) -> Void
    init(onClose: @escaping @Sendable (Int, String) -> Void) { self.onClose = onClose }
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        onClose(closeCode.rawValue, reason.flatMap { String(data: $0, encoding: .utf8) } ?? "")
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { onClose(-2, error.localizedDescription) }
    }
}

// MARK: - What Zuffi's voice brain can ask the agents to do

@MainActor
enum LiveTools {
    private static func fn(_ name: String, _ desc: String, _ props: [String: [String: Any]] = [:], required: [String] = []) -> [String: Any] {
        var d: [String: Any] = ["name": name, "description": desc]
        if !props.isEmpty { d["parameters"] = ["type": "OBJECT", "properties": props, "required": required] }
        return d
    }
    private static let str: (String) -> [String: Any] = { ["type": "STRING", "description": $0] }

    static let declarations: [[String: Any]] = [
        fn("run_command", "Do something on the Mac with Zuffi's agents. Write one clear English command, e.g. 'open Spotify', 'play music', 'volume 40', 'turn off wifi', 'open Notes and create a note titled hello', 'search google for Norbert Wiener', 'open x.com', 'what's the weather', 'prayer times', 'start meeting notes', 'lock screen', 'put Safari on the left and Notes on the right'.",
           ["command": str("The command in plain English.")], required: ["command"]),
        fn("add_reminder", "Create a reminder, task or meeting at an exact time.",
           ["title": str("What to remind about, short."), "when": str("ISO 8601 local date-time, e.g. 2026-10-12T10:00:00"),
            "kind": str("reminder | task | meeting"), "repeat": str("Optional: daily | weekdays | weekly | monthly")], required: ["title", "when"]),
        fn("delete_reminder", "Delete a reminder, task or meeting by its id from the list in your instructions.", ["id": str("Item id.")], required: ["id"]),
        fn("complete_task", "Mark a reminder/task as done by id.", ["id": str("Item id.")], required: ["id"]),
        fn("list_reminders", "Get the current reminders, meetings and tasks with ids."),
        fn("check_email", "Summarise the newest unread emails in the Mail app."),
        fn("read_latest_email", "Read the newest email in the inbox."),
        fn("read_email_from", "Read the newest email from someone.", ["sender": str("Name or address.")], required: ["sender"]),
        fn("draft_email_reply", "Draft (not send) a reply to the newest email from someone. Read the draft to the user and ask before sending.",
           ["to": str("Who to reply to (name), or 'last' for the email just read."), "message": str("What the user wants to say.")], required: ["to", "message"]),
        fn("send_email", "Send the email draft — ONLY after the user clearly said yes."),
        fn("check_whatsapp", "How many unread WhatsApp messages and from whom."),
        fn("whatsapp_draft", "Prepare a WhatsApp message (not sent yet).", ["to": str("Contact name or number."), "message": str("The message.")], required: ["to", "message"]),
        fn("send_whatsapp", "Send the prepared WhatsApp message — ONLY after a clear yes."),
        fn("look_through_camera", "Look through the Mac's camera to answer a question about the user or what they're holding/showing.", ["question": str("What to look for.")]),
        fn("look_at_screen", "Look at what's on the Mac screen now.", ["question": str("What to look for.")]),
        fn("take_photo", "Take a photo with the camera, save it to Pictures and show it."),
        fn("find_jobs", "Search jobs matching the user's CV.", ["role": str("Job title or skill, e.g. 'react developer'."), "location": str("City or 'remote'."),
                                                                  "level": str("internship | apprentice | entry | mid | senior | lead (optional)")], required: ["role"]),
        fn("operate_screen", "Use the Mac's screen, mouse and keyboard to do a task in any app or website (clicking, typing, scrolling) — for things the other tools can't do, e.g. 'play the latest Arijit Singh song on YouTube', 'fill in this form with my details', 'find the cheapest flight on this page'. Zuffi sees the screen, acts step by step and asks the user before anything risky. Returns the result or a question for the user.",
           ["task": str("The whole task in plain English, with all details the user gave.")], required: ["task"]),
        fn("screen_answer", "The screen agent asked the user to confirm a risky step (send, buy, delete…). Pass their answer.", ["yes": ["type": "BOOLEAN", "description": "true if the user agreed"]], required: ["yes"]),
        fn("stop_screen", "Stop the screen agent right away (the user said stop / take over)."),
        fn("make_note", "Create and save a note in Apple Notes with a title and the full text (write the text out properly — lists, paragraphs). Use for 'make a note', 'write this down', 'save notes about…'.",
           ["title": str("Short title."), "text": str("The full note text. Use new lines for lists.")], required: ["title", "text"]),
        fn("type_text", "Type text into the app the user is working in (the box or document they last clicked). Use for 'type …', 'write … here', 'likho'.",
           ["text": str("Exactly what to type.")], required: ["text"]),
        fn("end_conversation", "Call when the user says goodbye/thanks/that's all, after your short goodbye."),
    ]

    static func run(_ name: String, _ a: [String: Any]) async -> [String: Any] {
        func s(_ k: String) -> String { (a[k] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
        func ok(_ r: String?) -> [String: Any] { r.map { ["ok": true, "result": $0] } ?? ["ok": false, "result": "Zuffi couldn't do that."] }
        defer { VoiceEngine.shared.listenAfterSpeech = false }    // agents may ask the offline voice to listen — not now
        switch name {
        case "run_command":
            let cmd = s("command")
            guard !cmd.isEmpty else { return ok(nil) }
            var r = await AgentRouter.shared.handle(cmd)
            if r == nil { r = await WebHub.shared.ask(cmd) }
            if MeetingNotes.shared.active { LiveSession.shared.stop("meeting notes") }     // meeting notes take over the mic
            return ok(r)
        case "add_reminder":
            let res = await WebHub.shared.callJS("return JSON.stringify(window.Sparrow.addReminder(t, w, k, r))",
                                                 ["t": s("title"), "w": s("when"), "k": s("kind").isEmpty ? "reminder" : s("kind"), "r": s("repeat")]) as? String
            return ok(res)
        case "delete_reminder":
            let res = await WebHub.shared.callJS("return window.Sparrow.removeItem(id)", ["id": s("id")]) as? String
            return res.map { ["ok": true, "result": "Deleted: \($0)"] } ?? ["ok": false, "result": "No item with that id."]
        case "complete_task":
            let res = await WebHub.shared.callJS("return window.Sparrow.completeItem(id)", ["id": s("id")]) as? String
            return res.map { ["ok": true, "result": "Done: \($0)"] } ?? ["ok": false, "result": "No item with that id."]
        case "list_reminders":
            return ok(await WebHub.shared.callJS("return JSON.stringify(window.Sparrow.listItems())") as? String)
        case "check_email": return ok(await MailAgent.shared.checkNew())
        case "read_latest_email": return ok(await MailAgent.shared.readLatest(show: false))
        case "read_email_from": return ok(await MailAgent.shared.handle("read the email from \(s("sender"))"))
        case "draft_email_reply":
            let to = s("to").lowercased() == "last" || s("to").isEmpty ? "it" : s("to")
            return ok(await MailAgent.shared.handle("reply to \(to) saying \(s("message"))"))
        case "send_email":
            guard MailAgent.shared.draft != nil else { return ["ok": false, "result": "There's no email draft to send."] }
            return ok(await MailAgent.shared.handle("send"))
        case "check_whatsapp": return ok(await WhatsAppAgent.shared.checkNew())
        case "whatsapp_draft": return ok(await WhatsAppAgent.shared.handle("whatsapp \(s("to")) saying \(s("message"))"))
        case "send_whatsapp":
            guard WhatsAppAgent.shared.draft != nil else { return ["ok": false, "result": "There's no WhatsApp message to send."] }
            return ok(await WhatsAppAgent.shared.handle("send"))
        case "look_through_camera", "take_photo":
            guard let jpeg = await CameraSnap.capture() else {
                return ["ok": false, "result": VoiceEngine.cameraOn ? "I couldn't use the camera. Allow Zuffi under System Settings → Privacy & Security → Camera." : "The camera is switched off in Zuffi. Ask the user to turn it on with the camera button."]
            }
            LiveSession.shared.sendImage(jpeg)
            if name == "take_photo" {
                let dir = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0].appendingPathComponent("Sparrow", isDirectory: true)
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
                let url = dir.appendingPathComponent("Photo \(f.string(from: Date())).jpg")
                try? jpeg.write(to: url)
                NSWorkspace.shared.open(url)
                return ["ok": true, "result": "Photo taken and saved in Pictures → Zuffi. The image was also sent to you."]
            }
            return ["ok": true, "result": "A photo from the camera was just sent to you as an image. Answer from what you see in it."]
        case "look_at_screen":
            guard let jpeg = await ScreenGrab.main()?.jpeg else {
                return ["ok": false, "result": "I couldn't see the screen. Tell the user: open Zuffi Settings → Screen, press Fix permissions, switch Zuffi on, then press Restart Zuffi."]
            }
            LiveSession.shared.sendImage(jpeg)
            return ["ok": true, "result": "A screenshot was just sent to you as an image. Answer from what you see in it."]
        case "find_jobs":
            let level = s("level"), loc = s("location")
            let q = "find \(level.isEmpty ? "" : level + " ")\(s("role")) jobs\(loc.isEmpty ? "" : " in " + loc)"
            return ok(await WebHub.shared.ask(q))
        case "operate_screen":
            return ok(await ScreenAgent.shared.run(s("task")))
        case "screen_answer":
            guard ScreenAgent.shared.awaitingConfirmation else { return ["ok": false, "result": "Nothing is waiting for an answer."] }
            let yes = a["yes"] as? Bool ?? false
            ScreenAgent.shared.confirm(yes)
            return ["ok": true, "result": yes ? "Confirmed — continuing." : "Cancelled."]
        case "stop_screen":
            ScreenAgent.shared.stop(); return ["ok": true, "result": "Stopped."]
        case "make_note":
            return ok(await Writer.makeNote(title: s("title"), text: s("text")))
        case "type_text":
            return ok(await Writer.type(s("text")))
        case "end_conversation":
            return ["ok": true, "result": "Ending after your goodbye."]
        default:
            return ["ok": false, "result": "Unknown tool \(name)."]
        }
    }
}

// MARK: - Camera: one photo, on request

final class CameraSnap: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    private var cont: CheckedContinuation<Data?, Never>?
    private let session = AVCaptureSession()

    static func capture() async -> Data? {
        guard await MainActor.run(body: { VoiceEngine.cameraOn }) else { return nil }
        let granted: Bool
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: granted = true
        case .notDetermined: granted = await AVCaptureDevice.requestAccess(for: .video)
        default: granted = false
        }
        guard granted else { return nil }
        let snap = CameraSnap()
        return await snap.take()
    }

    private func take() async -> Data? {
        await withCheckedContinuation { (c: CheckedContinuation<Data?, Never>) in
            self.cont = c
            DispatchQueue.global(qos: .userInitiated).async {
                guard let dev = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: dev) else { self.finish(nil); return }
                let output = AVCapturePhotoOutput()
                self.session.beginConfiguration()
                self.session.sessionPreset = .photo
                if self.session.canAddInput(input) { self.session.addInput(input) }
                if self.session.canAddOutput(output) { self.session.addOutput(output) }
                self.session.commitConfiguration()
                self.session.startRunning()
                // a moment for the camera to adjust its exposure
                Thread.sleep(forTimeInterval: 1.0)
                output.capturePhoto(with: AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg]), delegate: self)
                DispatchQueue.global().asyncAfter(deadline: .now() + 6) { self.finish(nil) }
            }
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        finish(photo.fileDataRepresentation().flatMap { ImageShrink.jpeg($0, maxSide: 1024) })
    }

    private let lock = NSLock()
    private func finish(_ d: Data?) {
        lock.lock(); let c = cont; cont = nil; lock.unlock()
        guard let c else { return }
        session.stopRunning()
        c.resume(returning: d)
    }
}

// MARK: - Screen: one screenshot, on request

enum ImageShrink {
    static func jpeg(_ data: Data, maxSide: CGFloat) -> Data? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil), let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return data }
        return jpeg(img, maxSide: maxSide)
    }
    static func jpeg(_ img: CGImage, maxSide: CGFloat) -> Data? {
        let w = CGFloat(img.width), h = CGFloat(img.height)
        let k = min(1, maxSide / max(w, h))
        let nw = Int(w * k), nh = Int(h * k)
        guard let ctx = CGContext(data: nil, width: nw, height: nh, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: nw, height: nh))
        guard let small = ctx.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: small).representation(using: .jpeg, properties: [.compressionFactor: 0.72])
    }
}


// MARK: - Writing: save a note in Notes, or type into the front app

@MainActor
enum Writer {
    private static func html(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }

    static func makeNote(title: String, text: String) async -> String? {
        let t = title.isEmpty ? "Note" : title
        let lines = text.components(separatedBy: .newlines).map { $0.isEmpty ? "<div><br></div>" : "<div>\(html($0))</div>" }
        let body = "<h1>\(html(t))</h1>" + lines.joined()
        let script = """
        tell application "Notes"
          set n to make new note with properties {body:\(MailAgent.q(body))}
          activate
          show n
        end tell
        return "ok"
        """
        guard await MailAgent.osa(script) != nil else { return nil }
        return "Saved a note called “\(t)” in Notes."
    }

    static func type(_ text: String) async -> String? {
        guard !text.isEmpty else { return nil }
        if let front = AppState.shared.lastExternalApp { front.activate(options: []) }
        try? await Task.sleep(nanoseconds: 450_000_000)
        let pb = NSPasteboard.general, old = pb.string(forType: .string)
        pb.clearContents(); pb.setString(text, forType: .string)
        _ = CommandEngine.shared.runAppleScript("tell application \"System Events\" to keystroke \"v\" using command down")
        try? await Task.sleep(nanoseconds: 600_000_000)
        if let old { pb.clearContents(); pb.setString(old, forType: .string) }
        return "Typed it."
    }
}
