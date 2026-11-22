import AppKit
import AVFoundation
import CoreGraphics

/// Face Unlock: Beim Aufwachen am Sperrbildschirm startet ein kurzer Kamera-Scan. Passt das Gesicht, tippt Islet das
/// gespeicherte Passwort. Das ist eine Komfort-Funktion und kein Ersatz für Face ID (die Mac-Kamera hat keine Tiefen-
/// sensorik). Sicherheitsgurte: nur bei wirklich gesperrtem Bildschirm, nie in andere Apps, höchstens zwei Versuche.
final class FaceUnlock: ObservableObject {
    static let shared = FaceUnlock()

    enum Phase: Equatable { case idle, scanning, recognized, typing, rejected, failed(String) }

    @Published var phase: Phase = .idle
    /// Live-Wert 0...1, wie gut das Gesicht gerade passt.
    @Published var score: Float = 0
    @Published var enrolled = FaceStore.hasTemplate && FaceStore.hasPassword
    @Published var locked = false
    @Published var log: [String] = []

    private let camera = FaceCamera()
    private let analyzer = FaceAnalyzer()
    private var template: FaceTemplate?
    private var password: String?
    private var started = false
    private var testMode = false
    private var recent: [Bool] = []
    private var deadline: Timer?
    private var cooldownUntil = Date.distantPast
    private var typedAttempts = 0
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var activityMonitor: Any?
    private var lastActivityScan = Date.distantPast
    private let needed = 4

    // MARK: Start/Stop

    func start() {
        guard !started else { return }
        started = true
        reloadCredentials()

        let dnc = DistributedNotificationCenter.default()
        func add(_ center: NotificationCenter, _ name: Notification.Name, _ block: @escaping () -> Void) {
            observers.append((center, center.addObserver(forName: name, object: nil, queue: .main) { _ in block() }))
        }
        add(dnc, .init("com.apple.screenIsLocked")) { [weak self] in
            self?.locked = true; self?.typedAttempts = 0
            self?.installActivityMonitor()
            if Pref.bool("faceOnLock") { self?.scanSoon("Bildschirm gesperrt", delay: 1.0) }
        }
        add(dnc, .init("com.apple.screenIsUnlocked")) { [weak self] in
            self?.locked = false; self?.typedAttempts = 0
            self?.removeActivityMonitor()
            if self?.phase == .scanning || self?.phase == .typing { self?.endScan(.idle) }
        }
        add(dnc, .init("com.apple.screensaver.didstop")) { [weak self] in
            if Pref.bool("faceOnScreensaver") { self?.scanSoon("Bildschirmschoner beendet", delay: 0.4) }
        }
        let ws = NSWorkspace.shared.notificationCenter
        add(ws, NSWorkspace.screensDidWakeNotification) { [weak self] in
            if Pref.bool("faceOnWake") { self?.scanSoon("Bildschirm aufgewacht", delay: 0.5) }
        }
        add(ws, NSWorkspace.didWakeNotification) { [weak self] in
            if Pref.bool("faceOnWake") { self?.scanSoon("Mac aufgewacht", delay: 1.0) }
        }
        locked = Self.screenIsLocked()
        if locked { installActivityMonitor() }
    }

    func stop() {
        guard started else { return }
        started = false
        observers.forEach { $0.0.removeObserver($0.1) }
        observers.removeAll()
        removeActivityMonitor()
        endScan(.idle)
        template = nil; password = nil
    }

    /// Lädt Vorlage und Passwort in den Speicher (einmal beim Start, nicht erst am Sperrbildschirm,
    /// damit eine mögliche Schlüsselbund-Abfrage beantwortet werden kann, solange du davor sitzt).
    func reloadCredentials() {
        DispatchQueue.global(qos: .userInitiated).async {
            let t = FaceStore.loadTemplate(), p = FaceStore.loadPassword()
            DispatchQueue.main.async { [weak self] in
                self?.template = t; self?.password = p
                self?.enrolled = t != nil && p != nil
            }
        }
    }

    func forgetEverything() {
        FaceStore.deleteAll()
        template = nil; password = nil; enrolled = false
        addLog("Gesicht und Passwort gelöscht")
    }

    // MARK: Zustand des Bildschirms

    static func screenIsLocked() -> Bool {
        guard let d = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return (d["CGSSessionScreenIsLocked"] as? NSNumber)?.boolValue ?? (d["CGSSessionScreenIsLocked"] as? Bool) ?? false
    }

    /// Das Passwort darf nur getippt werden, wenn der Sperrbildschirm wirklich vorne liegt, nie in eine normale App.
    private static func lockScreenIsFront() -> Bool {
        guard screenIsLocked() else { return false }
        let id = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        return id == nil || id == "com.apple.loginwindow" || id == "com.apple.ScreenSaver.Engine"
    }

    // MARK: Auslöser

    private func installActivityMonitor() {
        guard activityMonitor == nil, Pref.bool("faceOnActivity") else { return }
        activityMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .keyDown, .scrollWheel, .leftMouseDown]) { [weak self] _ in
            guard let self, Date().timeIntervalSince(self.lastActivityScan) > 3 else { return }
            self.lastActivityScan = Date()
            self.scanSoon("Maus oder Tastatur bewegt", delay: 0.1)
        }
    }

    private func removeActivityMonitor() {
        if let m = activityMonitor { NSEvent.removeMonitor(m); activityMonitor = nil }
    }

    /// Wartet kurz, bis macOS den Sperrbildschirm wirklich zeigt, und startet dann den Scan.
    private func scanSoon(_ reason: String, delay: TimeInterval) {
        guard started, Pref.bool("modFace") else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.beginScan(reason: reason, attemptsLeft: 4)
        }
    }

    // MARK: Scan

    /// Für „Testen“ in den Einstellungen: läuft auch bei entsperrtem Bildschirm und tippt nie.
    func testScan() {
        testMode = true
        beginScan(reason: "Test", attemptsLeft: 0)
    }

    private func beginScan(reason: String, attemptsLeft: Int) {
        guard started || testMode, phase == .idle || phase == .rejected || isFailed else { return }
        guard Date() > cooldownUntil else { return }
        if !testMode && !Self.screenIsLocked() {
            if attemptsLeft > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.beginScan(reason: reason, attemptsLeft: attemptsLeft - 1) }
            }
            return
        }
        guard let template else { fail("Noch kein Gesicht eingelernt"); return }
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else { fail("Kamera-Zugriff fehlt"); return }

        addLog("Scan gestartet (\(reason))")
        phase = .scanning; score = 0; recent = []
        FaceScanIsland.shared.show(.searching, locked: Self.screenIsLocked())
        let strictness = FaceMatcher.Strictness(rawValue: Pref.string("faceStrictness")) ?? .normal
        camera.onFrame = { [weak self] pb in
            guard let self else { return }
            var ok = false, s: Float = 0
            if let f = self.analyzer.analyze(pb) { (ok, s) = FaceMatcher.matches(f, template: template, strictness: strictness) }
            DispatchQueue.main.async { self.consume(ok: ok, score: s) }
        }
        camera.start(deviceID: Pref.string("faceCamera")) { [weak self] ok in
            if !ok { self?.fail("Kamera nicht verfügbar") }
        }
        deadline?.invalidate()
        deadline = Timer.scheduledTimer(withTimeInterval: max(3, Pref.double("faceScanSeconds")), repeats: false) { [weak self] _ in
            guard self?.phase == .scanning else { return }
            self?.endScan(.rejected)
            self?.addLog("Gesicht nicht erkannt (Zeit abgelaufen)")
        }
    }

    private var isFailed: Bool { if case .failed = phase { return true }; return false }

    private func consume(ok: Bool, score s: Float) {
        guard phase == .scanning else { return }
        score = s
        recent.append(ok)
        if recent.count > 8 { recent.removeFirst() }
        if recent.filter({ $0 }).count >= needed { recognized() }
    }

    private func recognized() {
        camera.stop()
        deadline?.invalidate()
        phase = .recognized
        addLog("Gesicht erkannt")
        let willType = Pref.bool("faceTypePassword") && !testMode
        FaceScanIsland.shared.show(willType ? .recognized : .recognizedDry, locked: Self.screenIsLocked())
        if willType {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in self?.typePassword() }
        } else {
            addLog(testMode ? "Test: nichts getippt" : "Probelauf: Passwort nicht getippt")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in self?.endScan(.idle) }
        }
    }

    private func fail(_ message: String) {
        addLog("Fehler: \(message)")
        camera.stop(); deadline?.invalidate()
        phase = .failed(message)
        FaceScanIsland.shared.show(.error(message), locked: Self.screenIsLocked())
        cooldownUntil = Date().addingTimeInterval(3)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self] in self?.endScan(.idle) }
    }

    func endScan(_ final: Phase) {
        camera.stop(); deadline?.invalidate(); deadline = nil
        camera.onFrame = nil
        testMode = false
        if final == .rejected {
            phase = .rejected
            cooldownUntil = Date().addingTimeInterval(3)
            FaceScanIsland.shared.show(.denied, locked: Self.screenIsLocked())
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
                if self?.phase == .rejected { self?.phase = .idle }
            }
        } else {
            phase = .idle
            FaceScanIsland.shared.hide()
        }
    }

    // MARK: Passwort tippen

    private func typePassword() {
        guard let pw = password, !pw.isEmpty else { fail("Kein Passwort gespeichert"); return }
        guard InputTap.trusted else { fail("Bedienungshilfen fehlen"); return }
        guard typedAttempts < 2 else { fail("Zwei Versuche gescheitert: bitte einmal von Hand entsperren"); return }
        guard Self.lockScreenIsFront() else { fail("Sperrbildschirm nicht erkannt, nichts getippt"); return }
        typedAttempts += 1
        phase = .typing
        FaceScanIsland.shared.show(.unlocking, locked: true)
        addLog("Passwort wird getippt (Versuch \(typedAttempts))")

        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            Self.postKey(0x38)                       // Shift: Display sicher wach und Feld bereit
            usleep(350_000)
            guard Self.lockScreenIsFront() else {    // zweite Prüfung direkt vor dem Tippen
                DispatchQueue.main.async { self?.fail("Sperrbildschirm weg, abgebrochen") }
                return
            }
            for _ in 0..<48 { Self.postKey(0x33) }   // Feld leeren
            for ch in pw { Self.postCharacter(ch); usleep(7_000) }
            usleep(150_000)
            Self.postKey(0x24)                       // Return
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
                guard let self else { return }
                if Self.screenIsLocked() {
                    self.fail("Passwort wurde nicht angenommen")
                } else {
                    self.addLog("Entsperrt")
                    self.endScan(.idle)
                }
            }
        }
    }

    private static func postKey(_ code: CGKeyCode) {
        let src = CGEventSource(stateID: .hidSystemState)
        CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: true)?.post(tap: .cghidEventTap)
        CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: false)?.post(tap: .cghidEventTap)
        usleep(4_000)
    }

    /// Tippt ein Zeichen über seinen Unicode-Wert, unabhängig vom Tastaturlayout.
    private static func postCharacter(_ ch: Character) {
        let src = CGEventSource(stateID: .hidSystemState)
        var u = Array(String(ch).utf16)
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: down)
            e?.flags = []
            e?.keyboardSetUnicodeString(stringLength: u.count, unicodeString: &u)
            e?.post(tap: .cghidEventTap)
        }
    }

    // MARK: Protokoll

    func addLog(_ line: String) {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"
        log.insert("\(f.string(from: Date()))  \(line)", at: 0)
        if log.count > 40 { log.removeLast(log.count - 40) }
    }
}
