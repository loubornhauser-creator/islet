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

    init() {
        panel = IslandPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isMovable = false
        panel.contentView = IslandHostingView(rootView: IslandView())

        IslandState.shared.$expanded.sink { [weak self] _ in
            DispatchQueue.main.async { self?.layout() }
        }.store(in: &cancellables)

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.reposition()
        }
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.layout()
        }
        reposition()
        panel.orderFrontRegardless()
    }

    private var targetScreen: NSScreen {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    func reposition() {
        IslandGeometry.shared.update(for: targetScreen)
        layout(immediate: true)
    }

    private func layout(immediate: Bool = false) {
        shrinkWork?.cancel()
        let screen = targetScreen
        let geo = IslandGeometry.shared
        let expanded = IslandState.shared.expanded
        let w: CGFloat, h: CGFloat
        if expanded {
            w = CGFloat(Pref.double("expandedWidth")) + 24
            h = CGFloat(Pref.double("expandedHeight")) + 16
        } else {
            w = max(geo.baseWidth + 220, 360)
            h = geo.notchHeight + 10
        }
        let frame = NSRect(x: screen.frame.midX - w / 2, y: screen.frame.maxY - h, width: w, height: h)
        if expanded || immediate {
            panel.setFrame(frame, display: true)
        } else {
            // Erst nach der Zuklapp-Animation verkleinern.
            let work = DispatchWorkItem { [weak self] in self?.panel.setFrame(frame, display: true) }
            shrinkWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
        }
    }
}
