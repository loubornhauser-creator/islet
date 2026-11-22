import Foundation
import IOKit.pwr_mgt
import Darwin

/// Koffein-Modus: startet `caffeinate` und prüft live, ob irgendein `caffeinate`
/// (auch aus dem Terminal gestartet) gerade Schlaf verhindert.
final class Caffeine: ObservableObject {
    static let shared = Caffeine()

    @Published var active = false
    private var timer: Timer?
    private var process: Process?
    private var interval: TimeInterval = 3
    private var enabled = false

    func start() {
        guard !enabled else { return }
        enabled = true
        refresh()
        schedule()
    }

    func stop() {
        enabled = false
        timer?.invalidate(); timer = nil
        active = false
    }

    /// Im geöffneten Panel schneller prüfen, sonst sparsam.
    func setFast(_ fast: Bool) {
        interval = fast ? 1 : 3
        if enabled { refresh(); schedule() }
    }

    private func schedule() {
        timer?.invalidate()
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.refresh() }
        t.tolerance = interval * 0.3
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func refresh() {
        let now = Self.caffeinateRunning()
        if now != active { active = now }
    }

    func toggle() { active ? turnOff() : turnOn(seconds: nil) }

    func turnOn(seconds: Int?) {
        turnOff(refreshNow: false)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        var args = ["-dims"]
        if let seconds { args += ["-t", String(seconds)] }
        p.arguments = args
        p.terminationHandler = { [weak self] _ in DispatchQueue.main.async { self?.refresh() } }
        try? p.run()
        process = p
        active = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.refresh() }
    }

    func turnOff(refreshNow: Bool = true) {
        process?.terminationHandler = nil
        process?.terminate()
        process = nil
        // Auch ein im Terminal gestartetes caffeinate beenden.
        let k = Process()
        k.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        k.arguments = ["-x", "caffeinate"]
        try? k.run()
        k.waitUntilExit()
        if refreshNow {
            active = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.refresh() }
        }
    }

    /// Wird beim Beenden aufgerufen: nur das eigene caffeinate stoppen.
    func shutdown() {
        process?.terminationHandler = nil
        process?.terminate()
    }

    static func caffeinateRunning() -> Bool {
        var unmanaged: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&unmanaged) == kIOReturnSuccess,
              let dict = unmanaged?.takeRetainedValue() as? [NSNumber: Any] else { return false }
        var buf = [CChar](repeating: 0, count: 64)
        for pid in dict.keys {
            buf[0] = 0
            if proc_name(pid.int32Value, &buf, UInt32(buf.count)) > 0,
               String(cString: buf) == "caffeinate" { return true }
        }
        return false
    }
}
