import CoreAudio
import AppKit

struct BTBattery: Identifiable, Equatable {
    let id: String        // L, R, C, M
    let label: String
    let percent: Int
}

struct BTDevice: Identifiable, Equatable {
    var id: String { name }
    let name: String
    let kind: String
    let batteries: [BTBattery]
    let symbol: String

    /// Der niedrigste Wert der Ohrhörer, sonst der Hauptakku (für die kompakte Anzeige).
    var level: Int? {
        let buds = batteries.filter { $0.id == "L" || $0.id == "R" }.map(\.percent)
        if let m = buds.min() { return m }
        return batteries.first { $0.id == "M" }?.percent ?? batteries.first?.percent
    }

    var kindLabel: String {
        switch kind.lowercased() {
        case "headphones": return "Kopfhörer"
        case "headset": return "Headset"
        case "speaker", "loudspeaker": return "Lautsprecher"
        case "mouse": return "Maus"
        case "keyboard": return "Tastatur"
        case "trackpad": return "Trackpad"
        case "gamepad", "game controller": return "Controller"
        case "": return "Bluetooth"
        default: return kind
        }
    }
}

/// Verbundene Bluetooth-Geräte mit Akkustand (AirPods, Maus, Tastatur …).
/// Verbindungen erkennt Islet ereignisgesteuert über die CoreAudio-Geräteliste, den Akkustand liest es
/// bei Bedarf über `system_profiler` (keine Bluetooth-Berechtigung nötig, kein Dauer-Polling).
final class Devices: ObservableObject {
    static let shared = Devices()

    @Published var connected: [BTDevice] = []
    /// Kurz nach dem Verbinden eines Audio-Geräts, für die kompakte Insel.
    @Published var chip: BTDevice?
    @Published var refreshing = false

    private var started = false
    private var knownAudio: Set<String> = []
    private var listener: AudioObjectPropertyListenerBlock?
    private var lastRefresh = Date.distantPast
    private var chipWork: DispatchWorkItem?

    // MARK: Start/Stop

    func start() {
        guard !started else { return }
        started = true
        knownAudio = Set(Self.bluetoothAudioNames())
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.devicesChanged() }
        listener = block
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, .main, block)
    }

    func stop() {
        guard started else { return }
        started = false
        if let b = listener {
            var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                                  mScope: kAudioObjectPropertyScopeGlobal,
                                                  mElement: kAudioObjectPropertyElementMain)
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, .main, b)
        }
        listener = nil
        chipWork?.cancel()
        connected = []; chip = nil
    }

    // MARK: Verbindungen

    private func devicesChanged() {
        let now = Set(Self.bluetoothAudioNames())
        let added = now.subtracting(knownAudio)
        let removed = knownAudio.subtracting(now)
        knownAudio = now
        if let name = added.first { didConnect(name) }
        else if !removed.isEmpty {
            if let c = chip, removed.contains(c.name) { chip = nil }
            refresh(force: true)
        }
    }

    private func didConnect(_ name: String) {
        showChip(BTDevice(name: name, kind: "Headphones", batteries: [], symbol: Self.symbol(name: name, kind: "")))
        // Der Akkustand ist erst nach ein paar Sekunden verfügbar.
        for delay in [1.5, 5.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.refresh(force: true) { list in
                    guard let self, let d = list.first(where: { $0.name == name }), self.chip?.name == name else { return }
                    self.chip = d
                }
            }
        }
    }

    private func showChip(_ d: BTDevice) {
        chip = d
        chipWork?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.chip = nil }
        chipWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: w)
    }

    // MARK: Akkustand

    func refresh(force: Bool = false, completion: (([BTDevice]) -> Void)? = nil) {
        guard started else { completion?([]); return }
        if !force, Date().timeIntervalSince(lastRefresh) < 20 { completion?(connected); return }
        lastRefresh = Date()
        refreshing = true
        DispatchQueue.global(qos: .utility).async {
            let list = Self.readProfiler()
            DispatchQueue.main.async { [weak self] in
                self?.refreshing = false
                self?.connected = list
                completion?(list)
            }
        }
    }

    static func readProfiler() -> [BTDevice] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        p.arguments = ["SPBluetoothDataType", "-json"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return parse(data)
    }

    static func parse(_ data: Data) -> [BTDevice] {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let sections = root["SPBluetoothDataType"] as? [[String: Any]],
              let list = sections.first?["device_connected"] as? [[String: Any]] else { return [] }
        // Dasselbe Gerät kann mehrfach auftauchen (z. B. klassisch und LE): nach Namen zusammenfassen und die Akkuwerte vereinen.
        var byName: [String: BTDevice] = [:]
        let order = ["L", "R", "C", "M"]
        for entry in list {
            for (name, value) in entry {
                guard let info = value as? [String: Any] else { continue }
                func pct(_ key: String) -> Int? {
                    (info[key] as? String).flatMap { Int($0.filter(\.isNumber)) }
                }
                var bats: [BTBattery] = []
                if let v = pct("device_batteryLevelLeft") { bats.append(BTBattery(id: "L", label: "L", percent: v)) }
                if let v = pct("device_batteryLevelRight") { bats.append(BTBattery(id: "R", label: "R", percent: v)) }
                if let v = pct("device_batteryLevelCase") { bats.append(BTBattery(id: "C", label: "Hülle", percent: v)) }
                if let v = pct("device_batteryLevelMain") { bats.append(BTBattery(id: "M", label: "Akku", percent: v)) }
                let kind = info["device_minorType"] as? String ?? ""
                let new = BTDevice(name: name, kind: kind, batteries: bats, symbol: symbol(name: name, kind: kind))
                if let old = byName[name] {
                    var merged = old.batteries
                    for b in new.batteries where !merged.contains(where: { $0.id == b.id }) { merged.append(b) }
                    merged.sort { (order.firstIndex(of: $0.id) ?? 9) < (order.firstIndex(of: $1.id) ?? 9) }
                    byName[name] = BTDevice(name: name, kind: old.kind.isEmpty ? new.kind : old.kind, batteries: merged, symbol: old.symbol)
                } else {
                    byName[name] = new
                }
            }
        }
        return byName.values.sorted { $0.name < $1.name }
    }

    static func symbol(name: String, kind: String) -> String {
        let n = name.lowercased(), k = kind.lowercased()
        let candidate: String
        if k.contains("mouse") { candidate = n.contains("magic") ? "magicmouse.fill" : "computermouse.fill" }
        else if k.contains("keyboard") { candidate = "keyboard.fill" }
        else if k.contains("trackpad") { candidate = "rectangle.fill" }
        else if k.contains("game") { candidate = "gamecontroller.fill" }
        else { candidate = AudioControl.symbol(name: name, transport: UInt32(kAudioDeviceTransportTypeBluetooth), source: 0) ?? "headphones" }
        return NSImage(systemSymbolName: candidate, accessibilityDescription: nil) != nil ? candidate : "dot.radiowaves.left.and.right"
    }

    // MARK: CoreAudio

    static func bluetoothAudioNames() -> [String] {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr else { return [] }
        var names: [String] = []
        for id in ids {
            var ta = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyTransportType,
                                                mScope: kAudioObjectPropertyScopeGlobal,
                                                mElement: kAudioObjectPropertyElementMain)
            var transport: UInt32 = 0
            var tsize = UInt32(MemoryLayout<UInt32>.size)
            guard AudioObjectGetPropertyData(id, &ta, 0, nil, &tsize, &transport) == noErr,
                  transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE else { continue }
            var na = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName,
                                                mScope: kAudioObjectPropertyScopeGlobal,
                                                mElement: kAudioObjectPropertyElementMain)
            var cf: Unmanaged<CFString>?
            var nsize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            if AudioObjectGetPropertyData(id, &na, 0, nil, &nsize, &cf) == noErr, let s = cf?.takeRetainedValue() as String? {
                names.append(s)
            }
        }
        return names
    }
}
