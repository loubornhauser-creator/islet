import AppKit
import ApplicationServices

/// Ein einziger CGEventTap für Medientasten (Lautstärke/Helligkeit) und das Unterdrücken
/// von Scroll-Events während einer Rand-Geste. Braucht die Bedienungshilfen-Freigabe.
final class InputTap {
    static let shared = InputTap()

    /// key: 0 Lauter, 1 Leiser, 2 Heller, 3 Dunkler, 7 Stumm. Rückgabe true = Event verschlucken.
    var onMediaKey: ((_ key: Int, _ flags: NSEvent.ModifierFlags) -> Bool)?
    var suppressScroll = false

    fileprivate(set) var tap: CFMachPort?
    private var source: CFRunLoopSource?

    static var trusted: Bool { AXIsProcessTrusted() }

    /// Wird aufgerufen, wenn die Freigabe nachträglich erteilt wurde: startet die Abfangung ohne Neustart.
    static func startIfNeeded() {
        guard trusted, shared.tap == nil, shared.onMediaKey != nil || Pref.bool("modGestures") else { return }
        shared.start()
    }

    static func requestPermission() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    @discardableResult
    func start() -> Bool {
        if tap != nil { return true }
        guard Self.trusted else { return false }
        let mask = CGEventMask(1 << 14) | CGEventMask(1 << CGEventType.scrollWheel.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, _ in
            let me = InputTap.shared
            switch type {
            case .tapDisabledByTimeout, .tapDisabledByUserInput:
                if let t = me.tap { CGEvent.tapEnable(tap: t, enable: true) }
                return Unmanaged.passUnretained(event)
            case .scrollWheel:
                return me.suppressScroll ? nil : Unmanaged.passUnretained(event)
            default:
                guard type.rawValue == 14, let ns = NSEvent(cgEvent: event), ns.subtype.rawValue == 8 else {
                    return Unmanaged.passUnretained(event)
                }
                let code = (ns.data1 & 0xFFFF0000) >> 16
                let down = ((ns.data1 & 0xFF00) >> 8) == 0xA
                guard [0, 1, 2, 3, 7].contains(code) else { return Unmanaged.passUnretained(event) }
                if down, let h = me.onMediaKey, h(code, ns.modifierFlags) { return nil }
                // Key-up der verschluckten Tasten ebenfalls verschlucken.
                return (!down && me.onMediaKey != nil && me.consumesKeys) ? nil : Unmanaged.passUnretained(event)
            }
        }
        guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                        options: .defaultTap, eventsOfInterest: mask,
                                        callback: callback, userInfo: nil) else { return false }
        tap = t
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, t, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
        return true
    }

    var consumesKeys = false

    func stop() {
        if let t = tap { CGEvent.tapEnable(tap: t, enable: false) }
        if let s = source { CFRunLoopRemoveSource(CFRunLoopGetMain(), s, .commonModes) }
        tap = nil; source = nil
    }
}
