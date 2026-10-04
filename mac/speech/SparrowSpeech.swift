// SparrowSpeech — Sparrow's fast, natural, offline voice for the Mac.
// Runs the sherpa-onnx engine (k2-fsa, Apache-2.0) natively, so a sentence is ready in a fraction of a second:
//   English → Kokoro (Apache-2.0)        Urdu / Roman Urdu / Hindi / Punjabi → Meta MMS-TTS (CC-BY-NC 4.0)
// Talks to Sparrow as JSON lines over stdin/stdout.
//
// in : {"cmd":"say","id":1,"text":"…","model":"kokoro","sid":3,"speed":1.0} · {"cmd":"stop"} · {"cmd":"warm","model":"kokoro"}
//      {"cmd":"render","text":"…","model":"kokoro","sid":3,"path":"/tmp/x.wav"}
// out: {"ev":"ready"} · {"ev":"start","id":1} · {"ev":"end","id":1} · {"ev":"error","id":1,"msg":"…"} · {"ev":"speed",…}
import Foundation
import AVFoundation

setvbuf(stdout, nil, _IOLBF, 0)

func emit(_ obj: [String: Any]) {
    guard let d = try? JSONSerialization.data(withJSONObject: obj), let s = String(data: d, encoding: .utf8) else { return }
    print(s); fflush(stdout)
}

let base = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1]
                                   : (CommandLine.arguments[0] as NSString).deletingLastPathComponent)

/// Keeps C strings alive for as long as the engine needs them.
final class CStrings {
    private var ptrs: [UnsafeMutablePointer<CChar>] = []
    func make(_ s: String) -> UnsafePointer<CChar> { let p = strdup(s)!; ptrs.append(p); return UnsafePointer(p) }
    deinit { ptrs.forEach { free($0) } }
}

final class Voice {
    let tts: OpaquePointer
    let rate: Int
    let strings: CStrings
    init?(model: String) {
        let s = CStrings()
        var c = SherpaOnnxOfflineTtsConfig()
        let threads = Int32(max(1, min(4, ProcessInfo.processInfo.activeProcessorCount - 1)))
        c.model.num_threads = threads
        c.model.provider = s.make("cpu")
        c.max_num_sentences = 1
        let fm = FileManager.default
        func onnx(in dir: URL) -> String? {
            let files = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
            return (files.first { $0.hasSuffix(".int8.onnx") } ?? files.first { $0.hasSuffix(".onnx") }).map { dir.appendingPathComponent($0).path }
        }
        if model == "kokoro" {
            let d = base.appendingPathComponent("kokoro")
            guard let m = onnx(in: d) else { return nil }
            c.model.kokoro.model = s.make(m)
            c.model.kokoro.voices = s.make(d.appendingPathComponent("voices.bin").path)
            c.model.kokoro.tokens = s.make(d.appendingPathComponent("tokens.txt").path)
            c.model.kokoro.data_dir = s.make(d.appendingPathComponent("espeak-ng-data").path)
            c.model.kokoro.length_scale = 1.0
            let lex = d.appendingPathComponent("lexicon-us-en.txt").path
            if fm.fileExists(atPath: lex) { c.model.kokoro.lexicon = s.make(lex) }
            c.model.kokoro.lang = s.make("en-us")
        } else {
            let d = base.appendingPathComponent("mms-\(model)")
            guard let m = onnx(in: d) else { return nil }
            c.model.vits.model = s.make(m)
            c.model.vits.tokens = s.make(d.appendingPathComponent("tokens.txt").path)
            c.model.vits.noise_scale = 0.667
            c.model.vits.noise_scale_w = 0.8
            c.model.vits.length_scale = 1.0
        }
        guard let t = SherpaOnnxCreateOfflineTts(&c) else { return nil }
        tts = t
        rate = Int(SherpaOnnxOfflineTtsSampleRate(t))
        strings = s
    }
    func generate(_ text: String, sid: Int, speed: Float) -> [Float] {
        guard let a = SherpaOnnxOfflineTtsGenerate(tts, text, Int32(sid), speed) else { return [] }
        defer { SherpaOnnxDestroyOfflineTtsGeneratedAudio(a) }
        guard let p = a.pointee.samples, a.pointee.n > 0 else { return [] }
        return Array(UnsafeBufferPointer(start: p, count: Int(a.pointee.n)))
    }
}

final class Speaker {
    let genQ = DispatchQueue(label: "sparrow.speech.gen", qos: .userInitiated)
    var voices: [String: Voice] = [:]          // touched only on genQ
    let engine = AVAudioEngine()
    let player = AVAudioPlayerNode()
    var connectedRate = 0
    var turn = 0                               // main thread
    var speedLogs = 0

    init() {
        engine.attach(player)
    }

    func voice(_ model: String) -> Voice? {     // genQ
        if let v = voices[model] { return v }
        let t0 = Date()
        guard let v = Voice(model: model) else { return nil }
        voices[model] = v
        emit(["ev": "loaded", "model": model, "ms": Int(Date().timeIntervalSince(t0) * 1000)])
        return v
    }

    func sentences(_ text: String) -> [String] {
        var clean = text.replacingOccurrences(of: #"[*_#`>•]"#, with: "", options: .regularExpression)
        clean = clean.replacingOccurrences(of: #"\s*\n+\s*"#, with: ". ", options: .regularExpression)
        let ns = clean as NSString
        let re = try! NSRegularExpression(pattern: #"[^.!?۔।]+[.!?۔।]*"#)
        var out: [String] = []
        for m in re.matches(in: clean, range: NSRange(location: 0, length: ns.length)) {
            var p = ns.substring(with: m.range).trimmingCharacters(in: .whitespaces)
            if p.isEmpty { continue }
            while p.count > 220, let cut = p.prefix(200).lastIndex(where: { $0 == "," || $0 == " " }) {
                out.append(String(p[..<cut]).trimmingCharacters(in: .whitespaces)); p = String(p[p.index(after: cut)...]).trimmingCharacters(in: .whitespaces)
            }
            if let last = out.last, last.count < 25 { out[out.count - 1] = last + " " + p } else { out.append(p) }
        }
        // start talking sooner: speak a long first sentence's first clause on its own
        if let f = out.first, f.count > 70, let r = f.range(of: #"[,;:]\s"#, options: .regularExpression),
           f.distance(from: f.startIndex, to: r.lowerBound) > 12 {
            out[0] = String(f[..<r.upperBound]).trimmingCharacters(in: .whitespaces)
            out.insert(String(f[r.upperBound...]).trimmingCharacters(in: .whitespaces), at: 1)
        }
        return out
    }

    func ensureOutput(rate: Int) -> AVAudioFormat? {
        guard let fmt = AVAudioFormat(standardFormatWithSampleRate: Double(rate), channels: 1) else { return nil }
        if connectedRate != rate {
            engine.disconnectNodeOutput(player)
            engine.connect(player, to: engine.mainMixerNode, format: fmt)
            connectedRate = rate
        }
        if !engine.isRunning { try? engine.start() }
        return fmt
    }

    func stop() {
        turn += 1
        player.stop()
    }

    func say(id: Int, text: String, model: String, sid: Int, speed: Float) {
        stop()
        let my = turn
        let parts = sentences(text)
        guard !parts.isEmpty else { emit(["ev": "end", "id": id]); return }
        var started = false
        var pending = parts.count
        genQ.async {
            guard let v = self.voice(model) else {
                DispatchQueue.main.async { emit(["ev": "error", "id": id, "msg": "voice \(model) unavailable"]) }
                return
            }
            for p in parts {
                var cancelled = false
                DispatchQueue.main.sync { cancelled = my != self.turn }
                if cancelled { return }
                let t0 = Date()
                let samples = v.generate(p, sid: sid, speed: speed)
                let took = Date().timeIntervalSince(t0)
                DispatchQueue.main.async {
                    guard my == self.turn else { return }
                    if self.speedLogs < 15, !samples.isEmpty {
                        self.speedLogs += 1
                        emit(["ev": "speed", "model": model, "audio": Double(samples.count) / Double(v.rate), "took": took])
                    }
                    guard !samples.isEmpty, let fmt = self.ensureOutput(rate: v.rate),
                          let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(samples.count)) else {
                        pending -= 1
                        if pending == 0 { emit(["ev": started ? "end" : "error", "id": id, "msg": "no audio"]) }
                        return
                    }
                    buf.frameLength = AVAudioFrameCount(samples.count)
                    samples.withUnsafeBufferPointer { src in buf.floatChannelData![0].update(from: src.baseAddress!, count: samples.count) }
                    self.player.scheduleBuffer(buf, completionCallbackType: .dataPlayedBack) { _ in
                        DispatchQueue.main.async {
                            guard my == self.turn else { return }
                            pending -= 1
                            if pending == 0 { emit(["ev": "end", "id": id]) }
                        }
                    }
                    if !started { started = true; self.player.play(); emit(["ev": "start", "id": id]) }
                }
            }
        }
    }

    func render(text: String, model: String, sid: Int, path: String) {
        genQ.async {
            guard let v = self.voice(model) else { emit(["ev": "error", "msg": "voice \(model) unavailable"]); return }
            let t0 = Date()
            var all: [Float] = []
            for p in self.sentences(text) { all += v.generate(p, sid: sid, speed: 1); all += [Float](repeating: 0, count: v.rate / 6) }
            let took = Date().timeIntervalSince(t0)
            var d = Data()
            func u32(_ x: UInt32) { var v = x.littleEndian; d.append(Data(bytes: &v, count: 4)) }
            func u16(_ x: UInt16) { var v = x.littleEndian; d.append(Data(bytes: &v, count: 2)) }
            d.append("RIFF".data(using: .ascii)!); u32(UInt32(36 + all.count * 2)); d.append("WAVEfmt ".data(using: .ascii)!)
            u32(16); u16(1); u16(1); u32(UInt32(v.rate)); u32(UInt32(v.rate * 2)); u16(2); u16(16)
            d.append("data".data(using: .ascii)!); u32(UInt32(all.count * 2))
            for s in all { u16(UInt16(bitPattern: Int16(max(-1, min(1, s)) * 32767))) }
            try? d.write(to: URL(fileURLWithPath: path))
            emit(["ev": "rendered", "model": model, "audio": Double(all.count) / Double(v.rate), "took": took, "path": path])
        }
    }

    func handle(_ line: String) {
        guard let d = line.data(using: .utf8), let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
              let cmd = o["cmd"] as? String else { return }
        let model = o["model"] as? String ?? "kokoro"
        let sid = o["sid"] as? Int ?? 3
        switch cmd {
        case "say": say(id: o["id"] as? Int ?? 0, text: o["text"] as? String ?? "", model: model, sid: sid, speed: Float(o["speed"] as? Double ?? 1))
        case "stop": stop()
        case "warm": genQ.async { _ = self.voice(model).map { $0.generate("Hi.", sid: sid, speed: 1) } }
        case "render": render(text: o["text"] as? String ?? "", model: model, sid: sid, path: o["path"] as? String ?? "/tmp/sparrow.wav")
        default: break
        }
    }
}

let speaker = Speaker()
emit(["ev": "ready"])
Thread.detachNewThread {
    while let line = readLine() { DispatchQueue.main.async { speaker.handle(line) } }
    exit(0)
}
RunLoop.main.run()
