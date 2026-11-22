import AppKit
import SwiftUI

/// Das eine Einstellungsfenster. Wird aus Menüleiste und aus dem Zahnrad der Insel geöffnet.
enum SettingsWindow {
    private static var window: NSWindow?

    static func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 544, height: 484),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "Islet Einstellungen"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: SettingsView())
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
