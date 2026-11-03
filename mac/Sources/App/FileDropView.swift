import AppKit
import SwiftUI
import Vision
import CoreImage

// MARK: - NSView drag destination
// Wired at the AppKit level in IslandWindowController (not via SwiftUI NSViewRepresentable)
// so it never interferes with SwiftUI hit-testing.

final class FileDropNSView: NSView {
    var onDragEntered: ((CGPoint) -> Void)?
    var onDragUpdated: ((CGPoint) -> Void)?
    var onDragExited:  (() -> Void)?
    var onFilesDropped: (([URL]) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }
    required init?(coder: NSCoder) { fatalError() }

    // Pass all mouse events through — drag-drop uses NSDraggingDestination, not hitTest
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        onDragEntered?(sender.draggingLocation)
        return .copy
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        onDragUpdated?(sender.draggingLocation)
        return .copy
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { onDragExited?() }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], !urls.isEmpty else { return false }
        onFilesDropped?(urls)
        return true
    }
}

// MARK: - File drop handler

enum FileDropHandler {
    @MainActor
    static func handle(urls: [URL], state: AppState) async {
        guard let url = urls.first else { return }
        let name = url.lastPathComponent
        // The notch: a dropped file or picture opens Tools, where you pick what to do with it.
        if NotchDesign.on {
            state.droppedFile = DroppedFile(url: url, name: name)
            state.fileDragOver = false
            state.chooseMode = nil
            state.promptContext = .file(name: name, fileURL: url)
            NotchNav.shared.open("tools")
            SoundEngine.shared.play("approve")
            BunnyFaceCenter.shared.show(.happy, for: 2)
            if !VoiceEngine.shared.speaking { VoiceEngine.shared.speak("Got it! Do you want to ask about it, or change its format?") }
            return
        }

        // Start animation immediately — do NOT block on file copy.
        // Use original URL first; swap to inbox copy once background copy finishes.
        state.droppedFile = DroppedFile(url: url, name: name)
        state.chooseMode = nil
        state.uploadProgress = 0
        state.fileDragOver = false
        state.promptContext = .file(name: name, fileURL: url)

        let dur = 2.4
        UploadSequenceEngine.shared.performDrop(uploadDuration: dur)

        // Copy to inbox in background — update state when done
        let inbox = SparrowPaths.supportDir.appendingPathComponent("inbox")
        Task.detached {
            try? FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
            let dest = inbox.appendingPathComponent(name)
            try? FileManager.default.removeItem(at: dest)
            if (try? FileManager.default.copyItem(at: url, to: dest)) != nil {
                await MainActor.run {
                    state.droppedFile = DroppedFile(url: dest, name: name)
                    state.promptContext = .file(name: name, fileURL: dest)
                    WebHub.shared.rememberFile(dest)       // keep it in Zuffi's memory
                    // A picture → Zuffi looks at it and tells you what it is (searching the web if useful).
                    let ext = dest.pathExtension.lowercased()
                    if ["jpg", "jpeg", "png", "heic", "webp", "gif", "tiff", "bmp"].contains(ext), LiveSession.shared.usable,
                       let raw = try? Data(contentsOf: dest), let jpeg = ImageShrink.jpeg(raw, maxSide: 1280) {
                        LiveSession.shared.start(text: "I'm showing you a picture (\(name)). Tell me what it is in one or two sentences, and search the web if that helps identify it.", image: jpeg)
                    }
                }
            }
        }

        // Drop feedback
        NotificationCenter.default.post(name: .botGulp, object: nil)
        SoundEngine.shared.play("approve")
        NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.happy)
        NotificationCenter.default.post(name: .botMorphTo, object: CGFloat(0))

        state.uploadDuration = dur
        state.uploadStartTime = Date()
        state.view = .uploading  // canvas stays active: uploadActive covers .uploading

        // Canvas timeline from drop:
        //   T_DROP → T_PROG_START : ≈1.30s  gulp + shrink + bar reveal
        //   T_PROG_START → progEnd: dur      progress bar fills
        //   progEnd → growEnd     : 0.70s    Mochi grows back to choose position
        let preProgress = USC.T_PROG_START - USC.T_DROP  // ≈1.30s

        // Tick sounds — delayed to sync with canvas progress start
        Task { @MainActor in
            var lastTens = 0
            let progStart = Date().addingTimeInterval(preProgress)
            while lastTens < 9 {
                try? await Task.sleep(nanoseconds: 80_000_000)
                let approxP = min(1.0, max(0, Date().timeIntervalSince(progStart) / dur))
                let tens = Int(approxP * 10)
                if tens > lastTens {
                    SoundEngine.shared.play("tick")
                    lastTens = tens
                }
            }
        }

        // Wait for canvas progress to complete (gulp/shrink phase + upload duration)
        try? await Task.sleep(nanoseconds: UInt64((preProgress + dur) * 1_000_000_000))

        // Canvas shows checkmark at this point
        SoundEngine.shared.play("approve")
        NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.happy)

        // Wait for grow-back animation + choose overlay settle
        try? await Task.sleep(nanoseconds: UInt64(1_000_000_000))

        // Clean up upload state
        state.uploadProgress = 0
        state.uploadStartTime = nil

        // Switch to choose — canvas stays active (uploadActive covers .choose).
        // Engine deactivates when user clicks a canvas choose button or navigates away.
        state.view = .choose
    }
}


// MARK: - Image studio (like Taby's image editor): everything here runs on this Mac, the picture never leaves it.
//   "make it safe to share" (hides emails, phone numbers, faces, names) · blur the faces · cover a word
//   make it smaller for email · copy the text · remove the background · pretty screenshot · rotate · mark it up
@MainActor
enum ImageStudio {
    static let exts: Set<String> = ["jpg", "jpeg", "png", "heic", "webp", "gif", "tiff", "bmp"]
    static func isImage(_ u: URL) -> Bool { exts.contains(u.pathExtension.lowercased()) }

    enum Job: String, CaseIterable { case safe, faces, smaller, text, cutout, pretty, rotate
        var label: String {
            switch self {
            case .safe: return "Make it safe to share"; case .faces: return "Blur faces"; case .smaller: return "Smaller for email"
            case .text: return "Copy the text"; case .cutout: return "Remove background"; case .pretty: return "Pretty screenshot"; case .rotate: return "Rotate"
            }
        }
    }

    /// Voice / chat: "blur the faces", "make it safe to share", "cover the name Anna", "copy the text from this"…
    static func voice(_ q: String) async -> String? {
        guard let f = AppState.shared.droppedFile, isImage(f.url) else {
            if q.lowercased().range(of: #"^(take|grab|capture) (a |an )?(screenshot|screen ?shot|picture of (my|the) screen)"#, options: .regularExpression) != nil {
                return await screenshot() ? "Got it! What should I do with it — make it safe to share, blur faces, copy the text…?" : "Okay, no screenshot."
            }
            return nil
        }
        let t = q.lowercased()
        if let r = t.range(of: #"^(cover|hide|blur|black out|pixelate)\s+(the\s+)?(name|word|text)\s+(.+)$"#, options: .regularExpression) {
            let word = String(t[r]).replacingOccurrences(of: #"^(cover|hide|blur|black out|pixelate)\s+(the\s+)?(name|word|text)\s+"#, with: "", options: .regularExpression)
            return await run(.safe, on: f.url, word: word)
        }
        let map: [(String, Job)] = [(#"safe to share|hide (my )?(private|personal)|blur (my |the )?(email|phone|number)"#, .safe),
                                    (#"(blur|pixelate|hide) (the )?faces?"#, .faces), (#"smaller|compress|for email|reduce (the )?size"#, .smaller),
                                    (#"copy (the )?text|read the text|text from (this|it)"#, .text), (#"remove (the )?background|cut ?out|no background"#, .cutout),
                                    (#"pretty|beautiful|backdrop|nice screenshot"#, .pretty), (#"\brotate|turn it"#, .rotate)]
        for (pat, job) in map where t.range(of: pat, options: .regularExpression) != nil { return await run(job, on: f.url) }
        return nil
    }

    /// Does the job and saves a new picture in Downloads (your original is never changed). Returns what to tell you.
    static func run(_ job: Job, on url: URL, word: String? = nil) async -> String {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil), let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return "I couldn't open that picture." }
        let base = (url.lastPathComponent as NSString).deletingPathExtension
        switch job {
        case .text:
            let words = await StudyText.ocr(img)
            guard !words.isEmpty else { return "I didn't find any text in it." }
            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(words, forType: .string)
            return "Copied the text — paste it anywhere. It starts: \(words.prefix(80))…"
        case .smaller:
            let s = shrink(img, maxSide: 1600)
            guard let d = jpeg(s, 0.72), let u = save(d, base + " (small).jpg") else { return "That didn't work." }
            reveal(u); return "Done — \(ByteCountFormatter.string(fromByteCount: Int64(d.count), countStyle: .file)), saved in Downloads."
        case .rotate:
            guard let r = rotated(img), let d = png(r), let u = save(d, base + " (rotated).png") else { return "That didn't work." }
            reveal(u); return "Rotated — saved in Downloads."
        case .pretty:
            guard let r = pretty(img), let d = png(r), let u = save(d, base + " (pretty).png") else { return "That didn't work." }
            reveal(u); return "Made it pretty — saved in Downloads."
        case .cutout:
            guard #available(macOS 14.0, *) else { return "Removing the background needs macOS 14 or newer." }
            guard let r = cutout(img), let d = png(r), let u = save(d, base + " (no background).png") else { return "I couldn't find a clear subject to cut out." }
            reveal(u); return "Background removed — saved in Downloads."
        case .safe, .faces:
            let json = await Task.detached { () -> String in
                guard let d = (try? Data(contentsOf: url)) else { return "[]" }
                return WebHub.findPrivateJSON(d.base64EncodedString())
            }.value
            let boxes = (try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]]) ?? []
            var hide: [CGRect] = []
            for b in boxes {
                let k = b["kind"] as? String ?? ""
                let text = (b["text"] as? String ?? "").lowercased()
                let want: Bool
                if let w = word { want = k == "text" && text.contains(w.lowercased()) }
                else if job == .faces { want = k == "face" } else { want = ["face", "email", "phone", "name"].contains(k) }
                if want, let x = (b["x"] as? NSNumber)?.doubleValue, let y = (b["y"] as? NSNumber)?.doubleValue,
                   let w = (b["w"] as? NSNumber)?.doubleValue, let h = (b["h"] as? NSNumber)?.doubleValue {
                    hide.append(CGRect(x: x, y: y, width: w, height: h))
                }
            }
            guard !hide.isEmpty else { return word != nil ? "I couldn't find \"\(word!)\" in it." : job == .faces ? "I didn't find any faces." : "I didn't find anything private in it — it looks safe to share." }
            guard let r = pixelate(img, hide), let d = png(r), let u = save(d, base + " (safe).png") else { return "That didn't work." }
            reveal(u); return "Hid \(hide.count) thing\(hide.count == 1 ? "" : "s") — saved in Downloads."
        }
    }

    // MARK: screenshot
    /// Drag over part of the screen (or press Space for a window) — it lands in Zuffi, ready to edit.
    static func screenshot() async -> Bool {
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("Screenshot \(Int(Date().timeIntervalSince1970)).png")
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture"); p.arguments = ["-i", "-x", out.path]
            p.terminationHandler = { _ in c.resume() }
            do { try p.run() } catch { c.resume() }
        }
        guard FileManager.default.fileExists(atPath: out.path) else { return false }
        let st = AppState.shared
        st.droppedFile = DroppedFile(url: out, name: out.lastPathComponent)
        st.promptContext = .file(name: out.lastPathComponent, fileURL: out)
        NotchNav.shared.open("tools")
        return true
    }
    static func markup(_ url: URL) {
        let preview = URL(fileURLWithPath: "/System/Applications/Preview.app")
        NSWorkspace.shared.open([url], withApplicationAt: preview, configuration: NSWorkspace.OpenConfiguration())
    }

    // MARK: drawing helpers
    private static func ctx(_ w: Int, _ h: Int) -> CGContext? {
        CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }
    private static func shrink(_ img: CGImage, maxSide: CGFloat) -> CGImage {
        let s = min(1, maxSide / CGFloat(max(img.width, img.height)))
        guard s < 1 else { return img }
        let w = Int(CGFloat(img.width) * s), h = Int(CGFloat(img.height) * s)
        guard let c = ctx(w, h) else { return img }
        c.interpolationQuality = .high; c.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        return c.makeImage() ?? img
    }
    private static func rotated(_ img: CGImage) -> CGImage? {
        guard let c = ctx(img.height, img.width) else { return nil }
        c.translateBy(x: CGFloat(img.height), y: 0); c.rotate(by: .pi / 2)
        c.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
        return c.makeImage()
    }
    /// Normalised boxes (top-left origin) → chunky pixels in those places.
    private static func pixelate(_ img: CGImage, _ boxes: [CGRect]) -> CGImage? {
        let W = img.width, H = img.height
        guard let c = ctx(W, H) else { return nil }
        c.draw(img, in: CGRect(x: 0, y: 0, width: W, height: H))
        for b in boxes {
            let r = CGRect(x: b.minX * CGFloat(W), y: b.minY * CGFloat(H), width: b.width * CGFloat(W), height: b.height * CGFloat(H))
                .insetBy(dx: -4, dy: -4).integral.intersection(CGRect(x: 0, y: 0, width: W, height: H))
            guard r.width > 2, r.height > 2, let piece = img.cropping(to: r) else { continue }
            let cell = max(6, Int(min(r.width, r.height) / 6))
            let sw = max(1, Int(r.width) / cell), sh = max(1, Int(r.height) / cell)
            guard let small = ctx(sw, sh) else { continue }
            small.interpolationQuality = .medium; small.draw(piece, in: CGRect(x: 0, y: 0, width: sw, height: sh))
            guard let tiny = small.makeImage() else { continue }
            c.interpolationQuality = .none
            c.draw(tiny, in: CGRect(x: r.minX, y: CGFloat(H) - r.maxY, width: r.width, height: r.height))     // drawing space starts bottom-left
        }
        return c.makeImage()
    }
    private static func pretty(_ img: CGImage) -> CGImage? {
        let pad = Int(CGFloat(max(img.width, img.height)) * 0.08)
        let W = img.width + pad * 2, H = img.height + pad * 2
        guard let c = ctx(W, H) else { return nil }
        let colors = [CGColor(red: 1, green: 0.84, blue: 0.78, alpha: 1), CGColor(red: 0.84, green: 0.80, blue: 1, alpha: 1)] as CFArray
        if let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 1]) {
            c.drawLinearGradient(g, start: .zero, end: CGPoint(x: W, y: H), options: [])
        }
        let r = CGRect(x: pad, y: pad, width: img.width, height: img.height)
        let radius = CGFloat(max(img.width, img.height)) * 0.018
        c.saveGState()
        c.setShadow(offset: CGSize(width: 0, height: -pad / 6), blur: CGFloat(pad) / 2, color: CGColor(gray: 0, alpha: 0.35))
        c.addPath(CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)); c.setFillColor(CGColor(gray: 1, alpha: 1)); c.fillPath()
        c.restoreGState()
        c.addPath(CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)); c.clip()
        c.draw(img, in: r)
        return c.makeImage()
    }
    @available(macOS 14.0, *)
    private static func cutout(_ img: CGImage) -> CGImage? {
        let req = VNGenerateForegroundInstanceMaskRequest()
        let h = VNImageRequestHandler(cgImage: img)
        guard (try? h.perform([req])) != nil, let res = req.results?.first,
              let buf = try? res.generateMaskedImage(ofInstances: res.allInstances, from: h, croppedToInstancesExtent: false) else { return nil }
        let ci = CIImage(cvPixelBuffer: buf)
        return CIContext().createCGImage(ci, from: ci.extent)
    }
    private static func png(_ img: CGImage) -> Data? { NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:]) }
    private static func jpeg(_ img: CGImage, _ q: Double) -> Data? { NSBitmapImageRep(cgImage: img).representation(using: .jpeg, properties: [.compressionFactor: q]) }
    private static func save(_ d: Data, _ name: String) -> URL? {
        let dir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        var dest = dir.appendingPathComponent(name), n = 2
        while FileManager.default.fileExists(atPath: dest.path) { dest = dir.appendingPathComponent("\((name as NSString).deletingPathExtension) \(n).\((name as NSString).pathExtension)"); n += 1 }
        do { try d.write(to: dest); return dest } catch { return nil }
    }
    private static func reveal(_ u: URL) { NSWorkspace.shared.activateFileViewerSelecting([u]) }
}
