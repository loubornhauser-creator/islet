import SwiftUI
import AppKit
import Combine

final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class IslandHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Hält das eine Insel-Fenster. Im Ruhezustand ist es nur so groß wie die kompakte Insel,
/// damit darunterliegende Fenster klickbar bleiben.
final class IslandController {
    private let panel: IslandPanel
    private var cancellables = Set<AnyCancellable>()
    private var shrinkWork: DispatchWorkItem?
    private var lastDisplayPref = ""

    init() {
        panel = IslandPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isMovable = false
        panel.animationBehavior = .none
        panel.contentView = IslandHostingView(rootView: IslandView())

        IslandState.shared.$expanded.sink { [weak self] _ in
            DispatchQueue.main.async { self?.layout() }
        }.store(in: &cancellables)
        IslandState.shared.$compactWidth.removeDuplicates().sink { [weak self] _ in
            DispatchQueue.main.async { self?.layout() }
        }.store(in: &cancellables)

        IslandState.shared.prepareWindow = { [weak self] in self?.layout(immediate: true, forceExpanded: true) }

        let nc = NotificationCenter.default
        nc.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.reposition()
        }
        nc.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            let d = Pref.string("display")
            if d != self.lastDisplayPref { self.lastDisplayPref = d; self.reposition() } else { self.layout() }
            self.updateVisibility()
        }
        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                // Kurz warten, bis der Vollbild-Wechsel abgeschlossen ist.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self?.updateVisibility() }
            }
        }
        lastDisplayPref = Pref.string("display")
        reposition()
        panel.orderFrontRegardless()
    }

    private var targetScreen: NSScreen {
        switch Pref.string("display") {
        case "main":
            return NSScreen.screens.first ?? NSScreen.main!
        case "mouse":
            let m = NSEvent.mouseLocation
            return NSScreen.screens.first { $0.frame.contains(m) } ?? NSScreen.main ?? NSScreen.screens[0]
        default:
            return NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens[0]
        }
    }

    func reposition() {
        IslandGeometry.shared.update(for: targetScreen)
        layout(immediate: true)
    }

    // MARK: Vollbild

    private func updateVisibility() {
        let hide = Pref.bool("hideInFullscreen") && Self.fullscreenAppActive(on: targetScreen)
        if hide, panel.isVisible { panel.orderOut(nil) }
        else if !hide, !panel.isVisible { panel.orderFrontRegardless() }
    }

    /// Eine App im Vollbild: ein normales Fenster (Ebene 0), das den ganzen Bildschirm deckt.
    private static func fullscreenAppActive(on screen: NSScreen) -> Bool {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return false }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        // CG-Koordinaten haben den Ursprung oben links.
        let rect = CGRect(x: screen.frame.minX, y: primaryHeight - screen.frame.maxY, width: screen.frame.width, height: screen.frame.height)
        let me = ProcessInfo.processInfo.processIdentifier
        for w in list {
            guard (w[kCGWindowLayer as String] as? Int) == 0,
                  (w[kCGWindowOwnerPID as String] as? Int32) != me,
                  let b = w[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = b["X"], let y = b["Y"], let wd = b["Width"], let ht = b["Height"] else { continue }
            if abs(x - rect.minX) < 1, abs(y - rect.minY) < 1, abs(wd - rect.width) < 1, abs(ht - rect.height) < 1 { return true }
        }
        return false
    }

    // MARK: Layout

    private func layout(immediate: Bool = false, forceExpanded: Bool = false) {
        shrinkWork?.cancel()
        let screen = targetScreen
        let geo = IslandGeometry.shared
        let expanded = forceExpanded || IslandState.shared.expanded || IslandState.shared.target
        let w: CGFloat, h: CGFloat
        if expanded {
            w = geo.expandedWidth + 24
            h = geo.expandedHeight + 16
        } else {
            // Geschlossen: exakt die Notch (oder, nur auf Wunsch, mit Live-Anzeigen daneben).
            // So bleiben alle Menüleisten-Symbole neben der Notch klickbar.
            w = max(geo.baseWidth, IslandState.shared.compactWidth)
            h = geo.notchHeight
        }
        let frame = NSRect(x: screen.frame.midX - w / 2, y: screen.frame.maxY - h, width: w, height: h)
        guard frame != panel.frame else { return }
        if expanded || immediate || frame.width > panel.frame.width {
            panel.setFrame(frame, display: true)
        } else {
            // Erst nach der Zuklapp-Animation verkleinern.
            let work = DispatchWorkItem { [weak self] in self?.panel.setFrame(frame, display: true) }
            shrinkWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
        }
    }
}
