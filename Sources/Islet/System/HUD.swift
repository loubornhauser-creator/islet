import SwiftUI
import AppKit

/// Senkrechte Seiten-Bar wie auf iPhone/iPad für Lautstärke und Helligkeit.
final class HUDState: ObservableObject {
    enum Kind { case volume, brightness }
    @Published var kind: Kind = .volume
    @Published var value: Double = 0
    @Published var muted = false
    @Published var visible = false
}

final class HUDController {
    static let shared = HUDController()
    let state = HUDState()
    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?
    private let size = NSSize(width: 74, height: 232)

    func show(_ kind: HUDState.Kind, value: Double, muted: Bool = false) {
        guard Pref.bool("modHUD") else { return }
        let p = panel ?? makePanel()
        place(p)
        state.kind = kind
        state.value = value
        state.muted = muted
        if !state.visible {
            p.orderFrontRegardless()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { state.visible = true }
        }
        hideWork?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.hide() }
        hideWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0.6, Pref.double("hudSeconds")), execute: w)
    }

    private func hide() {
        withAnimation(.easeIn(duration: 0.22)) { state.visible = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, !self.state.visible else { return }
            self.panel?.orderOut(nil)
        }
    }

    private func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 2)
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        p.ignoresMouseEvents = true
        p.contentView = NSHostingView(rootView: HUDView(state: state))
        panel = p
        return p
    }

    private func place(_ p: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens[0]
        let margin: CGFloat = 10
        let x = Pref.string("hudSide") == "left"
            ? screen.frame.minX + margin
            : screen.frame.maxX - size.width - margin
        p.setFrame(NSRect(x: x, y: screen.frame.midY - size.height / 2, width: size.width, height: size.height), display: false)
    }
}

struct HUDView: View {
    @ObservedObject var state: HUDState
    @AppStorage("accentHex") private var accentHex = "#0A84FF"
    @AppStorage("hudSide") private var side = "right"

    private var icon: String {
        switch state.kind {
        case .brightness: return state.value < 0.5 ? "sun.min.fill" : "sun.max.fill"
        case .volume:
            if state.muted || state.value <= 0 { return "speaker.slash.fill" }
            return state.value < 0.34 ? "speaker.wave.1.fill" : (state.value < 0.67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill")
        }
    }

    var body: some View {
        let shape = Capsule(style: .continuous)
        VStack(spacing: 0) {
            GeometryReader { g in
                ZStack(alignment: .bottom) {
                    Color.white.opacity(0.14)
                    Color(hex: accentHex)
                        .frame(height: g.size.height * (state.muted && state.kind == .volume ? 0 : state.value))
                        .animation(.spring(response: 0.25, dampingFraction: 0.85), value: state.value)
                }
            }
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(height: 44)
                .contentTransition(.symbolEffect(.replace))
        }
        .frame(width: 56, height: 216)
        .clipShape(shape)
        .modifier(GlassBackground(shape: shape, strength: 0.3))
        .scaleEffect(state.visible ? 1 : 0.8, anchor: side == "left" ? .leading : .trailing)
        .opacity(state.visible ? 1 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
