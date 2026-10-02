// SparrowVoice — the Mac's own speech engine for the Sparrow app.
// Listens with Apple's speech recognition (the same engine as Siri dictation, on-device when possible)
// and speaks with Apple's natural voices. Talks to the app as JSON lines over stdin/stdout.
//
// in : {"cmd":"listen","context":["Gmail","Spotify",…]} · {"cmd":"stop"} · {"cmd":"say","text":"…","gender":"female","rate":0.5}
//      {"cmd":"hush"} · {"cmd":"voices"}
// out: {"ev":"auth","speech":true,"mic":true} · {"ev":"partial","text":"…"} · {"ev":"final","text":"…"}
//      {"ev":"speaking","on":true} · {"ev":"voices","list":[…]} · {"ev":"error","msg":"…"}
import Foundation
import AVFoundation
import Speech

setvbuf(stdout, nil, _IOLBF, 0)

func emit(_ obj: [String: Any]) {
    guard let d = try? JSONSerialization.data(withJSONObject: obj), let s = String(data: d, encoding: .utf8) else { return }
    print(s)
    fflush(stdout)
}

final class Engine: NSObject, AVSpeechSynthesizerDelegate {
    let recognizer = SFSpeechRecognizer(locale: Locale(identifier: Locale.current.identifier.hasPrefix("en") ? Locale.current.identifier : "en-GB"))
        ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    let audio = AVAudioEngine()
    let synth = AVSpeechSynthesizer()
    var request: SFSpeechAudioBufferRecognitionRequest?
    var task: SFSpeechRecognitionTask?
    var wantListening = false
    var speaking = false
    var heard = ""
    var generation = 0
    var silence: Timer?
    var refresh: Timer?
    var context: [String] = ["Sparrow", "hey Sparrow", "Gmail", "Spotify", "WhatsApp", "YouTube", "Chrome", "Safari", "Finder",
                             "Visual Studio Code", "Claude", "ChatGPT", "remind me", "meeting", "volume up", "volume down", "next song"]

    override init() {
        super.init()
        synth.delegate = self
        NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: audio, queue: .main) { [weak self] _ in
            guard let self, self.wantListening else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self.start() }
        }
    }

    // MARK: permissions
    func authorize(_ done: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { st in
            let speechOK = st == .authorized
            AVCaptureDevice.requestAccess(for: .audio) { micOK in
                DispatchQueue.main.async {
                    emit(["ev": "auth", "speech": speechOK, "mic": micOK])
                    done(speechOK && micOK)
                }
            }
        }
    }

    // MARK: listening
    func listen() {
        wantListening = true
        authorize { ok in if ok { self.start() } }
    }

    func start() {
        guard wantListening, !speaking else { return }
        guard let recognizer, recognizer.isAvailable else {
            emit(["ev": "error", "msg": "Speech recognition isn't ready yet"])
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self.start() }
            return
        }
        pause()
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.contextualStrings = Array(context.prefix(100))
        if #available(macOS 13, *) { req.addsPunctuation = false }
        if recognizer.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }
        request = req
        let node = audio.inputNode
        let format = node.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { emit(["ev": "error", "msg": "No microphone found"]); return }
        node.installTap(onBus: 0, bufferSize: 1024, format: format) { buf, _ in req.append(buf) }
        audio.prepare()
        do { try audio.start() } catch {
            emit(["ev": "error", "msg": "Couldn't use the microphone: \(error.localizedDescription)"])
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self.start() }
            return
        }
        heard = ""
        generation += 1
        let gen = generation
        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let failed = error != nil
            DispatchQueue.main.async { self?.onResult(text, final: isFinal || failed, gen: gen) }
        }
        // Apple limits one recognition session to about a minute — refresh it regularly.
        refresh?.invalidate()
        refresh = Timer.scheduledTimer(withTimeInterval: 50, repeats: false) { [weak self] _ in
            guard let self, self.heard.isEmpty else { return }
            self.start()
        }
    }

    func pause() {
        generation += 1
        silence?.invalidate(); refresh?.invalidate()
        task?.cancel(); task = nil
        request?.endAudio(); request = nil
        if audio.isRunning { audio.stop() }
        audio.inputNode.removeTap(onBus: 0)
    }

    func stop() { wantListening = false; pause() }

    func onResult(_ text: String?, final: Bool, gen: Int) {
        guard gen == generation else { return }
        if let text, !text.isEmpty {
            heard = text
            emit(["ev": "partial", "text": text])
        }
        silence?.invalidate()
        if final { finish(); return }
        // When you stop talking for a moment, send what you said.
        let words = heard.split(separator: " ").count
        silence = Timer.scheduledTimer(withTimeInterval: words <= 3 ? 0.8 : 1.1, repeats: false) { [weak self] _ in self?.finish() }
    }

    func finish() {
        silence?.invalidate()
        let said = heard.trimmingCharacters(in: .whitespacesAndNewlines)
        heard = ""
        if !said.isEmpty { emit(["ev": "final", "text": said]) }
        if wantListening { DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { self.start() } }   // fresh transcript
    }

    // MARK: speaking (natural voices, gentle pauses)
    func bestVoice(gender: String) -> AVSpeechSynthesisVoice? {
        let lang = "en"
        let wanted: AVSpeechSynthesisVoiceGender = gender == "male" ? .male : .female
        let all = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix(lang) && !$0.identifier.contains("eloquence") && !$0.identifier.contains("speech.synthesis.voice") }
        let fav = ["Zoe", "Ava", "Serena", "Samantha", "Allison", "Susan", "Kate", "Evan", "Nathan", "Tom", "Daniel", "Oliver", "Alex", "Arthur"]
        func rank(_ v: AVSpeechSynthesisVoice) -> Int {
            (v.quality == .premium ? 0 : v.quality == .enhanced ? 100 : 200) + (v.gender == wanted ? 0 : 50) + (fav.firstIndex { v.name.hasPrefix($0) } ?? 30)
        }
        return all.min { rank($0) < rank($1) }
    }

    func say(_ text: String, gender: String, rate: Double) {
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        let esc = text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
        var body = esc.replacingOccurrences(of: #"([.!?])\s+"#, with: "$1<break time=\"280ms\"/> ", options: .regularExpression)
        body = body.replacingOccurrences(of: #":\s+"#, with: ":<break time=\"160ms\"/> ", options: .regularExpression)
        let u: AVSpeechUtterance
        if #available(macOS 13, *), let s = AVSpeechUtterance(ssmlRepresentation: "<speak>\(body)</speak>") { u = s } else { u = AVSpeechUtterance(string: text) }
        let v = bestVoice(gender: gender)
        u.voice = v
        u.rate = Float(v?.quality == .default ? rate * 0.94 : rate)
        u.pitchMultiplier = gender == "male" ? 0.98 : 1.04
        u.volume = 0.95
        speaking = true
        if wantListening { pause() }            // never hear ourselves
        emit(["ev": "speaking", "on": true])
        synth.speak(u)
    }

    func speechDone() {
        speaking = false
        emit(["ev": "speaking", "on": false])
        if wantListening { DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self.start() } }
    }
    func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) { DispatchQueue.main.async { self.speechDone() } }
    func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel u: AVSpeechUtterance) { DispatchQueue.main.async { self.speechDone() } }

    func voices() {
        let list = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("en") }.map {
            ["name": $0.name, "id": $0.identifier, "quality": $0.quality == .premium ? "premium" : $0.quality == .enhanced ? "enhanced" : "basic"]
        }
        emit(["ev": "voices", "list": list, "basicOnly": !list.contains { $0["quality"] != "basic" }])
    }

    func handle(_ line: String) {
        guard let d = line.data(using: .utf8), let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any], let cmd = o["cmd"] as? String else { return }
        switch cmd {
        case "listen":
            if let c = o["context"] as? [String] { context = Array(Set(context + c)) }
            listen()
        case "stop": stop()
        case "say": say(o["text"] as? String ?? "", gender: o["gender"] as? String ?? "female", rate: o["rate"] as? Double ?? 0.5)
        case "hush": synth.stopSpeaking(at: .immediate)
        case "voices": voices()
        default: break
        }
    }
}

let engine = Engine()
emit(["ev": "ready"])
Thread.detachNewThread {
    while let line = readLine() {
        DispatchQueue.main.async { engine.handle(line) }
    }
    exit(0)   // the app closed
}
RunLoop.main.run()
