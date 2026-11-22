import AppKit
import SwiftUI

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
        guard let path = value("--snapshot") else { return false }
        IslandGeometry.shared.notchWidth = 200
        IslandGeometry.shared.notchHeight = 34
        IslandState.shared.expanded = true
        if let t = value("--tab"), let tab = IslandTab(rawValue: t) { IslandState.shared.tab = tab }
        if value("--clip") != nil {
            Clipboard.shared.items = ["https://github.com/loubornhauser-creator/islet", "swift build -c release", "Termin mit Lena am Montag um 14 Uhr", "ssh deploy@server"].map { ClipItem(text: $0, date: Date().addingTimeInterval(-120)) }
        }
        let w = Pref.double("expandedWidth"), h = Pref.double("expandedHeight")
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
            print("Gesten-Start möglich:", Gestures.shared.start()); Gestures.shared.stop()
            exit(0)
        }
        if snapshotIfRequested() { return }
        island = IslandController()
        Hotkey.shared.onPress = { IslandState.shared.hotkeyToggle() }
        setupStatusItem()
        applyModules()
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.applyModules()
        }
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
            if !InputTap.shared.start() && !InputTap.trusted && !askedPermission {
                askedPermission = true
                InputTap.requestPermission()
            }
        } else {
            InputTap.shared.stop()
        }
    }

    private var askedPermission = false

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
        menu.addItem(withTitle: "Einstellungen …", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Islet beenden", action: #selector(quit), keyEquivalent: "q").target = self
        item.menu = menu
        statusItem = item
    }

    @objc private func openSettings() { SettingsWindow.show() }
    @objc private func toggleIsland() { IslandState.shared.toggle() }

    @objc private func quit() { NSApp.terminate(nil) }
}
