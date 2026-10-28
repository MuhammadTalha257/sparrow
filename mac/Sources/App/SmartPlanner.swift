import Foundation
import AppKit
import SwiftUI
import PDFKit
import Vision
import UniformTypeIdentifiers

// =====================================================================
// MARK: - Smart planner: talk to Zuffi like a person
// When the instant built-in rules don't recognise a request, a fast AI (Groq — free, ~0.3 s;
// or Gemini / ChatGPT) turns whatever you said — any wording, English, Urdu, Hindi, Roman Urdu,
// several things at once — into Zuffi's own commands. Zuffi runs them and answers naturally.
// =====================================================================

@MainActor
final class SmartPlanner {
    static let shared = SmartPlanner()

    struct Plan { let commands: [String]; let say: String }

    private func key(_ k: String) -> String? {
        guard let v = KeychainStore.shared.get(k), !v.isEmpty else { return nil }
        return v
    }
    var isAvailable: Bool { NetStatus.shared.online && (key("groq-api-key") ?? key("gemini-api-key") ?? key("openai-api-key")) != nil }

    private static let commands = """
    open <app or website> · quit <app> · play music · play music on spotify · play <song or artist> · play <song> on spotify · play <query> on youtube
    pause · next song · previous song · volume <0-100> · volume up · volume down · mute
    remind me to <task> at <time> <day> · meeting with <who> <day> at <time> · add task <task> · note <text> · what's on today · my tasks
    save <phone number> as <name> · what's <name>'s number
    search <query> · youtube <query> · weather · prayer times · battery · what time is it · new chat
    remind me to drink water every <n> hours · medicine reminders at <times>
    shut down mac · restart mac · sleep mac · lock screen · turn on wifi · turn off wifi · turn on bluetooth · turn off bluetooth
    brightness up · brightness down · dark mode · light mode · hide everything · screenshot · full screen · close this window · new tab
    put <app> on the left and <app> on the right · run shortcut <name> · type <text>
    start meeting notes · stop meeting notes
    check my emails · read the email from <name> · reply to <name> saying <what to tell them> · send · cancel
    analyse my cv · find <role> jobs in <place> · find jobs for me · tailor my cv for job <n> · apply to job <n> · my job applications · type my email|phone|name|linkedin|cover letter
    check whatsapp · whatsapp <name> saying <text> · reply to <name> on whatsapp saying <text>
    what's on my screen · on screen, <any task to do by clicking and typing in an app or website, with all details>
    """

    private func systemPrompt() -> String {
        let f = DateFormatter(); f.dateFormat = "EEEE d MMMM yyyy, h:mm a"
        let name = AssistantPrefs.displayName
        let app = AppState.shared.lastExternalApp?.localizedName ?? "unknown"
        return """
        You are Zuffi, a warm, quick assistant living on the user's Mac. Now: \(f.string(from: Date())). User: \(name.isEmpty ? "unknown" : name). Front app: \(app).
        Turn what the user said (any language: English, Urdu, Hindi, Punjabi, Roman Urdu, mixed) into Zuffi commands, in order.
        Write every command in ENGLISH using exactly these forms:
        \(Self.commands)
        Rules:
        - Use as few commands as needed. Times like "kal 10 baje" become "at 10am tomorrow".
        - If it's a question or chat (not an action), return no commands and answer in "say" (max 2 short sentences).
        - If you're not sure what they want, return no commands and ask a short question in "say".
        - Never invent actions they didn't ask for. Risky actions (shut down, restart) only if clearly asked.
        - "say": one short, friendly, human sentence confirming what you're doing, in the SAME language and script the user used.
        Reply ONLY with JSON: {"commands": ["..."], "say": "..."}
        """
    }

    func plan(_ text: String) async -> Plan? {
        guard isAvailable else { return nil }
        let t0 = Date()
        var raw: String?
        if let k = key("groq-api-key") { raw = try? await openAIStyle(url: "https://api.groq.com/openai/v1/chat/completions",
                                                                       model: UserDefaults.standard.string(forKey: "groqResolved") ?? "llama-3.3-70b-versatile", key: k, text: text) }
        if raw == nil, let k = key("gemini-api-key") { raw = try? await gemini(key: k, text: text) }
        if raw == nil, let k = key("openai-api-key") { raw = try? await openAIStyle(url: "https://api.openai.com/v1/chat/completions",
                                                                                    model: UserDefaults.standard.string(forKey: "openaiResolved") ?? "gpt-4o-mini", key: k, text: text) }
        guard let raw, let plan = Self.parse(raw) else { return nil }
        appendAppLog("agents.log", String(format: "planner %.2fs: \"%@\" → %@ | %@", Date().timeIntervalSince(t0), text, plan.commands.joined(separator: " ; "), plan.say))
        return plan
    }

    static func parse(_ raw: String) -> Plan? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let a = s.firstIndex(of: "{"), let b = s.lastIndex(of: "}") { s = String(s[a...b]) }
        guard let d = s.data(using: .utf8), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return nil }
        let cmds = (o["commands"] as? [String] ?? []).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return Plan(commands: Array(cmds.prefix(6)), say: (o["say"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func post(_ url: URL, body: [String: Any], headers: [String: String]) async throws -> [String: Any] {
        // Understanding a command (JSON answer) must be quick; a free-text job (summaries) may take longer.
        let json = body["response_format"] != nil || ((body["generationConfig"] as? [String: Any])?["responseMimeType"] != nil)
        var req = URLRequest(url: url, timeoutInterval: json ? 8 : 30)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    private func openAIStyle(url: String, model: String, key: String, text: String) async throws -> String? {
        let j = try await post(URL(string: url)!, body: [
            "model": model, "temperature": 0, "max_tokens": 300,
            "response_format": ["type": "json_object"],
            "messages": [["role": "system", "content": systemPrompt()], ["role": "user", "content": text]],
        ], headers: ["Authorization": "Bearer \(key)"])
        return ((j["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any])?["content"] as? String
    }

    private func gemini(key: String, text: String) async throws -> String? {
        let model = UserDefaults.standard.string(forKey: "geminiResolved") ?? AppState.defaultGeminiModel
        let j = try await post(URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!, body: [
            "system_instruction": ["parts": [["text": systemPrompt()]]],
            "contents": [["role": "user", "parts": [["text": text]]]],
            "generationConfig": model.contains("2.5-flash")
                ? ["temperature": 0, "responseMimeType": "application/json", "thinkingConfig": ["thinkingBudget": 0] as [String: Any]] as [String: Any]
                : ["temperature": 0, "responseMimeType": "application/json"] as [String: Any],
        ], headers: ["x-goog-api-key": key])
        let parts = (((j["candidates"] as? [[String: Any]])?.first?["content"] as? [String: Any])?["parts"] as? [[String: Any]]) ?? []
        return parts.compactMap { $0["text"] as? String }.joined()
    }

    /// A plain text answer from the fast AI (used for meeting summaries).
    func complete(_ prompt: String) async -> String? {
        let msgs: [[String: Any]] = [["role": "user", "content": prompt]]
        if let k = key("groq-api-key"), let j = try? await post(URL(string: "https://api.groq.com/openai/v1/chat/completions")!,
            body: ["model": UserDefaults.standard.string(forKey: "groqResolved") ?? "llama-3.3-70b-versatile", "temperature": 0.2, "messages": msgs],
            headers: ["Authorization": "Bearer \(k)"]),
           let c = ((j["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any])?["content"] as? String { return c }
        if let k = key("gemini-api-key") {
            let model = UserDefaults.standard.string(forKey: "geminiResolved") ?? AppState.defaultGeminiModel
            let genCfg: [String: Any] = model.contains("2.5-flash") ? ["thinkingConfig": ["thinkingBudget": 0] as [String: Any]] : [:]
            if let j = try? await post(URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!,
                                       body: ["contents": [["role": "user", "parts": [["text": prompt]]]], "generationConfig": genCfg], headers: ["x-goog-api-key": k]) {
                let parts = (((j["candidates"] as? [[String: Any]])?.first?["content"] as? [String: Any])?["parts"] as? [[String: Any]]) ?? []
                let t = parts.compactMap { $0["text"] as? String }.joined()
                if !t.isEmpty { return t }
            }
        }
        if let k = key("openai-api-key"), let j = try? await post(URL(string: "https://api.openai.com/v1/chat/completions")!,
            body: ["model": UserDefaults.standard.string(forKey: "openaiResolved") ?? "gpt-4o-mini", "messages": msgs],
            headers: ["Authorization": "Bearer \(k)"]),
           let c = ((j["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any])?["content"] as? String { return c }
        return nil
    }

    /// Runs a plan: every command through Zuffi's own agents, then one natural answer.
    func run(_ plan: Plan) async -> String {
        var results: [String] = []
        for (i, c) in plan.commands.enumerated() {
            var r = await AgentRouter.shared.handle(c)
            if r == nil { r = await WebHub.shared.ask(c) }
            if let r { results.append(r) }
            if i < plan.commands.count - 1, c.lowercased().hasPrefix("open") { try? await Task.sleep(nanoseconds: 900_000_000) }
        }
        // Information answers (time, weather, numbers…) are worth saying; plain confirmations are covered by "say".
        let info = results.filter { r in
            !["Opening", "Closing", "Playing", "Paused", "Next", "Previous", "Volume", "Muted", "Searching", "Done"].contains { r.hasPrefix($0) }
        }
        if plan.commands.isEmpty { return plan.say }
        if !info.isEmpty && info.joined().count < 260 { return ([plan.say] + info).filter { !$0.isEmpty }.joined(separator: " ") }
        return plan.say.isEmpty ? (results.joined(separator: " ")) : plan.say
    }
}

// =====================================================================
// MARK: - Study: turn anything into notes, flashcards and a quiz · lecture notes · explain my screen · deadlines
// =====================================================================

/// Reads the words out of a file: PDF (scanned pages too), Word, RTF, PowerPoint, text, photos of notes.
enum StudyText {
    static func extract(_ url: URL) async -> String {
        let ext = url.pathExtension.lowercased()
        if ["png", "jpg", "jpeg", "heic", "webp", "tiff", "gif"].contains(ext) {
            guard let img = NSImage(contentsOf: url), let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return "" }
            return await ocr(cg)
        }
        if ext == "pdf", let doc = PDFDocument(url: url) {
            let text = doc.string ?? ""
            if text.trimmingCharacters(in: .whitespacesAndNewlines).count > 80 { return text }
            // scanned: read each page with OCR
            var out: [String] = []
            for i in 0..<min(doc.pageCount, 40) {
                guard let page = doc.page(at: i) else { continue }
                let b = page.bounds(for: .mediaBox), k: CGFloat = 2
                let img = NSImage(size: NSSize(width: b.width * k, height: b.height * k))
                img.lockFocus()
                NSColor.white.setFill(); NSRect(origin: .zero, size: img.size).fill()
                if let ctx = NSGraphicsContext.current?.cgContext { ctx.scaleBy(x: k, y: k); page.draw(with: .mediaBox, to: ctx) }
                img.unlockFocus()
                if let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) { out.append(await ocr(cg)) }
            }
            return out.joined(separator: "\n\n")
        }
        if ext == "pptx" { return pptx(url) }
        if ["docx", "doc", "rtf", "odt", "html", "htm"].contains(ext), let a = try? NSAttributedString(url: url, options: [:], documentAttributes: nil) { return a.string }
        if let d = try? Data(contentsOf: url) { return String(data: d, encoding: .utf8) ?? String(data: d, encoding: .isoLatin1) ?? "" }
        return ""
    }
    /// Words in a picture (printed or neat handwriting).
    static func ocr(_ cg: CGImage) async -> String {
        let req = VNRecognizeTextRequest()
        req.recognitionLevel = .accurate
        req.usesLanguageCorrection = true
        req.automaticallyDetectsLanguage = true
        do { try VNImageRequestHandler(cgImage: cg).perform([req]) } catch { return "" }
        return (req.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }
    /// PowerPoint: the text on each slide.
    static func pptx(_ url: URL) -> String {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("zuffi-pptx-\(UUID().uuidString)")
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/unzip"); p.arguments = ["-q", "-o", url.path, "ppt/slides/*.xml", "-d", dir.path]
        try? p.run(); p.waitUntilExit()
        defer { try? FileManager.default.removeItem(at: dir) }
        let slides = ((try? FileManager.default.contentsOfDirectory(atPath: dir.appendingPathComponent("ppt/slides").path)) ?? [])
            .filter { $0.hasSuffix(".xml") }.sorted { (Int($0.filter(\.isNumber)) ?? 0) < (Int($1.filter(\.isNumber)) ?? 0) }
        return slides.enumerated().map { i, f in
            let xml = (try? String(contentsOf: dir.appendingPathComponent("ppt/slides/\(f)"), encoding: .utf8)) ?? ""
            let words = xml.components(separatedBy: "<a:t>").dropFirst().compactMap { $0.components(separatedBy: "</a:t>").first }
            return "Slide \(i + 1): " + words.joined(separator: " ")
        }.joined(separator: "\n")
    }
}

struct StudyCard: Codable, Identifiable, Hashable { var id = UUID().uuidString; var q: String; var a: String; var box = 0; var due = Date() }
struct StudyQuestion: Codable, Identifiable, Hashable { var id = UUID().uuidString; var q: String; var options: [String]; var answer: Int; var why: String }
struct StudyDeck: Codable, Identifiable, Hashable {
    var id = UUID().uuidString
    var title: String
    var created = Date()
    var source = ""
    var summary = ""
    var keyPoints: [String] = []
    var cards: [StudyCard] = []
    var quiz: [StudyQuestion] = []
    var best: Int?
}
struct Deadline: Codable, Identifiable, Hashable {
    var id = UUID().uuidString
    var title: String
    var subject = ""
    var date: Date
    var kind = "Assignment"          // Assignment · Exam · Test
    var done = false
    var plan: [String] = []
}

@MainActor
final class StudyHub: ObservableObject {
    static let shared = StudyHub()
    @Published var decks: [StudyDeck] = TeamStore.load("study-decks", [StudyDeck]()) { didSet { TeamStore.save("study-decks", decks) } }
    @Published var deadlines: [Deadline] = TeamStore.load("study-deadlines", [Deadline]()) { didSet { TeamStore.save("study-deadlines", deadlines) } }
    @Published var busy = ""
    @Published var output = ""            // the last tool's answer (explain, essay feedback, references, photo text)
    @Published var recording = false
    @Published var streak: Int = UserDefaults.standard.integer(forKey: "studyStreak")
    private var timer: Timer?

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1800, repeats: true) { _ in Task { @MainActor in StudyHub.shared.remind() } }
        remind()
    }

    /// A day before and on the day: a reminder in the notch.
    private func remind() {
        let cal = Calendar.current
        for d in deadlines where !d.done {
            let days = cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: cal.startOfDay(for: d.date)).day ?? 99
            guard days == 0 || days == 1 || days == 3 else { continue }
            let key = "dl-\(d.id)-\(days)"
            guard !UserDefaults.standard.bool(forKey: key) else { continue }
            UserDefaults.standard.set(true, forKey: key)
            let when = days == 0 ? "today" : days == 1 ? "tomorrow" : "in 3 days"
            NotchInbox.shared.add("\(d.kind) \(when): \(d.title)", d.subject.isEmpty ? "You've got this — open Study for your plan." : d.subject, icon: "graduationcap.fill", action: "dashboard")
            MacStatus.shared.toast("\(d.kind) \(when)", d.title, icon: "graduationcap.fill")
        }
    }

    func studied() {
        let today = ZuffiBusiness.iso(Date()), last = UserDefaults.standard.string(forKey: "studyLastDay") ?? ""
        guard last != today else { return }
        let yesterday = ZuffiBusiness.iso(Date().addingTimeInterval(-86400))
        streak = last == yesterday ? streak + 1 : 1
        UserDefaults.standard.set(streak, forKey: "studyStreak"); UserDefaults.standard.set(today, forKey: "studyLastDay")
        BunnyFaceCenter.shared.show(.happy, for: 3)
    }

    // MARK: anything → notes, flashcards and a quiz

    func makeDeck(title: String, text: String, source: String, lecture: Bool = false) async {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count > 60 else { output = "I couldn't find enough words in that to study from."; return }
        busy = "Reading it and making your notes…"
        defer { busy = "" }
        let prompt = """
        You are a brilliant, patient teacher. From the material below make study materials for a student.
        \(lecture ? "It is a recording of a lecture — tidy it into clear lecture notes and add the questions most likely to come up in an exam." : "")
        Use ONLY what is in the material; don't add facts that aren't there. Write in the material's language.
        JSON only:
        {"title":"short title","summary":"clear summary in 6-10 short lines","keyPoints":["the most important points, 6-12"],
         "cards":[{"q":"question or term","a":"short answer"}],
         "quiz":[{"q":"question","options":["A","B","C","D"],"answer":0,"why":"one line why"}]}
        Make 12-20 cards and 8-10 quiz questions (answer = index of the right option; vary the position).
        MATERIAL:
        \(t.prefix(60_000))
        """
        guard let raw = await AIService.shared.oneShot(prompt), let j = AIService.jsonIn(raw) as? [String: Any] else {
            output = "I couldn't make the notes this time — check that an AI is set up in Settings (Ollama works offline, or add your own key)."; return
        }
        var deck = StudyDeck(title: (j["title"] as? String) ?? title, source: source)
        deck.summary = (j["summary"] as? String) ?? ""
        deck.keyPoints = (j["keyPoints"] as? [String]) ?? []
        deck.cards = ((j["cards"] as? [[String: Any]]) ?? []).compactMap { d in
            guard let q = d["q"] as? String, let a = d["a"] as? String else { return nil }; return StudyCard(q: q, a: a)
        }
        deck.quiz = ((j["quiz"] as? [[String: Any]]) ?? []).compactMap { d in
            guard let q = d["q"] as? String, let o = d["options"] as? [String], o.count >= 2 else { return nil }
            let ans = (d["answer"] as? Int) ?? Int((d["answer"] as? String) ?? "") ?? 0
            return StudyQuestion(q: q, options: o, answer: min(max(0, ans), o.count - 1), why: (d["why"] as? String) ?? "")
        }
        decks.insert(deck, at: 0)
        output = ""
        studied()
    }

    /// A dropped file (its callback comes on a background thread).
    nonisolated static func load(_ item: NSItemProvider) {
        _ = item.loadObject(ofClass: URL.self) { url, _ in if let url { Task { @MainActor in await StudyHub.shared.fromFile(url) } } }
    }

    func fromFile(_ url: URL) async {
        busy = "Reading \(url.lastPathComponent)…"
        let text = await StudyText.extract(url)
        await makeDeck(title: url.deletingPathExtension().lastPathComponent, text: text, source: url.lastPathComponent)
    }

    func fromYouTube(_ link: String) async {
        busy = "Watching the video (reading its subtitles)…"
        guard let v = await ZuffiReach.read(link, agent: ZuffiTeam.shared.agent("research-synthesist") ?? ZuffiTeam.manager, runID: nil) else {
            busy = ""; output = "I couldn't open that video or page."; return
        }
        await makeDeck(title: v.title, text: v.text, source: link, lecture: true)
    }

    // MARK: lecture → notes

    func toggleLecture() {
        if !recording {
            _ = MeetingNotes.shared.start(); recording = true
            NotchInbox.shared.add("Recording your lecture", "Press Stop in Study when it ends", icon: "waveform.badge.mic", action: nil)
        } else {
            recording = false
            Task { @MainActor in
                busy = "Writing up the lecture…"
                _ = await MeetingNotes.shared.stop()
                let t = MeetingNotes.shared.lastTranscript
                let f = DateFormatter(); f.dateFormat = "d MMM, HH:mm"
                await makeDeck(title: "Lecture — \(f.string(from: Date()))", text: t, source: "Lecture recording", lecture: true)
            }
        }
    }

    // MARK: explain what's on my screen, step by step (teach, don't just answer)

    func explainScreen(_ ask: String = "") async {
        busy = "Looking at your screen…"
        defer { busy = "" }
        guard let shot = await ScreenGrab.main() else { output = "I couldn't see the screen — allow Zuffi in System Settings → Privacy & Security → Screen Recording."; return }
        let r = await AIService.shared.oneShot("""
            You are a kind, expert tutor. Look at the student's screen. \(ask.isEmpty ? "Find the question or topic they're working on." : "They ask: \(ask)")
            Teach it step by step so they understand: what it's asking, the idea behind it, each step with a short reason, \
            then the final answer, then one quick question to check they understood. Use simple words. If it's a test they're taking right now, explain the idea without giving the final answer.
            """, system: "You are a patient tutor who explains clearly. Plain text with short lines and numbered steps.", image: (mime: "image/jpeg", base64: shot.jpeg.base64EncodedString()))
        output = zClean(r ?? "I couldn't explain it this time — check an AI that can see pictures is set up (Claude, ChatGPT or Gemini key).")
        studied()
    }

    // MARK: small tools

    func photoToText(_ url: URL) async {
        busy = "Reading the photo…"; defer { busy = "" }
        let t = await StudyText.extract(url)
        output = t.isEmpty ? "I couldn't find words in that picture." : t
    }
    func essayFeedback(_ essay: String) async {
        busy = "Reading your writing…"; defer { busy = "" }
        let words = essay.split(whereSeparator: { $0.isWhitespace }).count
        let r = await AIService.shared.oneShot("""
            Give feedback on this student's writing like a supportive teacher. Don't rewrite it for them.
            1) What's good (2-3 points) 2) Structure and argument 3) Clarity and grammar — quote the exact sentence and show the fix 4) The 3 most important things to improve.
            WRITING (\(words) words):
            \(essay.prefix(30000))
            """, system: "You are an encouraging writing teacher. Plain text, short lines.")
        output = "Word count: \(words)\n\n" + zClean(r ?? "I couldn't read it this time.")
    }
    func reference(_ source: String, style: String) async {
        busy = "Making the reference…"; defer { busy = "" }
        var info = source
        if source.hasPrefix("http"), let page = await ZuffiReach.read(source, agent: ZuffiTeam.manager, runID: nil) { info = "URL: \(source)\nTITLE: \(page.title)\nPAGE START:\n\(page.text.prefix(3000))" }
        let today = DateFormatter.localizedString(from: Date(), dateStyle: .long, timeStyle: .none)
        let r = await AIService.shared.oneShot("""
            Make a \(style) reference for this source, and the in-text citation. Use only details you can see (author, year, title, site, publisher); \
            write "n.d." if there's no date. Accessed date: \(today). Reply with:
            Reference: …
            In-text: …
            SOURCE:
            \(info)
            """, system: "You format academic references exactly. Plain text.")
        output = zClean(r ?? "I couldn't make it this time.")
    }

    // MARK: deadlines → a study plan

    func plan(_ id: String) async {
        guard let i = deadlines.firstIndex(where: { $0.id == id }) else { return }
        let d = deadlines[i]
        busy = "Making your plan…"; defer { busy = "" }
        let days = max(1, Calendar.current.dateComponents([.day], from: Date(), to: d.date).day ?? 1)
        let r = await AIService.shared.oneShot("""
            Make a realistic study plan for a student. \(d.kind): \(d.title)\(d.subject.isEmpty ? "" : " (\(d.subject))"), in \(days) days.
            One line per day, like "Mon 3 Nov — 45 min: …". Short sessions, include review days and a rest. JSON only: ["line", ...]
            """) ?? ""
        if let arr = AIService.jsonIn(r) as? [String], let j = deadlines.firstIndex(where: { $0.id == id }) { deadlines[j].plan = arr }
    }
}

// MARK: Study page

struct StudyPage: View {
    var light: Bool
    @ObservedObject private var hub = StudyHub.shared
    @State private var tab = "Study a file"
    @State private var openDeck: StudyDeck?
    @State private var link = ""
    @State private var ask = ""
    @State private var essay = ""
    @State private var refSource = ""
    @State private var refStyle = "Harvard"
    @State private var dlTitle = ""
    @State private var dlSubject = ""
    @State private var dlDate = Date().addingTimeInterval(7 * 86400)
    @State private var dlKind = "Assignment"
    @State private var dropping = false
    private var T: HubTheme { HubTheme(light: light) }
    private let tabs = ["Study a file", "Lecture notes", "Explain my screen", "Deadlines", "Tools"]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 8) {
                ForEach(tabs, id: \.self) { t in
                    Button { tab = t } label: {
                        Text(t).font(HubFont.p(13)).foregroundColor(tab == t ? .white : T.text).padding(.horizontal, 14).frame(height: 32)
                            .background(Capsule().fill(tab == t ? HubTheme.blue : T.content))
                    }.buttonStyle(.plain)
                }
                Spacer()
                if hub.streak > 0 { Label("\(hub.streak)-day streak", systemImage: "flame.fill").font(HubFont.p(13)).foregroundColor(Color(hex: "#F5B963")) }
            }
            if !hub.busy.isEmpty { HStack(spacing: 8) { ProgressView().controlSize(.small); Text(hub.busy).font(HubFont.p(13, .regular)) } }
            switch tab {
            case "Lecture notes": lecturePane
            case "Explain my screen": explainPane
            case "Deadlines": deadlinesPane
            case "Tools": toolsPane
            default: filePane
            }
            if !hub.output.isEmpty && (tab == "Explain my screen" || tab == "Tools") {
                DashCard(title: "Answer", light: light) {
                    ChatRichText(text: hub.output)
                    HStack {
                        DashButton(title: "Copy", icon: "doc.on.doc", light: light) { ResultExport.copy(hub.output) }
                        DashButton(title: "Save", icon: "arrow.down.circle", filled: false, light: light) { ResultExport.save("Zuffi study", hub.output, pdf: true) }
                    }
                }
            }
            if !hub.decks.isEmpty && (tab == "Study a file" || tab == "Lecture notes") {
                DashCard(title: "Your study sets", sub: "Open one for notes, flashcards and a quiz", light: light) {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        ForEach(hub.decks) { d in
                            Button { openDeck = d } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(d.title).font(HubFont.p(14, .semibold)).lineLimit(2).multilineTextAlignment(.leading)
                                    Text("\(d.cards.count) cards · \(d.quiz.count) questions\(d.best.map { " · best \($0)/\(d.quiz.count)" } ?? "")").font(HubFont.p(11.5, .regular)).foregroundColor(T.inactive)
                                    Text(d.created.formatted(date: .abbreviated, time: .omitted)).font(HubFont.p(11, .regular)).foregroundColor(T.inactive)
                                }
                                .padding(14).frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
                                .background(RoundedRectangle(cornerRadius: 14).fill(T.content)).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                            .contextMenu { Button("Delete") { hub.decks.removeAll { $0.id == d.id } } }
                        }
                    }
                }
            }
        }
        .sheet(item: $openDeck) { d in DeckView(deckID: d.id, light: light) { openDeck = nil } }
        .onAppear { hub.start() }
    }

    private var filePane: some View {
        DashCard(title: "Study from any file", sub: "Drop lecture slides, a PDF, Word file, PowerPoint or a photo of your notes. Zuffi makes a summary, key points, flashcards and a practice quiz.", light: light) {
            VStack(spacing: 10) {
                Image(systemName: "tray.and.arrow.down.fill").font(.system(size: 30)).foregroundColor(HubTheme.blue)
                Text("Drop a file here").font(HubFont.p(15, .semibold))
                DashButton(title: "Choose a file", icon: "doc.badge.plus", light: light) {
                    let p = NSOpenPanel(); p.allowedContentTypes = [.pdf, .image, .plainText, .rtf, .item]
                    if p.runModal() == .OK, let u = p.url { Task { await hub.fromFile(u) } }
                }
            }
            .frame(maxWidth: .infinity).padding(.vertical, 28)
            .background(RoundedRectangle(cornerRadius: 16).strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [7])).foregroundColor(dropping ? HubTheme.blue : T.border))
            .onDrop(of: [.fileURL], isTargeted: $dropping) { items in
                guard let item = items.first else { return false }
                StudyHub.load(item)
                return true
            }
            HStack(spacing: 10) {
                TextField("…or paste a YouTube lecture link", text: $link).textFieldStyle(.roundedBorder)
                DashButton(title: "Make notes", icon: "play.rectangle.fill", light: light) { let l = link; link = ""; Task { await hub.fromYouTube(l) } }
            }
            if !hub.output.isEmpty { Text(hub.output).font(HubFont.p(12.5, .regular)).foregroundColor(Color(hex: "#EF6B6B")) }
        }
    }

    private var lecturePane: some View {
        DashCard(title: "Lecture notes", sub: "Record a class or an online lecture. When it ends, Zuffi writes clean notes, key points, likely exam questions and flashcards.", light: light) {
            HStack(spacing: 16) {
                Button { hub.toggleLecture() } label: {
                    HStack(spacing: 10) {
                        Image(systemName: hub.recording ? "stop.fill" : "record.circle").font(.system(size: 18))
                        Text(hub.recording ? "Stop and write my notes" : "Start recording").font(HubFont.p(15, .semibold))
                    }
                    .foregroundColor(.white).padding(.horizontal, 22).frame(height: 48)
                    .background(Capsule().fill(hub.recording ? Color(hex: "#E5534B") : HubTheme.blue))
                }.buttonStyle(.plain)
                if hub.recording { Label("Listening…", systemImage: "waveform").font(HubFont.p(13)).foregroundColor(Color(hex: "#E5534B")) }
            }
            Text("Tip: for an online lecture, play it out loud on your Mac. The recording itself isn't kept — only the notes.").font(HubFont.p(12, .regular)).foregroundColor(T.inactive)
        }
    }

    private var explainPane: some View {
        DashCard(title: "Explain my screen", sub: "Open your homework or a question, then press Explain. Zuffi teaches it step by step — so you really get it.", light: light) {
            HStack(spacing: 10) {
                TextField("Optional: what don't you get? e.g. why is step 2 like that?", text: $ask).textFieldStyle(.roundedBorder)
                DashButton(title: "Explain", icon: "eye.fill", light: light) { let q = ask; ask = ""; Task { await hub.explainScreen(q) } }
            }
        }
    }

    private var deadlinesPane: some View {
        DashCard(title: "Deadlines & exams", sub: "Add them once. Zuffi counts down, makes a study plan and reminds you 3 days before, the day before and on the day.", light: light) {
            HStack(spacing: 10) {
                Picker("", selection: $dlKind) { Text("Assignment").tag("Assignment"); Text("Exam").tag("Exam"); Text("Test").tag("Test") }.labelsHidden().frame(width: 120)
                TextField("What is it? e.g. Biology essay", text: $dlTitle).textFieldStyle(.roundedBorder)
                TextField("Subject", text: $dlSubject).textFieldStyle(.roundedBorder).frame(width: 140)
                DatePicker("", selection: $dlDate, displayedComponents: [.date, .hourAndMinute]).labelsHidden()
                DashButton(title: "Add", icon: "plus", light: light) {
                    let t = dlTitle.trimmingCharacters(in: .whitespaces); guard !t.isEmpty else { return }
                    let d = Deadline(title: t, subject: dlSubject, date: dlDate, kind: dlKind)
                    hub.deadlines.append(d); hub.deadlines.sort { $0.date < $1.date }; dlTitle = ""
                    Task { await hub.plan(d.id) }
                }
            }
            ForEach(hub.deadlines.filter { !$0.done }) { d in
                let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: Calendar.current.startOfDay(for: d.date)).day ?? 0
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        VStack(spacing: 0) {
                            Text(days < 0 ? "!" : "\(days)").font(HubFont.p(20, .semibold))
                            Text(days == 1 ? "day" : "days").font(HubFont.p(10, .regular))
                        }
                        .foregroundColor(.white).frame(width: 54, height: 54)
                        .background(RoundedRectangle(cornerRadius: 12).fill(days <= 1 ? Color(hex: "#E5534B") : days <= 3 ? Color(hex: "#F5B963") : HubTheme.blue))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(d.title).font(HubFont.p(14.5, .semibold))
                            Text("\(d.kind)\(d.subject.isEmpty ? "" : " · \(d.subject)") · \(d.date.formatted(date: .abbreviated, time: .shortened))").font(HubFont.p(11.5, .regular)).foregroundColor(T.inactive)
                        }
                        Spacer()
                        Button("Plan") { Task { await hub.plan(d.id) } }.buttonStyle(.plain).foregroundColor(HubTheme.blue).font(HubFont.p(12))
                        Button("Done ✓") { if let i = hub.deadlines.firstIndex(where: { $0.id == d.id }) { hub.deadlines[i].done = true; hub.studied() } }.buttonStyle(.plain).foregroundColor(Color(hex: "#3DBE7E")).font(HubFont.p(12))
                    }
                    if !d.plan.isEmpty {
                        VStack(alignment: .leading, spacing: 3) { ForEach(d.plan, id: \.self) { l in Text("• " + l).font(HubFont.p(12.5, .regular)) } }.padding(.leading, 66)
                    }
                }
                .padding(12).background(RoundedRectangle(cornerRadius: 14).fill(T.content))
            }
        }
    }

    private var toolsPane: some View {
        VStack(alignment: .leading, spacing: 20) {
            DashCard(title: "Photo of notes → text", sub: "Handwritten notes, a whiteboard or a book page into text you can copy.", light: light) {
                DashButton(title: "Choose a photo", icon: "camera.viewfinder", light: light) {
                    let p = NSOpenPanel(); p.allowedContentTypes = [.image, .pdf]
                    if p.runModal() == .OK, let u = p.url { Task { await hub.photoToText(u) } }
                }
            }
            DashCard(title: "Writing feedback", sub: "Paste your essay. Zuffi gives teacher-style feedback and the word count — it doesn't write it for you.", light: light) {
                TextEditor(text: $essay).font(HubFont.p(13, .regular)).frame(height: 120).overlay(RoundedRectangle(cornerRadius: 8).stroke(T.border))
                DashButton(title: "Get feedback", icon: "text.badge.checkmark", light: light) { let e = essay; Task { await hub.essayFeedback(e) } }
            }
            DashCard(title: "References", sub: "Paste a link (or a book's details) and get the reference and in-text citation.", light: light) {
                HStack(spacing: 10) {
                    TextField("https://… or Author, Title, Year, Publisher", text: $refSource).textFieldStyle(.roundedBorder)
                    Picker("", selection: $refStyle) { ForEach(["Harvard", "APA 7", "MLA 9", "Chicago"], id: \.self) { Text($0).tag($0) } }.labelsHidden().frame(width: 110)
                    DashButton(title: "Make", icon: "quote.opening", light: light) { let s = refSource, st = refStyle; Task { await hub.reference(s, style: st) } }
                }
            }
        }
    }
}

/// One study set: summary · flashcards (with spaced review) · quiz.
struct DeckView: View {
    let deckID: String
    var light: Bool
    var done: () -> Void
    @ObservedObject private var hub = StudyHub.shared
    @State private var mode = "Notes"
    @State private var cardIndex = 0
    @State private var flipped = false
    @State private var qIndex = 0
    @State private var picked: Int?
    @State private var score = 0
    private var T: HubTheme { HubTheme(light: light) }
    private var deck: StudyDeck? { hub.decks.first { $0.id == deckID } }
    private var dueCards: [StudyCard] { (deck?.cards ?? []).filter { $0.due <= Date() } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(deck?.title ?? "").font(HubFont.p(19, .semibold)).lineLimit(1)
                Spacer()
                Picker("", selection: $mode) { Text("Notes").tag("Notes"); Text("Flashcards").tag("Flashcards"); Text("Quiz").tag("Quiz") }.pickerStyle(.segmented).frame(width: 300)
                Button("Done", action: done).keyboardShortcut(.cancelAction)
            }
            if let d = deck {
                switch mode {
                case "Flashcards": cards(d)
                case "Quiz": quiz(d)
                default:
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Summary").font(HubFont.p(15, .semibold))
                            Text(d.summary).font(HubFont.p(14, .regular)).textSelection(.enabled)
                            Text("Key points").font(HubFont.p(15, .semibold))
                            ForEach(d.keyPoints, id: \.self) { p in Text("• " + p).font(HubFont.p(14, .regular)).textSelection(.enabled) }
                            HStack {
                                DashButton(title: "Copy notes", icon: "doc.on.doc", light: light) { ResultExport.copy(notesText(d)) }
                                DashButton(title: "Save as PDF", icon: "arrow.down.circle", filled: false, light: light) { ResultExport.save(d.title, notesText(d), pdf: true) }
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .padding(24).frame(width: 760, height: 600)
    }

    private func notesText(_ d: StudyDeck) -> String {
        "Summary\n\(d.summary)\n\nKey points\n" + d.keyPoints.map { "- " + $0 }.joined(separator: "\n") + "\n\nFlashcards\n" + d.cards.map { "- \($0.q) — \($0.a)" }.joined(separator: "\n")
    }

    @ViewBuilder private func cards(_ d: StudyDeck) -> some View {
        let list = dueCards.isEmpty ? d.cards : dueCards
        if list.isEmpty { Text("No cards.").foregroundColor(T.inactive) } else {
            let c = list[min(cardIndex, list.count - 1)]
            VStack(spacing: 16) {
                Text(dueCards.isEmpty ? "All reviewed for now — practising anyway" : "\(dueCards.count) to review").font(HubFont.p(12, .regular)).foregroundColor(T.inactive)
                Button { withAnimation(.spring(response: 0.4)) { flipped.toggle() } } label: {
                    Text(flipped ? c.a : c.q).font(HubFont.p(flipped ? 17 : 21, flipped ? .regular : .semibold)).multilineTextAlignment(.center)
                        .padding(30).frame(maxWidth: .infinity, minHeight: 280)
                        .background(RoundedRectangle(cornerRadius: 20).fill(flipped ? HubTheme.blue.opacity(0.18) : T.content))
                        .rotation3DEffect(.degrees(flipped ? 360 : 0), axis: (x: 0, y: 1, z: 0))
                }.buttonStyle(.plain)
                Text(flipped ? "How well did you know it?" : "Click the card to see the answer").font(HubFont.p(12, .regular)).foregroundColor(T.inactive)
                if flipped {
                    HStack(spacing: 12) {
                        DashButton(title: "Again", filled: false, light: light) { grade(c, ok: false, count: list.count) }
                        DashButton(title: "Got it", icon: "checkmark", light: light) { grade(c, ok: true, count: list.count) }
                    }
                }
            }
        }
    }
    private func grade(_ c: StudyCard, ok: Bool, count: Int) {
        guard let di = hub.decks.firstIndex(where: { $0.id == deckID }), let ci = hub.decks[di].cards.firstIndex(where: { $0.id == c.id }) else { return }
        let box = ok ? min(5, c.box + 1) : 0
        let days = [0, 1, 3, 7, 14, 30][box]
        hub.decks[di].cards[ci].box = box
        hub.decks[di].cards[ci].due = ok ? Date().addingTimeInterval(Double(days) * 86400) : Date().addingTimeInterval(60)
        flipped = false; cardIndex = (cardIndex + 1) % max(1, count)
        hub.studied()
    }

    @ViewBuilder private func quiz(_ d: StudyDeck) -> some View {
        if d.quiz.isEmpty { Text("No quiz questions.").foregroundColor(T.inactive) }
        else if qIndex >= d.quiz.count {
            VStack(spacing: 14) {
                Text("You scored \(score) / \(d.quiz.count)").font(HubFont.p(26, .semibold))
                Text(score == d.quiz.count ? "Perfect! 🎉" : score * 2 >= d.quiz.count ? "Nice work — review the ones you missed." : "Keep going — try the flashcards, then the quiz again.").font(HubFont.p(14, .regular))
                DashButton(title: "Try again", icon: "arrow.clockwise", light: light) { qIndex = 0; score = 0; picked = nil }
            }.frame(maxWidth: .infinity).padding(.top, 60)
        } else {
            let q = d.quiz[qIndex]
            VStack(alignment: .leading, spacing: 12) {
                Text("Question \(qIndex + 1) of \(d.quiz.count)").font(HubFont.p(12, .regular)).foregroundColor(T.inactive)
                Text(q.q).font(HubFont.p(18, .semibold))
                ForEach(Array(q.options.enumerated()), id: \.offset) { i, o in
                    Button { if picked == nil { picked = i; if i == q.answer { score += 1 } } } label: {
                        HStack { Text(o).font(HubFont.p(14, .regular)).multilineTextAlignment(.leading); Spacer()
                            if let p = picked, i == q.answer { Image(systemName: "checkmark.circle.fill").foregroundColor(Color(hex: "#3DBE7E")) }
                            else if picked == i { Image(systemName: "xmark.circle.fill").foregroundColor(Color(hex: "#EF6B6B")) } }
                            .padding(14).background(RoundedRectangle(cornerRadius: 12).fill(picked == nil ? T.content : i == q.answer ? Color(hex: "#3DBE7E").opacity(0.18) : picked == i ? Color(hex: "#EF6B6B").opacity(0.18) : T.content))
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
                if picked != nil {
                    Text(q.why).font(HubFont.p(13, .regular)).foregroundColor(T.inactive)
                    DashButton(title: qIndex + 1 == d.quiz.count ? "See score" : "Next", icon: "arrow.right", light: light) {
                        picked = nil; qIndex += 1
                        if qIndex >= d.quiz.count, let di = hub.decks.firstIndex(where: { $0.id == deckID }) { hub.decks[di].best = max(hub.decks[di].best ?? 0, score); hub.studied() }
                    }
                }
            }
        }
    }
}
