import CoreAudio
import CoreMediaIO
import Foundation

/// Zeigt, ob Mikrofon oder Kamera gerade benutzt werden (wie die orangen/grünen Punkte auf dem iPhone).
/// Ereignisgesteuert über Property-Listener, kein Polling, keine Berechtigung nötig.
final class Indicators: ObservableObject {
    static let shared = Indicators()

    @Published var micActive = false
    @Published var camActive = false

    private var started = false
    private var audioBlocks: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    private var camBlocks: [(CMIOObjectID, CMIOObjectPropertyAddress, CMIOObjectPropertyListenerBlock)] = []

    func start() {
        guard !started else { return }
        started = true
        attachAudio()
        attachCamera()
        refresh()
    }

    func stop() {
        guard started else { return }
        started = false
        for (id, var a, b) in audioBlocks { AudioObjectRemovePropertyListenerBlock(id, &a, .main, b) }
        for (id, var a, b) in camBlocks { CMIOObjectRemovePropertyListenerBlock(id, &a, .main, b) }
        audioBlocks.removeAll(); camBlocks.removeAll()
        micActive = false; camActive = false
    }

    // MARK: Mikrofon

    private func attachAudio() {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr else { return }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr else { return }
        for id in ids where hasInput(id) {
            var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                                               mScope: kAudioObjectPropertyScopeGlobal,
                                               mElement: kAudioObjectPropertyElementMain)
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.refresh() }
            if AudioObjectAddPropertyListenerBlock(id, &a, .main, block) == noErr { audioBlocks.append((id, a, block)) }
        }
    }

    private func hasInput(_ id: AudioDeviceID) -> Bool {
        var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams,
                                           mScope: kAudioObjectPropertyScopeInput,
                                           mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &a, 0, nil, &size) == noErr && size > 0
    }

    private func micRunning() -> Bool {
        for (id, var a, _) in audioBlocks {
            var v: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            if AudioObjectGetPropertyData(id, &a, 0, nil, &size, &v) == noErr, v != 0 { return true }
        }
        return false
    }

    // MARK: Kamera

    private func attachCamera() {
        var addr = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
                                             mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                             mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(CMIOObjectID(kCMIOObjectSystemObject), &addr, 0, nil, &size) == 0, size > 0 else { return }
        var ids = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &addr, 0, nil, size, &used, &ids) == 0 else { return }
        for id in ids {
            var a = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                                              mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                              mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
            let block: CMIOObjectPropertyListenerBlock = { [weak self] _, _ in self?.refresh() }
            if CMIOObjectAddPropertyListenerBlock(id, &a, .main, block) == 0 { camBlocks.append((id, a, block)) }
        }
    }

    private func camRunning() -> Bool {
        for (id, var a, _) in camBlocks {
            var v: UInt32 = 0
            var used: UInt32 = 0
            if CMIOObjectGetPropertyData(id, &a, 0, nil, UInt32(MemoryLayout<UInt32>.size), &used, &v) == 0, v != 0 { return true }
        }
        return false
    }

    private func refresh() {
        let m = micRunning(), c = camRunning()
        if m != micActive { micActive = m }
        if c != camActive { camActive = c }
    }
}
