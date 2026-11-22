import CoreAudio
import Foundation
import AppKit

/// Systemlautstärke über CoreAudio, ereignisgesteuert (Listener statt Polling).
final class AudioControl: ObservableObject {
    static let shared = AudioControl()

    @Published var volume: Float = 0
    @Published var muted = false
    /// SF-Symbol des aktuellen Ausgabegeräts (AirPods, Kopfhörer, Lautsprecher, Monitor …).
    /// `nil` = normale Mac-Lautsprecher, dann zeigt die Anzeige das Pegel-Symbol.
    @Published var outputSymbol: String? = nil
    @Published var outputName = ""
    var onExternalChange: (() -> Void)?

    fileprivate var deviceID: AudioDeviceID { device }
    private var device = AudioDeviceID(kAudioObjectUnknown)
    private var deviceBlocks: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    private var systemBlock: AudioObjectPropertyListenerBlock?
    private var started = false
    private var selfChangeUntil = Date.distantPast

    private static let virtualMainVolume = AudioObjectPropertySelector(0x766D7663) // 'vmvc'

    private static func address(_ sel: AudioObjectPropertySelector,
                                scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeOutput,
                                element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: sel, mScope: scope, mElement: element)
    }

    func start() {
        guard !started else { return }
        started = true
        attachDevice()
        var addr = Self.address(kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.attachDevice() }
        systemBlock = block
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, .main, block)
    }

    func stop() {
        guard started else { return }
        started = false
        detachDevice()
        if let b = systemBlock {
            var addr = Self.address(kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal)
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, .main, b)
        }
        systemBlock = nil
    }

    private func detachDevice() {
        for (var addr, block) in deviceBlocks {
            AudioObjectRemovePropertyListenerBlock(device, &addr, .main, block)
        }
        deviceBlocks.removeAll()
    }

    private func attachDevice() {
        detachDevice()
        var id = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = Self.address(kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id) == noErr else { return }
        device = id
        readState()
        for sel in [Self.virtualMainVolume, kAudioDevicePropertyMute, kAudioDevicePropertyDataSource] {
            var a = Self.address(sel)
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                guard let self else { return }
                self.readState()
                if Date() > self.selfChangeUntil { self.onExternalChange?() }
            }
            if AudioObjectAddPropertyListenerBlock(device, &a, .main, block) == noErr {
                deviceBlocks.append((a, block))
            }
        }
    }

    private func readState() {
        readOutputKind()
        var v = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        var a = Self.address(Self.virtualMainVolume)
        if AudioObjectGetPropertyData(device, &a, 0, nil, &size, &v) == noErr { volume = v }
        var m = UInt32(0)
        var msize = UInt32(MemoryLayout<UInt32>.size)
        var ma = Self.address(kAudioDevicePropertyMute)
        if AudioObjectGetPropertyData(device, &ma, 0, nil, &msize, &m) == noErr { muted = m != 0 }
    }

    func setVolume(_ value: Float) {
        selfChangeUntil = Date().addingTimeInterval(0.3)
        var v = min(1, max(0, value))
        var a = Self.address(Self.virtualMainVolume)
        AudioObjectSetPropertyData(device, &a, 0, nil, UInt32(MemoryLayout<Float32>.size), &v)
        if v > 0 && muted { setMute(false) }
        volume = v
    }

    func adjust(_ delta: Float) { setVolume(volume + delta) }

    func setMute(_ on: Bool) {
        selfChangeUntil = Date().addingTimeInterval(0.3)
        var m: UInt32 = on ? 1 : 0
        var a = Self.address(kAudioDevicePropertyMute)
        AudioObjectSetPropertyData(device, &a, 0, nil, UInt32(MemoryLayout<UInt32>.size), &m)
        muted = on
    }

    func toggleMute() { setMute(!muted) }
}

// MARK: Ausgabegerät erkennen

extension AudioControl {
    private static func fourCC(_ s: String) -> UInt32 {
        s.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
    }

    fileprivate func readOutputKind() {
        var nameRef: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var na = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName,
                                            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var name = ""
        if AudioObjectGetPropertyData(deviceID, &na, 0, nil, &size, &nameRef) == noErr, let r = nameRef {
            name = r.takeRetainedValue() as String
        }
        func u32(_ sel: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope) -> UInt32 {
            var v = UInt32(0)
            var sz = UInt32(MemoryLayout<UInt32>.size)
            var a = AudioObjectPropertyAddress(mSelector: sel, mScope: scope, mElement: kAudioObjectPropertyElementMain)
            return AudioObjectGetPropertyData(deviceID, &a, 0, nil, &sz, &v) == noErr ? v : 0
        }
        let transport = u32(kAudioDevicePropertyTransportType, kAudioObjectPropertyScopeGlobal)
        let source = u32(kAudioDevicePropertyDataSource, kAudioObjectPropertyScopeOutput)
        outputName = name
        outputSymbol = Self.symbol(name: name, transport: transport, source: source)
    }

    /// Wählt das passende Symbol anhand von Gerätename, Anschlussart und Datenquelle.
    static func symbol(name: String, transport: UInt32, source: UInt32) -> String? {
        let n = name.lowercased()
        let has: ([String]) -> Bool = { $0.contains { n.contains($0) } }
        let bluetooth = transport == fourCC("blue") || transport == fourCC("blea")

        var candidate: String?
        if n.contains("airpods") {
            if n.contains("max") { candidate = "airpodsmax" }
            else if n.contains("pro") { candidate = "airpodspro" }
            else if has(["4th", "gen4", "gen 4", "4. gen"]) { candidate = "airpods.gen4" }
            else if has(["3rd", "gen3", "gen 3", "3. gen"]) { candidate = "airpods.gen3" }
            else { candidate = "airpods" }
        } else if n.contains("homepod") {
            candidate = n.contains("mini") ? "homepodmini.fill" : "homepod.fill"
        } else if has(["beats"]) {
            candidate = "beats.headphones"
        } else if transport == fourCC("airp") {
            candidate = "airplayaudio"
        } else if transport == fourCC("hdmi") || transport == fourCC("dprt") {
            candidate = "display"
        } else if transport == fourCC("bltn") {
            candidate = source == fourCC("hdpn") ? "headphones" : nil   // Kopfhörerbuchse
        } else if has(["headphone", "headset", "kopfh", "earbuds", "buds", "earphone"]) {
            candidate = "headphones"
        } else if has(["speaker", "lautsprecher", "soundbar", "boom", "jbl", "sonos", "echo", "bose"]) {
            candidate = "hifispeaker.fill"
        } else if bluetooth {
            candidate = "headphones"     // unbekanntes Bluetooth-Audio: meist Kopfhörer
        }
        guard let c = candidate else { return nil }
        return NSImage(systemSymbolName: c, accessibilityDescription: nil) != nil ? c : "headphones"
    }
}
