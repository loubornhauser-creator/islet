import AppKit
import SwiftUI

/// Welche Seite die Einstellungen zeigen.
enum SettingsPage: String, CaseIterable, Identifiable {
    case general, modules, appearance, tools, calendarDevices, face, volume, actions, permissions, about
    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "Allgemein"
        case .modules: return "Module"
        case .appearance: return "Aussehen"
        case .tools: return "Koffein & Timer"
        case .calendarDevices: return "Kalender & Geräte"
        case .face: return "Face Unlock"
        case .volume: return "Lautstärke & Gesten"
        case .actions: return "Aktionen"
        case .permissions: return "Berechtigungen"
        case .about: return "Über Islet"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape.fill"
        case .modules: return "square.grid.2x2.fill"
        case .appearance: return "paintpalette.fill"
        case .tools: return "cup.and.saucer.fill"
        case .calendarDevices: return "calendar"
        case .face: return "faceid"
        case .volume: return "speaker.wave.2.fill"
        case .actions: return "bolt.fill"
        case .permissions: return "hand.raised.fill"
        case .about: return "info.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .general: return .gray
        case .modules: return .indigo
        case .appearance: return .pink
        case .tools: return .orange
        case .calendarDevices: return .red
        case .face: return .green
        case .volume: return .blue
        case .actions: return .yellow
        case .permissions: return .green
        case .about: return .teal
        }
    }
}

final class SettingsNav: ObservableObject {
    static let shared = SettingsNav()
    @Published var page: SettingsPage = .general
}

/// Das eine Einstellungsfenster. Wird aus Menüleiste, Zahnrad und Übersicht geöffnet
/// und beim Schließen komplett freigegeben (spart Arbeitsspeicher).
final class SettingsWindow: NSObject, NSWindowDelegate {
    private static let shared = SettingsWindow()
    private var window: NSWindow?

    static func show(page: SettingsPage? = nil) {
        if let page { SettingsNav.shared.page = page }
        shared.present()
    }

    private func present() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 600),
                             styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.titleVisibility = .hidden
            w.titlebarAppearsTransparent = true
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.contentView = NSHostingView(rootView: SettingsView())
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window?.contentView = nil
        window?.delegate = nil
        window = nil
    }
}
