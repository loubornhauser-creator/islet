import CoreAudio
import Foundation

/// Systemlautstärke über CoreAudio, ereignisgesteuert (Listener statt Polling).
final class AudioControl: ObservableObject {
    static let shared = AudioControl()

    @Published var volume: Float = 0
    @Published var muted = false
    var onExternalChange: (() -> Void)?

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
        for sel in [Self.virtualMainVolume, kAudioDevicePropertyMute] {
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
