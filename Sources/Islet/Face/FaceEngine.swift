import AVFoundation
import Vision
import CoreImage

/// Ergebnis der Analyse eines Kamerabilds.
struct FaceFrame {
    var feature: VNFeaturePrintObservation
    var geometry: [Float]
    var yaw: Float
    var pitch: Float
    var roll: Float
    /// Gesichtshöhe relativ zur Bildhöhe (0...1).
    var size: Float
}

/// Kamera: läuft nur, solange ein Scan oder die Einrichtung aktiv ist (die grüne LED zeigt es).
/// Die Sitzung bleibt dauerhaft vorbereitet (Eingang und Ausgang hängen schon dran), beim Scan wird nur noch
/// `startRunning()` aufgerufen. Das spart beim Aufwachen die Konfigurationszeit.
final class FaceCamera: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    var onFrame: ((CVPixelBuffer) -> Void)?
    /// Wird einmal pro Start aufgerufen, sobald das erste Bild wirklich da ist (die Kamera läuft tatsächlich).
    var onFirstFrame: (() -> Void)?
    /// Diagnose: Unterbrechungen und Laufzeitfehler der Kamera.
    var onEvent: ((String) -> Void)?
    private let queue = DispatchQueue(label: "islet.face.camera", qos: .userInitiated)
    private var configured = false
    private var input: AVCaptureDeviceInput?
    private var firstFrameSent = false
    private var lastFrame = Date.distantPast
    private(set) var running = false

    /// Höchstens so viele Bilder pro Sekunde auswerten. Standard ohne Begrenzung: Die Auswertung bremst von selbst,
    /// späte Bilder werden verworfen.
    var maxFPS: Double = 60

    override init() {
        super.init()
        let nc = NotificationCenter.default
        nc.addObserver(forName: AVCaptureSession.wasInterruptedNotification, object: session, queue: nil) { [weak self] _ in
            self?.onEvent?("Kamera unterbrochen")
        }
        nc.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: nil) { [weak self] n in
            let e = (n.userInfo?[AVCaptureSessionErrorKey] as? NSError)?.localizedDescription ?? "?"
            self?.onEvent?("Kamera-Fehler: \(e)")
        }
    }

    static func devices() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
                                         mediaType: .video, position: .unspecified).devices
    }

    /// Wählt bei jedem Scan neu: bevorzugte Kamera, sonst die eingebaute, sonst eine externe (Clamshell, Desktop-Mac).
    static func pickDevice(preferredID: String) -> AVCaptureDevice? {
        let all = devices()
        if preferredID != "auto", let d = all.first(where: { $0.uniqueID == preferredID }) { return d }
        return all.first { $0.deviceType == .builtInWideAngleCamera } ?? all.first
    }

    private func configureIfNeeded() {
        guard !configured else { return }
        configured = true
        session.beginConfiguration()
        session.sessionPreset = .vga640x480
        let out = AVCaptureVideoDataOutput()
        out.alwaysDiscardsLateVideoFrames = true
        out.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        out.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(out) { session.addOutput(out) }
        session.commitConfiguration()
    }

    func start(deviceID: String, completion: @escaping (Bool) -> Void) {
        queue.async { [self] in
            configureIfNeeded()
            guard let device = Self.pickDevice(preferredID: deviceID) else { DispatchQueue.main.async { completion(false) }; return }
            if input?.device.uniqueID != device.uniqueID {
                session.beginConfiguration()
                if let input { session.removeInput(input) }
                if let new = try? AVCaptureDeviceInput(device: device), session.canAddInput(new) { session.addInput(new); input = new } else { input = nil }
                session.commitConfiguration()
            }
            guard input != nil else { DispatchQueue.main.async { completion(false) }; return }
            firstFrameSent = false
            lastFrame = .distantPast
            if !session.isRunning { session.startRunning() }
            running = session.isRunning
            DispatchQueue.main.async { completion(self.running) }
        }
    }

    func stop() {
        queue.async { [self] in
            if session.isRunning { session.stopRunning() }
            running = false
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        if !firstFrameSent {
            firstFrameSent = true
            DispatchQueue.main.async { [weak self] in self?.onFirstFrame?() }
        }
        let now = Date()
        guard now.timeIntervalSince(lastFrame) >= 1 / maxFPS else { return }
        lastFrame = now
        onFrame?(pb)
    }
}

/// Gesichtserkennung nur mit Apples Vision-Framework, ohne eigenes Modell und ohne Download.
/// Zwei Merkmale zusammen: Bild-Fingerabdruck des ausgerichteten Gesichts und Proportionen aus den Gesichtspunkten.
final class FaceAnalyzer {
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    /// Lädt die Vision-Modelle vor, damit der erste echte Scan nicht die Ladezeit trägt.
    func prewarm() {
        var pb: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, 320, 240, kCVPixelFormatType_32BGRA, nil, &pb)
        if let pb { _ = try? VNImageRequestHandler(cvPixelBuffer: pb).perform([VNDetectFaceLandmarksRequest()]) }
        let ctx = CGContext(data: nil, width: 160, height: 160, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        if let cg = ctx?.makeImage() {
            let fp = VNGenerateImageFeaturePrintRequest()
            _ = try? VNImageRequestHandler(cgImage: cg).perform([fp])
        }
    }

    func analyze(_ pixelBuffer: CVPixelBuffer) -> FaceFrame? {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up)
        let landmarksRequest = VNDetectFaceLandmarksRequest()
        guard (try? handler.perform([landmarksRequest])) != nil,
              let face = (landmarksRequest.results ?? []).max(by: { $0.boundingBox.height < $1.boundingBox.height }),
              let landmarks = face.landmarks else { return nil }

        let w = CGFloat(CVPixelBufferGetWidth(pixelBuffer)), h = CGFloat(CVPixelBufferGetHeight(pixelBuffer))
        let imageSize = CGSize(width: w, height: h)
        guard let geometry = Self.geometry(landmarks, imageSize: imageSize) else { return nil }

        // Gesicht ausrichten (Neigung ausgleichen), zuschneiden, Graustufen, Fingerabdruck.
        let roll = CGFloat(face.roll?.floatValue ?? 0)
        let box = VNImageRectForNormalizedRect(face.boundingBox, Int(w), Int(h))
        let center = CGPoint(x: box.midX, y: box.midY)
        var image = CIImage(cvPixelBuffer: pixelBuffer)
        image = image.transformed(by: CGAffineTransform(translationX: -center.x, y: -center.y)
            .rotated(by: -roll)
            .translatedBy(x: center.x, y: center.y))
        let side = max(box.width, box.height) * 1.35
        let crop = CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side)
        image = image.cropped(to: crop)
            .transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY))
            .transformed(by: CGAffineTransform(scaleX: 160 / side, y: 160 / side))
            .applyingFilter("CIPhotoEffectMono")
            .applyingFilter("CIColorControls", parameters: [kCIInputContrastKey: 1.25])
        guard let cg = ciContext.createCGImage(image, from: CGRect(x: 0, y: 0, width: 160, height: 160)) else { return nil }

        let fp = VNGenerateImageFeaturePrintRequest()
        fp.imageCropAndScaleOption = .scaleFill
        guard (try? VNImageRequestHandler(cgImage: cg).perform([fp])) != nil, let feature = fp.results?.first else { return nil }

        return FaceFrame(feature: feature, geometry: geometry,
                         yaw: face.yaw?.floatValue ?? 0, pitch: face.pitch?.floatValue ?? 0, roll: Float(roll),
                         size: Float(face.boundingBox.height))
    }

    /// Verhältnisse zwischen Gesichtspunkten, geteilt durch den Augenabstand (unabhängig von der Entfernung).
    private static func geometry(_ l: VNFaceLandmarks2D, imageSize: CGSize) -> [Float]? {
        func pts(_ r: VNFaceLandmarkRegion2D?) -> [CGPoint] { r?.pointsInImage(imageSize: imageSize) ?? [] }
        func center(_ p: [CGPoint]) -> CGPoint? {
            guard !p.isEmpty else { return nil }
            return CGPoint(x: p.map(\.x).reduce(0, +) / CGFloat(p.count), y: p.map(\.y).reduce(0, +) / CGFloat(p.count))
        }
        func dist(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }
        func width(_ p: [CGPoint]) -> CGFloat { (p.map(\.x).max() ?? 0) - (p.map(\.x).min() ?? 0) }
        func height(_ p: [CGPoint]) -> CGFloat { (p.map(\.y).max() ?? 0) - (p.map(\.y).min() ?? 0) }

        let le = pts(l.leftEye), re = pts(l.rightEye), nose = pts(l.nose), lips = pts(l.outerLips)
        let contour = pts(l.faceContour), lb = pts(l.leftEyebrow), rb = pts(l.rightEyebrow), median = pts(l.medianLine)
        guard let lc = center(le), let rc = center(re) else { return nil }
        let eye = dist(lc, rc)
        guard eye > 4 else { return nil }
        let eyeMid = CGPoint(x: (lc.x + rc.x) / 2, y: (lc.y + rc.y) / 2)
        let nc = center(nose), mc = center(lips), lbc = center(lb), rbc = center(rb)
        // Beim Neigen des Kopfes fehlen manchmal einzelne Regionen: Ersatzpunkte nehmen, sonst "unbekannt" (NaN).
        let chin: CGPoint? = median.last ?? contour.min(by: { $0.y < $1.y })
        let top: CGPoint? = median.first
        let browMid: CGPoint? = (lbc != nil && rbc != nil) ? CGPoint(x: (lbc!.x + rbc!.x) / 2, y: (lbc!.y + rbc!.y) / 2) : nil

        func ratio(_ v: CGFloat?) -> Float { v.map { Float($0 / eye) } ?? .nan }
        let vals: [Float] = [
            contour.count > 2 ? ratio(width(contour)) : .nan,
            ratio(nc.map { dist(eyeMid, $0) }),
            (nc != nil && mc != nil) ? ratio(dist(nc!, mc!)) : .nan,
            lips.count > 2 ? ratio(width(lips)) : .nan,
            (mc != nil && chin != nil) ? ratio(dist(mc!, chin!)) : .nan,
            ratio(browMid.map { dist($0, eyeMid) }),
            le.count > 2 ? ratio(width(le)) : .nan,
            re.count > 2 ? ratio(width(re)) : .nan,
            (top != nil && chin != nil) ? ratio(dist(top!, chin!)) : .nan,
            nose.count > 2 ? ratio(width(nose)) : .nan,
            lips.count > 2 ? ratio(height(lips)) : .nan,
            (lbc != nil && rbc != nil) ? ratio(dist(lbc!, rbc!)) : .nan,
        ]
        return vals.filter { !$0.isNaN }.count >= 6 ? vals : nil
    }
}

/// Abgleich eines Kamerabilds mit der eingelernten Vorlage.
enum FaceMatcher {
    enum Strictness: String, CaseIterable {
        case loose, normal, strict
        /// Faktor auf die beim Einlernen gemessene Streuung. Kleiner = strenger.
        var factor: Float { self == .loose ? 1.75 : (self == .normal ? 1.4 : 1.15) }
        var label: String { self == .loose ? "Locker" : (self == .normal ? "Normal" : "Streng") }
    }

    static func featureDistance(_ a: VNFeaturePrintObservation, _ b: VNFeaturePrintObservation) -> Float {
        var d: Float = 0
        _ = try? a.computeDistance(&d, to: b)
        return d
    }

    /// Abstand der Proportionen. Unbekannte Werte (NaN) werden übersprungen, mindestens 4 gemeinsame müssen da sein.
    static func geometryDistance(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return .infinity }
        var s: Float = 0, n: Float = 0
        for i in 0..<a.count where !a[i].isNaN && !b[i].isNaN { let d = a[i] - b[i]; s += d * d; n += 1 }
        return n >= 4 ? (s / n).squareRoot() : .infinity
    }

    /// Nächster eingelernter Abdruck bei ähnlicher Kopfhaltung.
    static func nearest(_ f: FaceFrame, in t: FaceTemplate) -> (feature: Float, geometry: Float) {
        let near = t.samples.filter { abs($0.yaw - f.yaw) < 0.35 && abs($0.pitch - f.pitch) < 0.30 }
        let pool = near.isEmpty ? t.samples : near
        var best = (feature: Float.infinity, geometry: Float.infinity)
        for s in pool {
            let df = featureDistance(f.feature, s.feature), dg = geometryDistance(f.geometry, s.geometry)
            if df + dg * 4 < best.feature + best.geometry * 4 { best = (df, dg) }
        }
        return best
    }

    static func matches(_ f: FaceFrame, template t: FaceTemplate, strictness: Strictness) -> (ok: Bool, score: Float) {
        guard f.size > 0.18, abs(f.yaw) < 0.75 else { return (false, 0) }
        let n = nearest(f, in: t)
        let tf = t.baseFeature * strictness.factor, tg = t.baseGeometry * strictness.factor
        let ok = n.feature <= tf && n.geometry <= tg
        // Anzeige: 100 % = identisch, 0 % = an der Schwelle oder darüber.
        let s = 1 - max(n.feature / max(tf, 0.0001), n.geometry / max(tg, 0.0001)) * 0.5
        return (ok, max(0, min(1, s)))
    }

    /// Schwellen aus den eigenen Abdrücken ableiten: Abstand jedes Abdrucks zu seinem nächsten Nachbarn bei ähnlicher Haltung.
    static func calibrate(_ samples: [FaceSample]) -> (feature: Float, geometry: Float) {
        var fs: [Float] = [], gs: [Float] = []
        for (i, a) in samples.enumerated() {
            var bf = Float.infinity, bg = Float.infinity
            for (j, b) in samples.enumerated() where i != j && abs(a.yaw - b.yaw) < 0.35 && abs(a.pitch - b.pitch) < 0.30 {
                bf = min(bf, featureDistance(a.feature, b.feature)); bg = min(bg, geometryDistance(a.geometry, b.geometry))
            }
            if bf.isFinite { fs.append(bf); gs.append(bg) }
        }
        func p90(_ v: [Float]) -> Float { v.isEmpty ? 1 : v.sorted()[min(v.count - 1, Int(Float(v.count) * 0.9))] }
        // Mindestens ein kleiner Wert, damit sehr ähnliche Abdrücke keine unmögliche Schwelle erzeugen.
        return (max(p90(fs), 0.05), max(p90(gs), 0.02))
    }
}
