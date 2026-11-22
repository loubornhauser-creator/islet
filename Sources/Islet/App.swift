import AppKit
import SwiftUI
import EventKit

@main
struct IsletMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var island: IslandController?
    private var statusItem: NSStatusItem?
    private var applied: [String: Bool] = [:]

    /// `Islet --snapshot out.png [--tab music|overview|clipboard|actions]` rendert die Insel,
    /// `Islet --snapshot-settings out.png --page general|modules|…` rendert eine Einstellungsseite (für Tests).
    private func snapshotIfRequested() -> Bool {
        let args = CommandLine.arguments
        func value(_ flag: String) -> String? {
            guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
            return args[i + 1]
        }
        if let path = value("--snapshot-settings") {
            if let p = value("--page"), let page = SettingsPage(rawValue: p) { SettingsNav.shared.page = page }
            let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 600), styleMask: [.borderless], backing: .buffered, defer: false)
            let host = NSHostingView(rootView: SettingsView())
            win.contentView = host
            win.orderFrontRegardless()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { Self.write(host, to: path) }
            return true
        }
        if let path = value("--snapshot-tutorial") {
            let page = Int(value("--page") ?? "0") ?? 0
            let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 520), styleMask: [.borderless], backing: .buffered, defer: false)
            let host = NSHostingView(rootView: TutorialView(startPage: page, onFinish: {}))
            win.contentView = host
            win.orderFrontRegardless()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { Self.write(host, to: path) }
            return true
        }
        if let path = value("--snapshot-moduleinfo"), let doc = ModuleDocs.doc(for: value("--module") ?? "modMusic") {
            let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 420), styleMask: [.borderless], backing: .buffered, defer: false)
            let host = NSHostingView(rootView: ModuleInfoView(doc: doc).background(Color(nsColor: .windowBackgroundColor)))
            win.contentView = host
            win.setContentSize(host.fittingSize)
            win.orderFrontRegardless()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { Self.write(host, to: path) }
            return true
        }
        if let path = value("--snapshot-cleaning") {
            CleaningLock.shared.endDate = Date().addingTimeInterval(105)
            let dim = value("--dim") != nil
            let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: dim ? 720 : 420, height: dim ? 420 : 170), styleMask: [.borderless], backing: .buffered, defer: false)
            win.backgroundColor = NSColor(white: 0.3, alpha: 1)
            let host = NSHostingView(rootView: CleaningView(dim: dim))
            win.contentView = host
            win.orderFrontRegardless()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { Self.write(host, to: path) }
            return true
        }
        guard let path = value("--snapshot") else { return false }
        IslandGeometry.shared.notchWidth = 200
        IslandGeometry.shared.notchHeight = 34
        IslandState.shared.openImmediately()
        if let t = value("--tab"), let tab = IslandTab(rawValue: t) { IslandState.shared.tab = tab }
        if value("--clip") != nil {
            Clipboard.shared.items = ["https://github.com/loubornhauser-creator/islet", "swift build -c release", "Termin am Montag um 14 Uhr", "ssh deploy@server"].map { ClipItem(text: $0, date: Date().addingTimeInterval(-120)) }
        }
        if value("--cal") != nil {
            let now = Date()
            CalendarModule.shared.status = .fullAccess
            CalendarModule.shared.events = [
                CalEvent(id: "1", title: "Design-Review", start: now.addingTimeInterval(-900), end: now.addingTimeInterval(1800), allDay: false, location: "Zoom", color: .blue),
                CalEvent(id: "2", title: "Mittagessen", start: now.addingTimeInterval(5400), end: now.addingTimeInterval(9000), allDay: false, location: "Café Aura", color: .green),
                CalEvent(id: "3", title: "Frames: Angebot abschicken", start: now.addingTimeInterval(20000), end: now.addingTimeInterval(23000), allDay: false, location: nil, color: .orange),
                CalEvent(id: "4", title: "Geburtstag Mama", start: now.addingTimeInterval(86400), end: now.addingTimeInterval(86400 + 3600), allDay: true, location: nil, color: .pink),
            ]
        }
        if value("--dev") != nil {
            let airpods = BTDevice(name: "AirPods Pro", kind: "Headphones",
                                   batteries: [BTBattery(id: "L", label: "L", percent: 47), BTBattery(id: "R", label: "R", percent: 89), BTBattery(id: "C", label: "Hülle", percent: 51)],
                                   symbol: "airpodspro")
            Devices.shared.connected = [airpods, BTDevice(name: "Magic Mouse", kind: "Mouse", batteries: [BTBattery(id: "M", label: "Akku", percent: 72)], symbol: "magicmouse.fill")]
        }
        if value("--claude") != nil {
            let now = Date()
            ClaudeUsage.shared.state = .ok
            ClaudeUsage.shared.plan = "Max"
            ClaudeUsage.shared.updated = now
            ClaudeUsage.shared.windows = [
                UsageWindow(title: "Session (5 Stunden)", percent: 37, resetsAt: now.addingTimeInterval(2 * 3600 + 14 * 60)),
                UsageWindow(title: "Woche (7 Tage)", percent: 78, resetsAt: now.addingTimeInterval(3 * 86400)),
                UsageWindow(title: "Woche Opus", percent: 93, resetsAt: now.addingTimeInterval(3 * 86400)),
            ]
        }
        if value("--music") != nil {
            Music.shared.running = true
            Music.shared.title = "Beispiel-Titel"
            Music.shared.artist = "Beispiel-Künstler"
            Music.shared.isPlaying = true
            Music.shared.duration = 215
        }
        if value("--rem") != nil {
            let now = Date()
            CalendarModule.shared.reminderStatus = .fullAccess
            CalendarModule.shared.reminders = [
                ReminderItem(id: "r1", title: "Rechnung an Frames schicken", due: now.addingTimeInterval(-2 * 86400), hasTime: false, list: "Arbeit", color: .red, priority: 1),
                ReminderItem(id: "r2", title: "Zahnarzt anrufen", due: now.addingTimeInterval(3600), hasTime: true, list: "Privat", color: .blue, priority: 0),
                ReminderItem(id: "r3", title: "Geschenk für Mama bestellen", due: now.addingTimeInterval(86400), hasTime: false, list: "Privat", color: .blue, priority: 0),
            ]
        }
        let w = Double(IslandGeometry.shared.expandedWidth), h = Double(IslandGeometry.shared.expandedHeight)
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: w + 40, height: h + 20),
                           styleMask: [.borderless], backing: .buffered, defer: false)
        win.backgroundColor = NSColor(white: 0.35, alpha: 1)
        let host = NSHostingView(rootView: IslandView())
        win.contentView = host
        win.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { Self.write(host, to: path) }
        return true
    }

    private static func write(_ host: NSView, to path: String) {
        if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        }
        exit(0)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Pref.register()
        keepExistingBehaviourIfTrusted()
        if CommandLine.arguments.contains("--selftest") {
            print("caffeinate läuft:", Caffeine.caffeinateRunning())
            print("Helligkeit verfügbar:", Brightness.available, Brightness.current ?? -1)
            AudioControl.shared.start()
            print("Ausgabegerät:", AudioControl.shared.outputName, "->", AudioControl.shared.outputSymbol ?? "Lautsprecher (Pegel-Symbol)")
            for (n, t, d) in [("Lou\u{2019}s AirPods Pro", "blue", ""), ("AirPods Max", "blue", ""), ("AirPods (3rd generation)", "blue", ""),
                              ("WH-1000XM5 Headset", "blue", ""), ("JBL Flip 6", "blue", ""), ("DELL U2723QE", "dprt", ""),
                              ("MacBook Pro Speakers", "bltn", "ispk"), ("External Headphones", "bltn", "hdpn")] {
                let f: (String) -> UInt32 = { $0.utf8.reduce(0) { ($0 << 8) | UInt32($1) } }
                print("  Test:", n, "->", AudioControl.symbol(name: n, transport: f(t), source: d.isEmpty ? 0 : f(d)) ?? "Lautsprecher")
            }
            print("Lautstärke:", AudioControl.shared.volume, "stumm:", AudioControl.shared.muted)
            print("Bedienungshilfen erlaubt:", InputTap.trusted)
            let bt = Devices.readProfiler()
            print("Bluetooth-Geräte verbunden:", bt.count)
            for d in bt { print("  ", d.name, "[\(d.kindLabel)]", d.symbol, d.batteries.map { "\($0.label) \($0.percent)%" }.joined(separator: " "), "-> Anzeige:", d.level.map { "\($0)%" } ?? "-") }
            print("Bluetooth-Audio (CoreAudio):", Devices.bluetoothAudioNames())
            print("Kalender-Status:", EKEventStore.authorizationStatus(for: .event).rawValue, "(3 = voller Zugriff)")
            print("Gesten-Start möglich:", Gestures.shared.start()); Gestures.shared.stop()
            exit(0)
        }
        if snapshotIfRequested() { return }
        island = IslandController()
        Hotkey.shared.onPress = { IslandState.shared.hotkeyToggle() }
        if !Pref.bool("tutorialDone") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { TutorialWindow.show() }
        }
        setupStatusItem()
        applyModules()
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.applyModules()
        }
    }

    /// Früher waren Tasten-Ersatz und Trackpad-Gesten standardmäßig an. Wer die Bedienungshilfen schon erteilt hat,
    /// behält sie, alle anderen starten ohne jede Freigabe-Abfrage.
    private func keepExistingBehaviourIfTrusted() {
        guard InputTap.trusted else { return }
        let stored = UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "app.islet.mac") ?? [:]
        for k in ["hudReplaceSystem", "modGestures"] where stored[k] == nil { UserDefaults.standard.set(true, forKey: k) }
    }

    func applicationWillTerminate(_ notification: Notification) {
        Caffeine.shared.shutdown()
    }

    // MARK: Module an/aus

    private func toggled(_ key: String) -> Bool? {
        let now = Pref.bool(key)
        if applied[key] == now { return nil }
        applied[key] = now
        return now
    }

    private func applyModules() {
        if let on = toggled("modMusic") { on ? Music.shared.start() : Music.shared.stop() }
        if let on = toggled("modCaffeine") { on ? Caffeine.shared.start() : Caffeine.shared.stop() }
        if let on = toggled("modBattery") { on ? Battery.shared.start() : Battery.shared.stop() }
        if let on = toggled("modTimer"), !on { CountdownTimer.shared.stop() }
        if let on = toggled("modClipboard") { on ? Clipboard.shared.start() : Clipboard.shared.stop() }
        if let on = toggled("modIndicators") { on ? Indicators.shared.start() : Indicators.shared.stop() }
        if let on = toggled("modCalendar") { on ? CalendarModule.shared.start() : CalendarModule.shared.stop() }
        if let on = toggled("modDevices") { on ? Devices.shared.start() : Devices.shared.stop() }
        if let on = toggled("modClaude") { on ? ClaudeUsage.shared.start() : ClaudeUsage.shared.stop() }
        if let on = toggled("modFace") { on ? FaceUnlock.shared.start() : FaceUnlock.shared.stop() }
        CalendarModule.shared.reloadIfSettingsChanged()

        Hotkey.shared.apply(Pref.string("hotkey"))
        statusItem?.isVisible = Pref.bool("showMenuBarIcon")

        let hud = Pref.bool("modHUD")
        let replace = Pref.bool("hudReplaceSystem")
        let gestures = Pref.bool("modGestures")
        Gestures.shared.reloadSettings()

        // CoreAudio-Listener: zeigt die Bar auch bei Änderungen von außen.
        if hud {
            AudioControl.shared.onExternalChange = {
                let a = AudioControl.shared
                HUDController.shared.show(.volume, value: Double(a.volume), muted: a.muted)
            }
            AudioControl.shared.start()
        } else if !Pref.bool("modMusic") {
            AudioControl.shared.stop()
        }
        if Pref.bool("modMusic") { AudioControl.shared.start() }

        // Medientasten
        InputTap.shared.consumesKeys = hud && replace
        InputTap.shared.onMediaKey = hud && replace ? { key, flags in Self.handleKey(key, flags) } : nil

        // Gesten
        if gestures {
            Gestures.shared.onDelta = { side, delta in
                DispatchQueue.main.async { Self.handleGesture(side, delta) }
            }
            Gestures.shared.start()
        } else {
            Gestures.shared.stop()
        }

        if (hud && replace) || gestures {
            // Nie von selbst nach der Freigabe fragen: Wer die Funktion einschaltet, bekommt in den Einstellungen einen Knopf dafür.
            InputTap.shared.start()
        } else {
            InputTap.shared.stop()
        }
    }

    private static func handleKey(_ key: Int, _ flags: NSEvent.ModifierFlags) -> Bool {
        let fine = flags.contains(.shift) && flags.contains(.option)
        let step: Float = fine ? 1.0 / 64 : 1.0 / 16
        DispatchQueue.main.async {
            let audio = AudioControl.shared
            switch key {
            case 0: audio.adjust(step); HUDController.shared.show(.volume, value: Double(audio.volume), muted: audio.muted)
            case 1: audio.adjust(-step); HUDController.shared.show(.volume, value: Double(audio.volume), muted: audio.muted)
            case 7: audio.toggleMute(); HUDController.shared.show(.volume, value: Double(audio.volume), muted: audio.muted)
            case 2: if let v = Brightness.adjust(step) { HUDController.shared.show(.brightness, value: Double(v)) }
            case 3: if let v = Brightness.adjust(-step) { HUDController.shared.show(.brightness, value: Double(v)) }
            default: break
            }
        }
        return true
    }

    private static func handleGesture(_ side: Gestures.Side, _ delta: Float) {
        let target = Pref.string(side == .left ? "gestureLeft" : "gestureRight")
        switch target {
        case "volume":
            let a = AudioControl.shared
            a.adjust(delta)
            HUDController.shared.show(.volume, value: Double(a.volume), muted: a.muted)
        case "brightness":
            if let v = Brightness.adjust(delta) { HUDController.shared.show(.brightness, value: Double(v)) }
        default: break
        }
    }

    // MARK: Menüleiste & Einstellungen

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "capsule.fill", accessibilityDescription: "Islet")
        let menu = NSMenu()
        menu.addItem(withTitle: "Insel öffnen/schließen", action: #selector(toggleIsland), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Tastatur reinigen", action: #selector(startCleaning), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Einführung …", action: #selector(showTutorial), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Einstellungen …", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Islet beenden", action: #selector(quit), keyEquivalent: "q").target = self
        item.menu = menu
        statusItem = item
    }

    @objc private func openSettings() { SettingsWindow.show() }
    @objc private func toggleIsland() { IslandState.shared.toggle() }
    @objc private func startCleaning() { CleaningLock.shared.start() }
    @objc private func showTutorial() { TutorialWindow.show() }

    @objc private func quit() { NSApp.terminate(nil) }
}
