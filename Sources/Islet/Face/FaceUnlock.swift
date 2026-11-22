import AppKit
import AVFoundation
import CoreGraphics

/// Protokoll für Face Unlock in einer Datei (nur Ereignisse und Zeiten, keine Bilder, keine Passwörter).
/// So lässt sich nachvollziehen, wo am Sperrbildschirm Zeit verloren geht oder etwas scheitert.
enum FaceLog {
    static let url: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Islet", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("face-unlock.log")
    }()
    private static let queue = DispatchQueue(label: "islet.facelog", qos: .utility)

    static func write(_ line: String) {
        queue.async {
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
            let text = "\(f.string(from: Date()))  \(line)\n"
            if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path), (attrs[.size] as? Int ?? 0) > 300_000 {
                try? FileManager.default.removeItem(at: url)
            }
            if let h = try? FileHandle(forWritingTo: url) {
                h.seekToEndOfFile(); h.write(Data(text.utf8)); try? h.close()
            } else {
                try? text.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }
}

/// Tippt das Passwort wie bei bekannten Open-Source-Entsperrern: Feld leeren (⌘→, ⌘⌫), Text in kleinen Unicode-Blöcken
/// (unabhängig vom Tastaturlayout), dann Return. Alles auf der HID-Ebene, nur so erreichen die Tasten das Passwortfeld.
enum FaceTyping {
    static func typeAndReturn(_ password: String) {
        let src = CGEventSource(stateID: .hidSystemState)
        key(0x7C, flags: .maskCommand, src)       // ⌘→ ans Ende
        key(0x33, flags: .maskCommand, src)       // ⌘⌫ alles davor löschen
        let units = Array(password.utf16)
        var start = 0
        while start < units.count {
            var end = min(start + 20, units.count)
            if end < units.count, (0xD800...0xDBFF).contains(units[end - 1]) { end -= 1 }   // Ersatzpaare nicht trennen
            var chunk = Array(units[start..<end])
            for down in [true, false] {
                let e = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: down)
                e?.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: &chunk)
                e?.post(tap: .cghidEventTap)
                Thread.sleep(forTimeInterval: 0.004)
            }
            start = end
        }
        key(0x24, flags: [], src)                 // Return
    }

    private static func key(_ code: CGKeyCode, flags: CGEventFlags, _ src: CGEventSource?) {
        let cmd = flags.contains(.maskCommand)
        if cmd {
            let c = CGEvent(keyboardEventSource: src, virtualKey: 0x37, keyDown: true); c?.flags = .maskCommand
            c?.post(tap: .cghidEventTap); Thread.sleep(forTimeInterval: 0.012)
        }
        let d = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: true), u = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: false)
        d?.flags = flags; u?.flags = flags
        d?.post(tap: .cghidEventTap); Thread.sleep(forTimeInterval: 0.012)
        u?.post(tap: .cghidEventTap); Thread.sleep(forTimeInterval: 0.012)
        if cmd {
            let c = CGEvent(keyboardEventSource: src, virtualKey: 0x37, keyDown: false); c?.flags = []
            c?.post(tap: .cghidEventTap); Thread.sleep(forTimeInterval: 0.012)
        }
    }

    static func tap(_ code: CGKeyCode) {
        let src = CGEventSource(stateID: .hidSystemState)
        CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: true)?.post(tap: .cghidEventTap)
        CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: false)?.post(tap: .cghidEventTap)
    }
}

/// Face Unlock: Beim Aufwachen am Sperrbildschirm startet ein kurzer Kamera-Scan. Passt das Gesicht, tippt Islet das
/// gespeicherte Passwort. Das ist eine Komfort-Funktion und kein Ersatz für Face ID (die Mac-Kamera hat keine Tiefen-
/// sensorik). Sicherheitsgurte: nur bei wirklich gesperrtem Bildschirm, höchstens zwei Versuche.
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
    private var credentialsLoaded = false
    private var started = false
    private var testMode = false
    private var recent: [Bool] = []
    private var deadline: Timer?
    private var cooldownUntil = Date.distantPast
    private var typedAttempts = 0
    private var sleeping = false
    private var autoRetried = false
    private var generation = 0
    private var scanStart = Date()
    private var gotFrame = false
    private var wrongSince: Date?
    private var activity: NSObjectProtocol?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var activityMonitor: Any?
    private var lastActivityScan = Date.distantPast
    /// Zwei Bilder gleichzeitig auswerten (Vision läuft zum Teil auf der Neural Engine), das verdoppelt den Durchsatz.
    private let slots = DispatchSemaphore(value: 2)
    private let analysisQueue = DispatchQueue(label: "islet.face.analysis", qos: .userInteractive, attributes: .concurrent)
    private var analysisTimes: [Double] = []

    private var needed: Int {
        switch FaceMatcher.Strictness(rawValue: Pref.string("faceStrictness")) ?? .normal { case .loose: return 1; case .normal: return 2; case .strict: return 3 }
    }

    // MARK: Start/Stop

    func start() {
        guard !started else { return }
        started = true
        // Ohne das drosselt macOS die App im Leerlauf (App Nap) und der Scan beim Aufwachen kommt zu spät.
        activity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep, reason: "Face Unlock wartet auf das Aufwachen")
        DispatchQueue.global(qos: .utility).async { [analyzer] in analyzer.prewarm() }
        reloadCredentials()

        let dnc = DistributedNotificationCenter.default()
        func add(_ center: NotificationCenter, _ name: Notification.Name, _ block: @escaping () -> Void) {
            observers.append((center, center.addObserver(forName: name, object: nil, queue: .main) { _ in block() }))
        }
        add(dnc, .init("com.apple.screenIsLocked")) { [weak self] in
            guard let self else { return }
            self.locked = true; self.typedAttempts = 0
            self.installActivityMonitor()
            self.addLog("Bildschirm gesperrt")
            if Pref.bool("faceOnLock") && !self.sleeping { self.scanSoon("Bildschirm gesperrt", delay: 0.1) }
        }
        add(dnc, .init("com.apple.screenIsUnlocked")) { [weak self] in
            guard let self else { return }
            self.locked = false; self.typedAttempts = 0; self.autoRetried = false
            self.removeActivityMonitor()
            self.addLog("Bildschirm entsperrt")
            if self.phase != .idle { self.endScan(.idle) }
        }
        add(dnc, .init("com.apple.screensaver.didstop")) { [weak self] in
            if Pref.bool("faceOnScreensaver") { self?.wake("Bildschirmschoner beendet") }
        }
        let ws = NSWorkspace.shared.notificationCenter
        add(ws, NSWorkspace.willSleepNotification) { [weak self] in
            self?.sleeping = true
            self?.addLog("Mac schläft ein")
            if self?.phase != .idle { self?.endScan(.idle) }
        }
        add(ws, NSWorkspace.screensDidWakeNotification) { [weak self] in
            if Pref.bool("faceOnWake") { self?.wake("Bildschirm aufgewacht") } else { self?.sleeping = false }
        }
        add(ws, NSWorkspace.didWakeNotification) { [weak self] in
            if Pref.bool("faceOnWake") { self?.wake("Mac aufgewacht") } else { self?.sleeping = false }
        }
        locked = Self.screenIsLocked()
        if locked { installActivityMonitor() }
        addLog("Face Unlock bereit")
    }

    func stop() {
        guard started else { return }
        started = false
        observers.forEach { $0.0.removeObserver($0.1) }
        observers.removeAll()
        removeActivityMonitor()
        endScan(.idle)
        if let a = activity { ProcessInfo.processInfo.endActivity(a); activity = nil }
        template = nil; password = nil; credentialsLoaded = false
    }

    /// Lädt Vorlage und Passwort in den Speicher (einmal beim Start, nicht erst am Sperrbildschirm,
    /// damit eine mögliche Schlüsselbund-Abfrage beantwortet werden kann, solange du davor sitzt).
    func reloadCredentials() {
        DispatchQueue.global(qos: .userInitiated).async {
            let migrated = FaceStore.migrateLegacyIfNeeded()
            let t = FaceStore.loadTemplate(), p = FaceStore.loadPassword()
            DispatchQueue.main.async { [weak self] in
                if let migrated { self?.addLog(migrated) }
                self?.template = t; self?.password = p
                self?.credentialsLoaded = true
                self?.enrolled = t != nil && p != nil
                self?.addLog("Daten geladen: Gesicht \(t != nil ? "ja" : "nein"), Passwort \(p != nil ? "ja" : "nein")")
            }
        }
    }

    func forgetEverything() {
        FaceStore.deleteAll()
        template = nil; password = nil; enrolled = false
        addLog("Gesicht und Passwort gelöscht")
    }

    // MARK: Zustand des Bildschirms

    /// Verbindlicher Sperrzustand vom Sitzungs-Server (nicht von einer fälschbaren Benachrichtigung).
    static func screenIsLocked() -> Bool {
        guard let d = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return (d["CGSSessionScreenIsLocked"] as? Bool) ?? (d["CGSSessionScreenIsLocked"] as? NSNumber)?.boolValue ?? false
    }

    // MARK: Auslöser

    private func wake(_ reason: String) {
        sleeping = false
        autoRetried = false
        addLog("\(reason)")
        DispatchQueue.global(qos: .utility).async { [analyzer] in analyzer.prewarm() }
        prewarmCamera()
        scanSoon(reason, delay: 0)
    }

    /// Die Kamera braucht rund 1,5 Sekunden zum Hochfahren. Deshalb startet sie schon beim Aufwachen, noch bevor der
    /// Sperrzustand geprüft ist. Wird der Bildschirm nicht gesperrt, geht sie nach 2 Sekunden wieder aus.
    private func prewarmCamera() {
        guard started, Pref.bool("modFace"), template != nil, Self.expectsLockOnWake(),
              AVCaptureDevice.authorizationStatus(for: .video) == .authorized, phase == .idle else { return }
        camera.onFrame = nil; camera.onFirstFrame = nil
        camera.start(deviceID: Pref.string("faceCamera")) { _ in }
        addLog("Kamera wird vorgewärmt")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self, self.phase == .idle else { return }
            self.camera.stop()
        }
    }

    /// Sperrt der Mac beim Aufwachen sofort? Steht die Einstellung „Kennwort erforderlich“ auf einer langen Zeit,
    /// lohnt sich das Vorwärmen nicht. Unbekannt gilt als „ja“.
    private static func expectsLockOnWake() -> Bool {
        let ask = CFPreferencesCopyAppValue("askForPassword" as CFString, "com.apple.screensaver" as CFString) as? Int
        let delay = CFPreferencesCopyAppValue("askForPasswordDelay" as CFString, "com.apple.screensaver" as CFString) as? Int
        if let ask, ask == 0 { return false }
        if let delay, delay > 10 { return false }
        return true
    }

    private func installActivityMonitor() {
        guard activityMonitor == nil, Pref.bool("faceOnActivity") else { return }
        activityMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .scrollWheel, .leftMouseDown]) { [weak self] _ in
            guard let self, self.phase == .idle, Date().timeIntervalSince(self.lastActivityScan) > 4 else { return }
            self.lastActivityScan = Date()
            self.scanSoon("Maus bewegt", delay: 0)
        }
    }

    private func removeActivityMonitor() {
        if let m = activityMonitor { NSEvent.removeMonitor(m); activityMonitor = nil }
    }

    private func scanSoon(_ reason: String, delay: TimeInterval) {
        guard started, Pref.bool("modFace") else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.beginScan(reason: reason, attemptsLeft: 8)
        }
    }

    // MARK: Scan

    /// Für „Testen“ in den Einstellungen: läuft auch bei entsperrtem Bildschirm und tippt nie.
    func testScan() {
        testMode = true
        beginScan(reason: "Test", attemptsLeft: 0)
    }

    private var isFailed: Bool { if case .failed = phase { return true }; return false }

    private func beginScan(reason: String, attemptsLeft: Int) {
        guard started || testMode, !sleeping || testMode, phase == .idle || phase == .rejected || isFailed else { return }
        guard Date() > cooldownUntil else { return }
        // Der Sperrzustand kann gleich nach dem Aufwachen noch kurz hinterherhinken: schnell nachprüfen, nicht lange warten.
        if !testMode && !Self.screenIsLocked() {
            if attemptsLeft > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in self?.beginScan(reason: reason, attemptsLeft: attemptsLeft - 1) }
            } else {
                addLog("Kein Scan: Bildschirm nicht gesperrt (\(reason))")
            }
            return
        }
        guard credentialsLoaded else {
            if attemptsLeft > 0 { DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in self?.beginScan(reason: reason, attemptsLeft: attemptsLeft - 1) } }
            return
        }
        guard let template else { fail("Noch kein Gesicht eingelernt"); return }
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else { fail("Kamera-Zugriff fehlt"); return }

        generation += 1
        let gen = generation
        scanStart = Date(); gotFrame = false; wrongSince = nil
        phase = .scanning; score = 0; recent = []
        addLog("Scan gestartet (\(reason))")
        let strictness = FaceMatcher.Strictness(rawValue: Pref.string("faceStrictness")) ?? .normal

        camera.onEvent = { [weak self] m in DispatchQueue.main.async { self?.addLog(m) } }
        // Die Animation startet erst, wenn die Kamera wirklich Bilder liefert.
        camera.onFirstFrame = { [weak self] in
            guard let self, self.generation == gen, self.phase == .scanning else { return }
            self.gotFrame = true
            self.addLog("Kamera läuft")
            FaceScanIsland.shared.show(.searching, locked: Self.screenIsLocked())
        }
        analysisTimes = []
        camera.onFrame = { [weak self] pb in
            guard let self, self.slots.wait(timeout: .now()) == .success else { return }
            self.analysisQueue.async {
                let t = Date()
                var hasFace = false, ok = false, s: Float = 0
                if let f = self.analyzer.analyze(pb) { hasFace = true; (ok, s) = FaceMatcher.matches(f, template: template, strictness: strictness) }
                let took = Date().timeIntervalSince(t) * 1000
                self.slots.signal()
                DispatchQueue.main.async { self.analysisTimes.append(took); self.consume(gen, hasFace: hasFace, ok: ok, score: s) }
            }
        }
        camera.start(deviceID: Pref.string("faceCamera")) { [weak self] ok in
            guard let self, self.generation == gen else { return }
            if ok { self.addLog("Kamera gestartet") } else { self.fail("Kamera nicht verfügbar") }
        }
        deadline?.invalidate()
        deadline = Timer.scheduledTimer(withTimeInterval: max(3, Pref.double("faceScanSeconds")), repeats: false) { [weak self] _ in
            guard let self, self.generation == gen, self.phase == .scanning else { return }
            if !self.gotFrame { self.fail("Die Kamera liefert keine Bilder") }
            else { self.addLog("Gesicht nicht erkannt (Zeit abgelaufen)"); self.endScan(.rejected) }
        }
    }

    private func ms() -> String { "+\(Int(Date().timeIntervalSince(scanStart) * 1000)) ms" }

    private func consume(_ gen: Int, hasFace: Bool, ok: Bool, score s: Float) {
        guard gen == generation, phase == .scanning else { return }
        score = s
        if ok { wrongSince = nil }
        else if hasFace {
            // Eine Weile Nicht-Treffer ist normal (man schaut noch weg). Erst nach 2 Sekunden am Stück gilt es als falsches Gesicht.
            if let w = wrongSince { if Date().timeIntervalSince(w) >= 2 { addLog("Falsches Gesicht (2 s ohne Treffer) \(ms())"); endScan(.rejected); return } }
            else { wrongSince = Date() }
        } else { wrongSince = nil }
        if hasFace { recent.append(ok); if recent.count > 5 { recent.removeFirst() } }
        if recent.filter({ $0 }).count >= needed { recognized() }
    }

    private func recognized() {
        camera.stop()
        deadline?.invalidate()
        phase = .recognized
        let avg = analysisTimes.isEmpty ? 0 : Int(analysisTimes.reduce(0, +) / Double(analysisTimes.count))
        addLog("Gesicht erkannt \(ms()), \(analysisTimes.count) Bilder, Ø \(avg) ms pro Bild")
        let willType = Pref.bool("faceTypePassword") && !testMode
        FaceScanIsland.shared.show(willType ? .recognized : .recognizedDry, locked: Self.screenIsLocked())
        if willType {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in self?.typePassword() }
        } else {
            addLog(testMode ? "Test: nichts getippt" : "Probelauf: Passwort nicht getippt")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in self?.endScan(.idle) }
        }
    }

    private func fail(_ message: String) {
        addLog("Fehler: \(message)")
        generation += 1
        camera.stop(); deadline?.invalidate()
        phase = .failed(message)
        FaceScanIsland.shared.show(.error(message), locked: Self.screenIsLocked())
        cooldownUntil = Date().addingTimeInterval(2)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) { [weak self] in self?.endScan(.idle) }
    }

    func endScan(_ final: Phase) {
        generation += 1
        camera.stop(); deadline?.invalidate(); deadline = nil
        camera.onFrame = nil; camera.onFirstFrame = nil
        let wasTest = testMode
        testMode = false
        if final == .rejected {
            phase = .rejected
            cooldownUntil = Date().addingTimeInterval(0.8)
            FaceScanIsland.shared.show(.denied, locked: Self.screenIsLocked())
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
                if self?.phase == .rejected { self?.phase = .idle }
            }
            // Einmal automatisch erneut versuchen, falls man beim Aufwachen noch weggeschaut hat.
            if !autoRetried && !wasTest && Self.screenIsLocked() {
                autoRetried = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                    guard let self, Self.screenIsLocked() else { return }
                    self.beginScan(reason: "Wiederholung", attemptsLeft: 0)
                }
            }
        } else {
            phase = .idle
            FaceScanIsland.shared.hide()
        }
    }

    // MARK: Passwort tippen

    private func typePassword() {
        guard let pw = password, !pw.isEmpty else { fail("Kein Passwort gespeichert"); return }
        guard InputTap.trusted else { fail("Bedienungshilfen fehlen: Islet in der Liste entfernen und neu hinzufügen"); return }
        guard typedAttempts < 2 else { fail("Zwei Versuche gescheitert: bitte einmal von Hand entsperren"); return }
        guard Self.screenIsLocked() else { fail("Bildschirm ist nicht gesperrt, nichts getippt"); return }
        typedAttempts += 1
        let attempt = typedAttempts
        phase = .typing
        FaceScanIsland.shared.show(.unlocking, locked: true)
        addLog("Passwort wird getippt (Versuch \(attempt)) \(ms())")
        let t0 = Date()

        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            // Läuft noch der Bildschirmschoner, verschluckt die erste Taste nur das Aufwecken: kurz warten, bis das Feld da ist.
            let saver = NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == "com.apple.ScreenSaver.Engine" }
            if saver { FaceTyping.tap(0x38); Thread.sleep(forTimeInterval: 0.7) } else { Thread.sleep(forTimeInterval: 0.03) }
            guard Self.screenIsLocked() else {       // zweite Prüfung direkt vor dem Tippen
                DispatchQueue.main.async { self?.fail("Sperrbildschirm weg, abgebrochen") }
                return
            }
            FaceTyping.typeAndReturn(pw)
            let typed = Int(Date().timeIntervalSince(t0) * 1000)
            DispatchQueue.main.async { self?.addLog("Return gesendet nach \(typed) ms") }
            // Sofort weitermachen, sobald macOS entsperrt hat (höchstens 5 Sekunden warten).
            for _ in 0..<50 {
                Thread.sleep(forTimeInterval: 0.1)
                if !Self.screenIsLocked() {
                    DispatchQueue.main.async {
                        guard let self else { return }
                        self.addLog("Entsperrt \(self.ms()), \(Int(Date().timeIntervalSince(t0) * 1000)) ms nach dem Tippen")
                        self.endScan(.idle)
                    }
                    return
                }
            }
            DispatchQueue.main.async {
                guard let self else { return }
                if attempt < 2 {
                    self.addLog("Nicht angenommen, zweiter Versuch")
                    self.typePassword()
                } else {
                    self.fail("Passwort wurde nicht angenommen")
                }
            }
        }
    }

    // MARK: Protokoll

    func addLog(_ line: String) {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"
        log.insert("\(f.string(from: Date()))  \(line)", at: 0)
        if log.count > 40 { log.removeLast(log.count - 40) }
        FaceLog.write(line)
    }
}
