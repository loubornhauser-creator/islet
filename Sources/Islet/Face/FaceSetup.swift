import SwiftUI
import AVFoundation

/// Kamera-Vorschau (gespiegelt wie ein Spiegel).
struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        v.wantsLayer = true
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        v.layer = layer
        DispatchQueue.main.async {
            if let c = layer.connection, c.isVideoMirroringSupported {
                c.automaticallyAdjustsVideoMirroring = false
                c.isVideoMirrored = true
            }
        }
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// Einrichtung: Passwort prüfen, Gesicht aus neun Kopfwinkeln einlernen, kurzer Prüf-Scan für die Schwelle.
final class FaceEnroller: ObservableObject {
    enum Step { case intro, password, scan, verify, done }

    @Published var step: Step = .intro
    @Published var passwordError: String?
    @Published var count = 0
    @Published var yawSpread: Float = 0
    @Published var message = "Schau geradeaus"
    @Published var cameraError: String?
    @Published var faceVisible = false
    @Published var verifyProgress = 0.0

    let camera = FaceCamera()
    private let analyzer = FaceAnalyzer()
    private var samples: [FaceSample] = []
    private var lastCapture = Date.distantPast
    private var verifyDistances: [(Float, Float)] = []
    private var password = ""
    private var yawMin: Float = 9, yawMax: Float = -9
    /// So viele abwechslungsreiche Aufnahmen werden gesammelt. Keine starren Winkel, denn Vision liefert Hoch/Runter-Neigung nicht zuverlässig.
    static let target = 24
    static let minimum = 12

    var canFinishScan: Bool { count >= Self.minimum }
    var progress: Double { min(1, Double(count) / Double(Self.target)) }

    func checkPassword(_ pw: String) {
        passwordError = nil
        guard !pw.isEmpty else { passwordError = "Bitte Passwort eingeben."; return }
        if FaceStore.verifyLoginPassword(pw) {
            password = pw
            step = .scan
            startCamera()
        } else {
            passwordError = "Das Passwort stimmt nicht mit deinem Mac-Account überein."
        }
    }

    func startCamera() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            DispatchQueue.main.async {
                guard let self else { return }
                guard granted else { self.cameraError = "Kamera-Zugriff verweigert. Bitte in den Systemeinstellungen erlauben."; return }
                self.camera.maxFPS = 7
                self.camera.onFrame = { [weak self] pb in
                    guard let self else { return }
                    let f = self.analyzer.analyze(pb)
                    DispatchQueue.main.async { self.handle(f) }
                }
                self.camera.start(deviceID: Pref.string("faceCamera")) { ok in
                    if !ok { self.cameraError = "Keine Kamera gefunden." }
                }
            }
        }
    }

    func stopCamera() { camera.stop(); camera.onFrame = nil }

    private func handle(_ f: FaceFrame?) {
        faceVisible = f != nil
        guard let f else { message = "Ich sehe kein Gesicht. Schau in die Kamera."; return }
        switch step {
        case .scan:
            guard f.size > 0.18 else { message = "Etwas näher an die Kamera"; return }
            if samples.count < 40, Date().timeIntervalSince(lastCapture) > 0.3 {
                lastCapture = Date()
                samples.append(FaceSample(feature: f.feature, geometry: f.geometry, yaw: f.yaw, pitch: f.pitch))
                count = samples.count
                yawMin = min(yawMin, f.yaw); yawMax = max(yawMax, f.yaw)
                yawSpread = yawMax - yawMin
            }
            if count >= Self.target && yawSpread >= 0.22 { beginVerify(); return }
            if count < 6 { message = "Schau gerade in die Kamera" }
            else if yawSpread < 0.22 { message = "Dreh den Kopf langsam nach links und rechts" }
            else if count < Self.target { message = "Neige den Kopf leicht, hoch und runter, und bleib im Bild" }
            else { message = "Gleich fertig" }
        case .verify:
            guard let t = currentTemplate() else { return }
            let n = FaceMatcher.nearest(f, in: t)
            verifyDistances.append((n.feature, n.geometry))
            verifyProgress = min(1, Double(verifyDistances.count) / 14)
            if verifyDistances.count >= 14 { save() }
        default: break
        }
    }

    /// Reicht der Anfang, darf man auch früher weiter.
    func beginVerify() {
        guard step == .scan, canFinishScan else { return }
        step = .verify
        verifyDistances = []; verifyProgress = 0
        message = "Schau jetzt ganz normal auf den Bildschirm, bewege dich dabei leicht"
    }

    private func currentTemplate() -> FaceTemplate? {
        let base = FaceMatcher.calibrate(samples)
        return FaceTemplate(samples: samples, baseFeature: base.feature, baseGeometry: base.geometry)
    }

    /// Schwelle = Streuung beim Einlernen oder beim freien Prüf-Scan, je nachdem was größer ist.
    private func save() {
        guard var t = currentTemplate() else { return }
        func p90(_ v: [Float]) -> Float { v.isEmpty ? 0 : v.sorted()[min(v.count - 1, Int(Float(v.count) * 0.9))] }
        t.baseFeature = max(t.baseFeature, p90(verifyDistances.map { $0.0 }))
        t.baseGeometry = max(t.baseGeometry, p90(verifyDistances.map { $0.1 }))
        stopCamera()
        if FaceStore.saveTemplate(t) && FaceStore.savePassword(password) {
            password = ""
            FaceUnlock.shared.reloadCredentials()
            FaceUnlock.shared.addLog("Gesicht eingelernt (\(t.samples.count) Abdrücke)")
            step = .done
        } else {
            cameraError = "Speichern fehlgeschlagen."
        }
    }
}

struct FaceSetupView: View {
    @StateObject private var e = FaceEnroller()
    @State private var pw = ""
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            switch e.step {
            case .intro: intro
            case .password: passwordStep
            case .scan, .verify: scanStep
            case .done: done
            }
        }
        .padding(26)
        .frame(width: 520)
        .onDisappear { e.stopCamera() }
    }

    private var intro: some View {
        VStack(spacing: 14) {
            Image(systemName: "faceid").font(.system(size: 52, weight: .light)).foregroundStyle(.green)
            Text("Face Unlock einrichten").font(.title2.bold())
            Text("In etwa einer Minute: Du gibst einmal dein Mac-Passwort ein, Islet prüft es und speichert es verschlüsselt auf diesem Mac. Danach lernt die Kamera dein Gesicht aus mehreren Kopfwinkeln.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text("Eine Mac-Kamera hat keine Tiefensensorik. Ein Foto oder Video von dir könnte sie täuschen. Nutze Face Unlock nur an einem Ort, dem du vertraust.")
                    .font(.callout)
            }
            .padding(12).background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            HStack { Button("Abbrechen", action: onClose); Button("Weiter") { e.step = .password }.keyboardShortcut(.defaultAction) }
        }
    }

    private var passwordStep: some View {
        VStack(spacing: 14) {
            Image(systemName: "key.fill").font(.system(size: 36, weight: .light)).foregroundStyle(.secondary)
            Text("Dein Mac-Passwort").font(.title3.bold())
            Text("Es wird sofort gegen deinen Account geprüft und danach verschlüsselt gespeichert, gebunden an diesen Mac und deinen Benutzer. Es gibt keine Schlüsselbund-Abfragen.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            SecureField("Passwort", text: $pw).textFieldStyle(.roundedBorder).frame(width: 280).onSubmit { e.checkPassword(pw) }
            if let err = e.passwordError { Text(err).foregroundStyle(.red).font(.callout) }
            HStack { Button("Abbrechen", action: onClose); Button("Prüfen und weiter") { e.checkPassword(pw); if e.step != .password { pw = "" } }.keyboardShortcut(.defaultAction) }
        }
    }

    private var scanStep: some View {
        VStack(spacing: 14) {
            Text(e.step == .scan ? "Gesicht einlernen" : "Kurzer Prüf-Scan").font(.title3.bold())
            ZStack {
                CameraPreview(session: e.camera.session)
                    .frame(width: 300, height: 225).clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(e.faceVisible ? Color.green : Color.white.opacity(0.3), lineWidth: 3).frame(width: 300, height: 225)
            }
            if e.step == .scan {
                ProgressView(value: e.progress).frame(width: 260)
                Text("\(e.count) von \(FaceEnroller.target) Aufnahmen").font(.caption).foregroundStyle(.secondary)
            } else {
                ProgressView(value: e.verifyProgress).frame(width: 260)
            }
            Text(e.message).multilineTextAlignment(.center).foregroundStyle(.secondary).frame(height: 36)
            if let c = e.cameraError { Text(c).foregroundStyle(.red).font(.callout) }
            HStack {
                Button("Abbrechen") { e.stopCamera(); onClose() }
                if e.step == .scan { Button("Fertig") { e.beginVerify() }.disabled(!e.canFinishScan) }
            }
        }
    }

    private var done: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 52)).foregroundStyle(.green)
            Text("Gesicht eingelernt").font(.title2.bold())
            Text("Zuerst läuft ein Probelauf: Islet erkennt dich am Sperrbildschirm und zeigt die Animation, tippt aber noch nichts. Wenn alles passt, schaltest du das Passwort-Tippen in den Einstellungen ein.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button("Fertig", action: onClose).keyboardShortcut(.defaultAction)
        }
    }
}
