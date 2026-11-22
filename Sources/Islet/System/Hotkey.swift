import Carbon.HIToolbox

/// Globaler Tastenkürzel zum Öffnen/Schließen der Insel (Carbon, braucht keine Berechtigung).
final class Hotkey {
    static let shared = Hotkey()
    var onPress: (() -> Void)?

    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var current = ""

    static let options: [(id: String, label: String)] = [
        ("off", "Aus"), ("ctrlOptSpace", "⌃⌥ Leertaste"), ("cmdOptI", "⌘⌥ I"), ("ctrlOptI", "⌃⌥ I"),
    ]

    func apply(_ id: String) {
        guard id != current else { return }
        current = id
        if let r = ref { UnregisterEventHotKey(r); ref = nil }
        let combo: (UInt32, UInt32)?
        switch id {
        case "ctrlOptSpace": combo = (UInt32(kVK_Space), UInt32(controlKey | optionKey))
        case "cmdOptI": combo = (UInt32(kVK_ANSI_I), UInt32(cmdKey | optionKey))
        case "ctrlOptI": combo = (UInt32(kVK_ANSI_I), UInt32(controlKey | optionKey))
        default: combo = nil
        }
        guard let (key, mods) = combo else { return }
        installHandlerOnce()
        var hk: EventHotKeyRef?
        let hid = EventHotKeyID(signature: OSType(0x49534C54), id: 1)  // 'ISLT'
        if RegisterEventHotKey(key, mods, hid, GetApplicationEventTarget(), 0, &hk) == noErr { ref = hk }
    }

    private func installHandlerOnce() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { Hotkey.shared.onPress?() }
            return noErr
        }, 1, &spec, nil, &handler)
    }
}
