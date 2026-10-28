import SwiftUI
import AVFoundation
import Vision
import CoreImage
import UniformTypeIdentifiers

// =====================================================================
// MARK: - Liquid glass for every macOS
//
// On macOS 26 (Tahoe) Zuffi uses Apple's own Liquid Glass. On macOS 14–15 this draws the same
// feel by hand: a real blur of what's behind, a tinted body, a bright sheen across the top,
// a soft coloured glow inside, a light rim that catches the light and a gentle lift on hover.
// (Same look as liquidGL on the phone / web app.)
// =====================================================================

struct LiquidGlass<S: InsettableShape>: ViewModifier {
    var shape: S
    var tint: Color? = nil
    var glow: Color = Color(hex: "#F58FA8")
    var interactive = false
    @State private var hover = false

    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            content
                .glassEffect(interactive ? Glass.regular.tint(tint).interactive() : Glass.regular.tint(tint), in: shape)
        } else { drawn(content) }
        #else
        drawn(content)
        #endif
    }

    private func drawn(_ content: Content) -> some View {
        content
            .background(
                ZStack {
                    shape.fill(.ultraThinMaterial)                                   // real blur of what's behind
                    shape.fill(LinearGradient(colors: [(tint ?? .white).opacity(tint == nil ? 0.13 : 0.34), (tint ?? .white).opacity(tint == nil ? 0.03 : 0.12)],
                                              startPoint: .top, endPoint: .bottom))   // glass body
                    shape.fill(LinearGradient(stops: [.init(color: .white.opacity(hover ? 0.36 : 0.26), location: 0),
                                                      .init(color: .white.opacity(0.07), location: 0.34),
                                                      .init(color: .clear, location: 0.52)], startPoint: .top, endPoint: .bottom))   // sheen
                    shape.fill(RadialGradient(colors: [glow.opacity(hover ? 0.28 : 0.16), .clear], center: .bottomTrailing, startRadius: 0, endRadius: 180))   // inner glow
                }
            )
            .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.75), .white.opacity(0.10), .white.opacity(0.30)],
                                                       startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))   // rim light
            .overlay(shape.inset(by: 1.5).strokeBorder(Color.white.opacity(0.07), lineWidth: 1))                             // inner rim
            .shadow(color: .black.opacity(0.28), radius: hover ? 18 : 12, y: hover ? 9 : 6)
            .scaleEffect(interactive && hover ? 1.03 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: hover)
            .onHover { if interactive { hover = $0 } }
    }
}

extension View {
    func liquidGlass<S: InsettableShape>(_ shape: S, tint: Color? = nil, glow: Color = Color(hex: "#F58FA8"), interactive: Bool = false) -> some View {
        modifier(LiquidGlass(shape: shape, tint: tint, glow: glow, interactive: interactive))
    }
}

/// Glass for the side buttons on Zuffi's home: circle / rounded square / capsule.
struct SideGlass: ViewModifier {
    var round: Bool
    var square: Bool
    var tint: Color
    func body(content: Content) -> some View {
        Group {
            if round && square { content.liquidGlass(RoundedRectangle(cornerRadius: 10, style: .continuous), tint: tint.opacity(0.35), glow: tint, interactive: true) }
            else if round { content.liquidGlass(Circle(), tint: tint.opacity(0.35), glow: tint, interactive: true) }
            else { content.liquidGlass(Capsule(), tint: tint.opacity(0.35), glow: tint, interactive: true) }
        }
        .shadow(color: tint.opacity(0.35), radius: 7)
    }
}

// =====================================================================
// MARK: - Try-On: nails on your own hand, and a new hair colour — live on the camera
// Hands: Apple Vision hand pose (21 points per hand, both hands), smoothed so the nails don't shake.
// Hair: Vision person segmentation + face position + your hair's own colour to find the hair, then recoloured keeping its shine.
// =====================================================================

struct TryOnImage: @unchecked Sendable { let img: CGImage }

/// Keeps a moving point steady without lag (the "one euro" filter).
struct OneEuro {
    var minCutoff = 1.2, beta = 0.02, dCutoff = 1.0
    private var x: Double?, dx = 0.0, t: Double?
    mutating func filter(_ value: Double, at time: Double) -> Double {
        guard let px = x, let pt = t, time > pt else { x = value; t = time; return value }
        let dt = time - pt
        func a(_ c: Double) -> Double { let r = 2 * Double.pi * c * dt; return r / (r + 1) }
        let d = (value - px) / dt
        dx = dx + a(dCutoff) * (d - dx)
        let cutoff = minCutoff + beta * abs(dx)
        let v = px + a(cutoff) * (value - px)
        x = v; t = time
        return v
    }
}

enum NailDesigns {
    struct Design: Identifiable { let id: String; let name: String; let img: CGImage }
    static func draw(_ w: Int = 120, _ h: Int = 200, _ body: (CGContext, CGFloat, CGFloat) -> Void) -> CGImage {
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        body(ctx, CGFloat(w), CGFloat(h))
        return ctx.makeImage()!
    }
    static func c(_ hex: String) -> CGColor { NSColor(Color(hex: hex)).usingColorSpace(.deviceRGB)?.cgColor ?? .black }
    static func solid(_ hex: String) -> CGImage { draw { x, w, h in x.setFillColor(c(hex)); x.fill(CGRect(x: 0, y: 0, width: w, height: h)) } }
    static func gradient(_ a: String, _ b: String) -> CGImage {
        draw { x, w, h in
            let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [c(a), c(b)] as CFArray, locations: [0, 1])!
            x.drawLinearGradient(g, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: h), options: [])
        }
    }
    static let all: [Design] = [
        Design(id: "nude", name: "Nude", img: solid("#E8B9A4")),
        Design(id: "red", name: "Classic red", img: solid("#B5121B")),
        Design(id: "pink", name: "Pink", img: solid("#F27BA6")),
        Design(id: "black", name: "Black", img: solid("#141414")),
        Design(id: "lilac", name: "Lilac", img: solid("#B9A2E6")),
        Design(id: "french", name: "French tip", img: draw { x, w, h in
            x.setFillColor(c("#F4D6CC")); x.fill(CGRect(x: 0, y: 0, width: w, height: h))
            x.setFillColor(c("#FFFFFF")); let p = CGMutablePath()
            p.move(to: CGPoint(x: 0, y: h * 0.72)); p.addQuadCurve(to: CGPoint(x: w, y: h * 0.72), control: CGPoint(x: w / 2, y: h * 0.62)); p.addLine(to: CGPoint(x: w, y: h)); p.addLine(to: CGPoint(x: 0, y: h)); p.closeSubpath()
            x.addPath(p); x.fillPath() }),
        Design(id: "ombre", name: "Pink ombré", img: gradient("#F7D7DF", "#E0457B")),
        Design(id: "sunset", name: "Sunset", img: gradient("#FFB36B", "#C4378A")),
        Design(id: "chrome", name: "Chrome", img: draw { x, w, h in
            let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [c("#8E9AAF"), c("#F4F6FA"), c("#9AA6BB"), c("#E8ECF3")] as CFArray, locations: [0, 0.35, 0.65, 1])!
            x.drawLinearGradient(g, start: .zero, end: CGPoint(x: w, y: h), options: []) }),
        Design(id: "glitter", name: "Gold glitter", img: draw { x, w, h in
            x.setFillColor(c("#2B1E16")); x.fill(CGRect(x: 0, y: 0, width: w, height: h))
            var r = SystemRandomNumberGenerator()
            for _ in 0..<420 { let s = CGFloat.random(in: 1...3.2, using: &r); x.setFillColor(c(["#F7D774", "#FFF1B8", "#D4A43A"].randomElement(using: &r)!)); x.fillEllipse(in: CGRect(x: .random(in: 0...w, using: &r), y: .random(in: 0...h, using: &r), width: s, height: s)) } }),
        Design(id: "marble", name: "Marble", img: draw { x, w, h in
            x.setFillColor(c("#F6F4F2")); x.fill(CGRect(x: 0, y: 0, width: w, height: h))
            x.setStrokeColor(c("#9C9A98")); x.setLineWidth(1.4)
            for i in 0..<6 { let p = CGMutablePath(); let y0 = CGFloat(i) * h / 5
                p.move(to: CGPoint(x: 0, y: y0)); p.addCurve(to: CGPoint(x: w, y: y0 + 30), control1: CGPoint(x: w * 0.3, y: y0 + 40), control2: CGPoint(x: w * 0.6, y: y0 - 30)); x.addPath(p); x.strokePath() } }),
        Design(id: "dots", name: "Polka dots", img: draw { x, w, h in
            x.setFillColor(c("#F5A3B5")); x.fill(CGRect(x: 0, y: 0, width: w, height: h)); x.setFillColor(c("#FFFFFF"))
            for row in 0..<8 { for col in 0..<4 { x.fillEllipse(in: CGRect(x: CGFloat(col) * 32 + (row % 2 == 0 ? 6 : 22), y: CGFloat(row) * 26 + 6, width: 11, height: 11)) } } }),
    ]
}

final class TryOnCamera: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    static let shared = TryOnCamera()
    @Published var frame: TryOnImage?
    @Published var hint = "Starting the camera…"
    @Published var running = false

    private let lock = NSLock()
    private var _mode = "nails"
    private var _design: CGImage? = NailDesigns.all[1].img
    private var _hair: CIColor? = CIColor(red: 0.55, green: 0.12, blue: 0.16)
    private var _strength: Double = 0.75
    private var _lift: Double = 0
    var mode: String { get { lock.withLock { _mode } } set { lock.withLock { _mode = newValue } } }
    var design: CGImage? { get { lock.withLock { _design } } set { lock.withLock { _design = newValue } } }
    var hair: CIColor? { get { lock.withLock { _hair } } set { lock.withLock { _hair = newValue } } }
    var strength: Double { get { lock.withLock { _strength } } set { lock.withLock { _strength = newValue } } }
    var lift: Double { get { lock.withLock { _lift } } set { lock.withLock { _lift = newValue } } }

    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "zuffi.tryon", qos: .userInitiated)
    private let ci = CIContext(options: [.cacheIntermediates: false])
    private var configured = false
    private var smooth: [String: OneEuro] = [:]
    private var lastFound = 0.0
    private var last: CGImage?

    func start() {
        AVCaptureDevice.requestAccess(for: .video) { ok in
            guard ok else { DispatchQueue.main.async { self.hint = "Allow the camera: System Settings → Privacy & Security → Camera → Zuffi." }; return }
            self.queue.async {
                if !self.configured { self.configure() }
                if !self.session.isRunning { self.session.startRunning() }
                DispatchQueue.main.async { self.running = true }
            }
        }
    }
    func stop() { queue.async { self.session.stopRunning(); DispatchQueue.main.async { self.running = false } } }

    private func configure() {
        configured = true
        session.beginConfiguration()
        session.sessionPreset = .hd1280x720
        let dev = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) ?? AVCaptureDevice.default(for: .video)
        if let dev, let input = try? AVCaptureDeviceInput(device: dev), session.canAddInput(input) { session.addInput(input) }
        let out = AVCaptureVideoDataOutput()
        out.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        out.alwaysDiscardsLateVideoFrames = true
        out.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(out) { session.addOutput(out) }
        session.commitConfiguration()
    }

    /// A still of what you see now (with the nails or hair colour).
    func snapshot() -> CGImage? { lock.withLock { last } }

    func captureOutput(_ output: AVCaptureOutput, didOutput sb: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pb = CMSampleBufferGetImageBuffer(sb) else { return }
        let w = CVPixelBufferGetWidth(pb), h = CVPixelBufferGetHeight(pb)
        let t = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sb))
        // selfie view: mirrored
        var img = CIImage(cvPixelBuffer: pb).transformed(by: CGAffineTransform(scaleX: -1, y: 1).translatedBy(x: -CGFloat(w), y: 0))
        let mode = self.mode
        var message = ""
        if mode == "hair" {
            let (out, msg) = hairPass(pb, img, w, h)
            img = out; message = msg
        }
        guard let cg = ci.createCGImage(img, from: CGRect(x: 0, y: 0, width: w, height: h)) else { return }
        var final = cg
        if mode == "nails" {
            let (out, msg) = nailPass(pb, cg, w, h, t)
            final = out; message = msg
        }
        lock.withLock { last = final }
        let box = TryOnImage(img: final)
        DispatchQueue.main.async { self.frame = box; if self.hint != message { self.hint = message } }
    }

    // MARK: nails

    private typealias J = VNHumanHandPoseObservation.JointName
    private static let fingers: [(J, J, J, J?)] = [
        (.thumbTip, .thumbIP, .thumbMP, nil), (.indexTip, .indexDIP, .indexPIP, .middlePIP), (.middleTip, .middleDIP, .middlePIP, .ringPIP),
        (.ringTip, .ringDIP, .ringPIP, .middlePIP), (.littleTip, .littleDIP, .littlePIP, .ringPIP),
    ]

    private func nailPass(_ pb: CVPixelBuffer, _ frame: CGImage, _ w: Int, _ h: Int, _ t: Double) -> (CGImage, String) {
        let req = VNDetectHumanHandPoseRequest(); req.maximumHandCount = 2
        try? VNImageRequestHandler(cvPixelBuffer: pb, orientation: .up).perform([req])
        let hands = req.results ?? []
        guard !hands.isEmpty, let design = self.design,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else {
            if t - lastFound > 0.6 { smooth.removeAll() }
            return (frame, "Hold up your hand — back of the hand to the camera, fingers a little apart")
        }
        lastFound = t
        ctx.draw(frame, in: CGRect(x: 0, y: 0, width: w, height: h))
        ctx.interpolationQuality = .high
        var drawn = 0
        for (hi, hand) in hands.enumerated() {
            guard let pts = try? hand.recognizedPoints(.all) else { continue }
            func p(_ j: J) -> CGPoint? {
                guard let q = pts[j], q.confidence > 0.35 else { return nil }
                let key = "\(hi)-\(j.rawValue.rawValue)"
                var fx = smooth[key + "x"] ?? OneEuro(), fy = smooth[key + "y"] ?? OneEuro()
                let x = fx.filter((1 - q.location.x) * Double(w), at: t), y = fy.filter(q.location.y * Double(h), at: t)
                smooth[key + "x"] = fx; smooth[key + "y"] = fy
                return CGPoint(x: x, y: y)
            }
            for (tipJ, dipJ, pipJ, nbJ) in Self.fingers {
                guard let tip = p(tipJ), let dip = p(dipJ) else { continue }
                let dx = tip.x - dip.x, dy = tip.y - dip.y
                let len = hypot(dx, dy)
                guard len > 6 else { continue }
                let thumb = tipJ == .thumbTip
                var width = len * (thumb ? 0.78 : 0.66)
                if let nb = nbJ.flatMap(p), let pip = p(pipJ) { width = min(width, max(len * 0.42, hypot(nb.x - pip.x, nb.y - pip.y) * 0.62)) }
                let length = len * (thumb ? 0.72 : 0.74)
                let center = CGPoint(x: dip.x + dx * 0.6, y: dip.y + dy * 0.6)
                let angle = atan2(dy, dx) - .pi / 2
                Self.drawNail(ctx, design, center, width, length, angle)
                drawn += 1
            }
        }
        return (ctx.makeImage() ?? frame, drawn == 0 ? "Turn your hand so your nails face the camera" : "")
    }

    static func drawNail(_ ctx: CGContext, _ design: CGImage, _ c: CGPoint, _ w: CGFloat, _ l: CGFloat, _ angle: CGFloat) {
        ctx.saveGState()
        ctx.translateBy(x: c.x, y: c.y); ctx.rotate(by: angle)
        let rect = CGRect(x: -w / 2, y: -l / 2, width: w, height: l)
        // a nail shape: straight-ish sides, rounded at the tip and gently at the cuticle
        let path = CGMutablePath()
        let r = w * 0.5
        path.move(to: CGPoint(x: -w / 2, y: -l / 2 + w * 0.18))
        path.addQuadCurve(to: CGPoint(x: w / 2, y: -l / 2 + w * 0.18), control: CGPoint(x: 0, y: -l / 2 - w * 0.12))
        path.addLine(to: CGPoint(x: w / 2, y: l / 2 - r))
        path.addArc(center: CGPoint(x: 0, y: l / 2 - r), radius: r, startAngle: 0, endAngle: .pi, clockwise: false)
        path.closeSubpath()
        // soft shadow at the edge so it sits on the nail
        ctx.setShadow(offset: .zero, blur: w * 0.12, color: CGColor(gray: 0, alpha: 0.35))
        ctx.addPath(path); ctx.setFillColor(CGColor(gray: 0, alpha: 0.2)); ctx.fillPath()
        ctx.setShadow(offset: .zero, blur: 0, color: nil)
        ctx.addPath(path); ctx.clip()
        // the design, filling the nail
        let iw = CGFloat(design.width), ih = CGFloat(design.height)
        let k = max(w / iw, l / ih)
        ctx.draw(design, in: CGRect(x: -iw * k / 2, y: -ih * k / 2, width: iw * k, height: ih * k))
        // glossy shine: a soft band down one side and a small highlight
        let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [CGColor(gray: 1, alpha: 0.42), CGColor(gray: 1, alpha: 0.0)] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(g, start: CGPoint(x: -w * 0.42, y: 0), end: CGPoint(x: -w * 0.05, y: 0), options: [])
        ctx.setFillColor(CGColor(gray: 1, alpha: 0.5))
        ctx.fillEllipse(in: CGRect(x: w * 0.08, y: l * 0.12, width: w * 0.16, height: l * 0.24))
        // gentle curve darkening at the sides (nails are curved)
        let edge = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [CGColor(gray: 0, alpha: 0.22), CGColor(gray: 0, alpha: 0), CGColor(gray: 0, alpha: 0), CGColor(gray: 0, alpha: 0.22)] as CFArray, locations: [0, 0.2, 0.8, 1])!
        ctx.drawLinearGradient(edge, start: CGPoint(x: -w / 2, y: 0), end: CGPoint(x: w / 2, y: 0), options: [])
        ctx.resetClip()
        ctx.addPath(path); ctx.setStrokeColor(CGColor(gray: 0, alpha: 0.25)); ctx.setLineWidth(max(1, w * 0.03)); ctx.strokePath()
        ctx.restoreGState()
    }

    // MARK: hair

    private func hairPass(_ pb: CVPixelBuffer, _ mirrored: CIImage, _ w: Int, _ h: Int) -> (CIImage, String) {
        guard let color = hair else { return (mirrored, "") }
        let seg = VNGeneratePersonSegmentationRequest(); seg.qualityLevel = .balanced; seg.outputPixelFormat = kCVPixelFormatType_OneComponent8
        let face = VNDetectFaceRectanglesRequest()
        try? VNImageRequestHandler(cvPixelBuffer: pb, orientation: .up).perform([seg, face])
        guard let maskPB = seg.results?.first?.pixelBuffer else { return (mirrored, "Step back a little so I can see you") }
        guard let f = (face.results ?? []).max(by: { $0.boundingBox.width < $1.boundingBox.width })?.boundingBox else { return (mirrored, "Look at the camera so I can find your face") }
        CVPixelBufferLockBaseAddress(maskPB, .readOnly); CVPixelBufferLockBaseAddress(pb, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(maskPB, .readOnly); CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
        let mw = CVPixelBufferGetWidth(maskPB), mh = CVPixelBufferGetHeight(maskPB)
        let mrow = CVPixelBufferGetBytesPerRow(maskPB), frow = CVPixelBufferGetBytesPerRow(pb)
        guard let mbase = CVPixelBufferGetBaseAddress(maskPB)?.assumingMemoryBound(to: UInt8.self),
              let fbase = CVPixelBufferGetBaseAddress(pb)?.assumingMemoryBound(to: UInt8.self) else { return (mirrored, "") }
        let sx = Double(w) / Double(mw), sy = Double(h) / Double(mh)
        // face in mask pixels (top-left origin)
        let fx0 = f.minX * Double(mw), fx1 = f.maxX * Double(mw), fTop = (1 - f.maxY) * Double(mh), fBot = (1 - f.minY) * Double(mh)
        let fw = fx1 - fx0, fh = fBot - fTop, cx = (fx0 + fx1) / 2
        func rgb(_ x: Int, _ y: Int) -> (Double, Double, Double) {
            let px = min(w - 1, Int(Double(x) * sx)), py = min(h - 1, Int(Double(y) * sy))
            let o = py * frow + px * 4
            return (Double(fbase[o + 2]) / 255, Double(fbase[o + 1]) / 255, Double(fbase[o]) / 255)
        }
        // your hair's own colour: just above the forehead, inside you
        var sr = 0.0, sg = 0.0, sb = 0.0, n = 0.0
        let y0 = max(0, Int(fTop - 0.32 * fh)), y1 = max(0, Int(fTop - 0.04 * fh))
        let x0 = max(0, Int(cx - 0.32 * fw)), x1 = min(mw - 1, Int(cx + 0.32 * fw))
        if y1 > y0 { for y in stride(from: y0, to: y1, by: 2) { for x in stride(from: x0, to: x1, by: 2) where mbase[y * mrow + x] > 160 { let c = rgb(x, y); sr += c.0; sg += c.1; sb += c.2; n += 1 } } }
        guard n > 20 else { return (mirrored, "Move back so the top of your head is in view") }
        let ref = (sr / n, sg / n, sb / n)
        // the hair mask
        var out = [UInt8](repeating: 0, count: mw * mh)
        let top = max(0, Int(fTop - 0.95 * fh)), bottom = min(mh, Int(fBot + 1.35 * fh))
        let left = max(0, Int(cx - 1.35 * fw)), right = min(mw, Int(cx + 1.35 * fw))
        let ex = cx, ey = fTop + 0.56 * fh, rx = 0.47 * fw, ry = 0.6 * fh
        let thr = 0.24
        for y in top..<bottom {
            for x in left..<right {
                let m = mbase[y * mrow + x]; guard m > 110 else { continue }
                let nx = (Double(x) - ex) / rx, ny = (Double(y) - ey) / ry
                if nx * nx + ny * ny < 1 { continue }                         // your face stays your face
                let c = rgb(x, y)
                let d = sqrt((c.0 - ref.0) * (c.0 - ref.0) + (c.1 - ref.1) * (c.1 - ref.1) + (c.2 - ref.2) * (c.2 - ref.2))
                let aboveForehead = Double(y) < fTop + 0.05 * fh
                let k = aboveForehead ? max(0, 1 - d / (thr * 1.6)) : max(0, 1 - d / thr)
                out[y * mw + x] = UInt8(min(255, Double(m) * k))
            }
        }
        guard let provider = CGDataProvider(data: Data(out) as CFData),
              let maskCG = CGImage(width: mw, height: mh, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: mw, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0), provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else { return (mirrored, "") }
        var mask = CIImage(cgImage: maskCG).transformed(by: CGAffineTransform(scaleX: sx, y: sy))
        mask = mask.transformed(by: CGAffineTransform(scaleX: -1, y: 1).translatedBy(x: -CGFloat(w), y: 0))
        mask = mask.clampedToExtent().applyingGaussianBlur(sigma: 3.5).cropped(to: CGRect(x: 0, y: 0, width: w, height: h))
        let s = strength
        mask = mask.applyingFilter("CIColorMatrix", parameters: ["inputRVector": CIVector(x: s, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: s, z: 0, w: 0), "inputBVector": CIVector(x: 0, y: 0, z: s, w: 0)])
        // recolour, keeping the hair's own light and shine
        let base = lift != 0 ? mirrored.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: lift]) : mirrored
        let tint = CIImage(color: color).cropped(to: mirrored.extent)
        let coloured = tint.applyingFilter("CIColorBlendMode", parameters: [kCIInputBackgroundImageKey: base])
        let result = coloured.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: mirrored, kCIInputMaskImageKey: mask])
        return (result, "")
    }
}

struct TryOnPage: View {
    var light: Bool
    @ObservedObject private var cam = TryOnCamera.shared
    @State private var mode = TryOnCamera.shared.mode
    @State private var pickedDesign = "red"
    @State private var hairID = "burgundy"
    @State private var strength = 0.75
    @State private var mine: CGImage?
    @State private var dropping = false
    @State private var saved = ""
    private var T: HubTheme { HubTheme(light: light) }
    static let hairColours: [(String, String, String, Double)] = [
        ("black", "Soft black", "#1A1716", -0.2), ("brown", "Dark brown", "#4A2E1F", 0), ("chestnut", "Chestnut", "#7A3E22", 0.1), ("caramel", "Caramel", "#A86B3C", 0.35),
        ("honey", "Honey blonde", "#C9984F", 0.6), ("platinum", "Platinum", "#E6DCC8", 0.9), ("copper", "Copper", "#B8501F", 0.25), ("burgundy", "Burgundy", "#7A1830", 0),
        ("rose", "Rose pink", "#E58BA8", 0.5), ("lilac", "Lilac", "#A88BD6", 0.45), ("blue", "Ocean blue", "#2F5DA8", 0.15), ("silver", "Silver", "#BFC4CC", 0.7),
    ]

    var body: some View {
        HStack(alignment: .top, spacing: 22) {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 20).fill(Color.black)
                if let f = cam.frame { Image(decorative: f.img, scale: 1).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 20)) }
                if !cam.hint.isEmpty {
                    Text(cam.hint).font(HubFont.p(13)).foregroundColor(.white).padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Capsule().fill(Color.black.opacity(0.55))).padding(14)
                }
            }
            .frame(minWidth: 560, maxWidth: .infinity, minHeight: 420)
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(dropping ? HubTheme.blue : Color.clear, lineWidth: 3))
            .onDrop(of: [.fileURL], isTargeted: $dropping) { items in
                guard mode == "nails", let i = items.first else { return false }
                TryOnPage.loadDesign(i); return true
            }

            VStack(alignment: .leading, spacing: 16) {
                Picker("", selection: $mode) { Text("💅 Nails").tag("nails"); Text("💇‍♀️ Hair colour").tag("hair") }.pickerStyle(.segmented)
                    .onChange(of: mode) { _, m in cam.mode = m }
                if mode == "nails" { nailsPanel } else { hairPanel }
                Divider()
                HStack {
                    DashButton(title: "Take photo", icon: "camera.fill", light: light) { save() }
                    if !saved.isEmpty { Text(saved).font(HubFont.p(11.5, .regular)).foregroundColor(T.inactive) }
                }
            }
            .frame(width: 320)
        }
        .onAppear { cam.mode = mode; cam.start() }
        .onDisappear { cam.stop() }
        .onReceive(NotificationCenter.default.publisher(for: .tryOnDesign)) { n in
            if let img = n.object as? NSImage, let cg = TryOnPage.nailCrop(img) { mine = cg; pickedDesign = "mine"; cam.design = cg }
        }
    }

    private var nailsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pick a design — or drop any nail picture onto the camera").font(HubFont.p(12.5, .regular)).foregroundColor(T.inactive)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(64), spacing: 10), count: 4), spacing: 10) {
                if let mine { swatch("mine", "Yours", mine) }
                ForEach(NailDesigns.all) { d in swatch(d.id, d.name, d.img) }
            }
            DashButton(title: "Use my picture", icon: "photo", filled: false, light: light) {
                let p = NSOpenPanel(); p.allowedContentTypes = [.image]
                if p.runModal() == .OK, let u = p.url, let img = NSImage(contentsOf: u), let cg = TryOnPage.nailCrop(img) { mine = cg; pickedDesign = "mine"; cam.design = cg }
            }
            Text("Best results: good light, back of your hand to the camera, fingers a little apart. Works with both hands.").font(HubFont.p(11.5, .regular)).foregroundColor(T.inactive)
        }
    }
    private func swatch(_ id: String, _ name: String, _ img: CGImage) -> some View {
        Button { pickedDesign = id; cam.design = img } label: {
            VStack(spacing: 3) {
                Image(decorative: img, scale: 1).resizable().scaledToFill().frame(width: 40, height: 58)
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: 8, bottomTrailingRadius: 8, topTrailingRadius: 20))
                    .overlay(UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: 8, bottomTrailingRadius: 8, topTrailingRadius: 20).stroke(pickedDesign == id ? HubTheme.blue : Color.clear, lineWidth: 2.5))
                Text(name).font(HubFont.p(9.5, .regular)).lineLimit(1)
            }.frame(width: 64)
        }.buttonStyle(.plain)
    }

    private var hairPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pick a colour. Keep your whole head in view, in good light.").font(HubFont.p(12.5, .regular)).foregroundColor(T.inactive)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(64), spacing: 10), count: 4), spacing: 10) {
                ForEach(Self.hairColours, id: \.0) { h in
                    Button { hairID = h.0; apply(h) } label: {
                        VStack(spacing: 3) {
                            Circle().fill(LinearGradient(colors: [Color(hex: h.2).opacity(0.75), Color(hex: h.2)], startPoint: .top, endPoint: .bottom)).frame(width: 40, height: 40)
                                .overlay(Circle().stroke(hairID == h.0 ? HubTheme.blue : Color.clear, lineWidth: 2.5))
                            Text(h.1).font(HubFont.p(9.5, .regular)).lineLimit(1)
                        }.frame(width: 64)
                    }.buttonStyle(.plain)
                }
            }
            HStack { Text("Strength").font(HubFont.p(12, .regular)); Slider(value: $strength, in: 0.3...1).onChange(of: strength) { _, v in cam.strength = v } }
            Text("Hair colour is a preview: very light colours on dark hair and fly-away strands look less exact than in a salon.").font(HubFont.p(11.5, .regular)).foregroundColor(T.inactive)
        }
    }
    private func apply(_ h: (String, String, String, Double)) {
        let c = NSColor(Color(hex: h.2)).usingColorSpace(.deviceRGB) ?? .brown
        cam.hair = CIColor(red: c.redComponent, green: c.greenComponent, blue: c.blueComponent)
        cam.lift = h.3
    }

    private func save() {
        guard let cg = cam.snapshot() else { return }
        let dir = DocsAgent.folder().appendingPathComponent("Try-On", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(DocsAgent.safeName(mode == "nails" ? "Nails" : "Hair") + ".jpg")
        let rep = NSBitmapImageRep(cgImage: cg)
        if let d = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.9]) { try? d.write(to: url) }
        let img = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        NSPasteboard.general.clearContents(); NSPasteboard.general.writeObjects([img])
        saved = "Saved in Downloads › Zuffi › Try-On and copied"
    }

    /// A nail picture → the design for one nail (the middle of the picture, nail-shaped).
    static func nailCrop(_ img: NSImage) -> CGImage? {
        guard let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let w = CGFloat(cg.width), h = CGFloat(cg.height), aspect: CGFloat = 0.6
        var r = CGRect(x: 0, y: 0, width: w, height: h)
        if w / h > aspect { r.size.width = h * aspect; r.origin.x = (w - r.width) / 2 } else { r.size.height = w / aspect; r.origin.y = (h - r.height) / 2 }
        // zoom in a little: nail photos usually have the nail in the middle
        r = r.insetBy(dx: r.width * 0.18, dy: r.height * 0.18)
        return cg.cropping(to: r.integral)
    }
    nonisolated static func loadDesign(_ item: NSItemProvider) {
        _ = item.loadObject(ofClass: URL.self) { url, _ in
            guard let url, let img = NSImage(contentsOf: url), let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
            let box = TryOnImage(img: cg)
            DispatchQueue.main.async { NotificationCenter.default.post(name: .tryOnDesign, object: NSImage(cgImage: box.img, size: .zero)) }
        }
    }
}

extension Notification.Name { static let tryOnDesign = Notification.Name("zuffiTryOnDesign") }
