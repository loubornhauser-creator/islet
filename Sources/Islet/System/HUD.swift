import SwiftUI
import AppKit

/// Senkrechte Seiten-Pille für Lautstärke und Helligkeit (Look wie bei Atoll: schmale Glaskapsel,
/// Füllung steigt vom Boden, Symbol unten in der Füllung, Prozentwert oben).
final class HUDState: ObservableObject {
    enum Kind { case volume, brightness }
    @Published var kind: Kind = .volume
    @Published var value: Double = 0
    @Published var muted = false
    /// +1 / -1 bei jedem Tastendruck rauf/runter. Löst das elastische Dehnen aus.
    @Published var bump: (direction: Int, id: Int) = (0, 0)
}

final class HUDController {
    static let shared = HUDController()
    let state = HUDState()

    /// Maße der sichtbaren Pille.
    static let pillSize = NSSize(width: 38, height: 180)
    /// Rand ums Fenster, damit Schatten und Dehnung nicht abgeschnitten werden.
    private static let bleed: CGFloat = 60
    private static let edgeMargin: CGFloat = 24

    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?
    private var shown = false
    private var lastValue: Double?
    private var bumpID = 0

    func show(_ kind: HUDState.Kind, value: Double, muted: Bool = false) {
        guard Pref.bool("modHUD") else { return }
        let p = panel ?? makePanel()
        place(p)

        // Richtung der Änderung für die elastische Bewegung (nur innerhalb derselben Art).
        let direction: Int
        if let last = lastValue, kind == state.kind, shown { direction = value >= last ? 1 : -1 } else { direction = 0 }
        lastValue = value

        state.kind = kind
        state.muted = muted
        if !shown {
            // Erstes Erscheinen: Wert ohne Füllanimation setzen, dann einblenden.
            state.value = value
            p.alphaValue = 0
            p.orderFrontRegardless()
        } else {
            state.value = value
            if direction != 0 {
                bumpID += 1
                state.bump = (direction, bumpID)
            }
        }
        shown = true
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            p.animator().alphaValue = 1
        }

        hideWork?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.hide() }
        hideWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0.6, Pref.double("hudSeconds")), execute: w)
    }

    private func hide() {
        guard let p = panel else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            p.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, p.alphaValue < 0.01 else { return }
            p.orderOut(nil)
            self.shown = false
            self.lastValue = nil
        })
    }

    private var windowSize: NSSize {
        NSSize(width: Self.pillSize.width + Self.bleed * 2, height: Self.pillSize.height + Self.bleed * 2)
    }

    private func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: NSRect(origin: .zero, size: windowSize),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 2)
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        p.ignoresMouseEvents = true
        p.alphaValue = 0
        p.contentView = NSHostingView(rootView: HUDView(state: state))
        panel = p
        return p
    }

    private func place(_ p: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens[0]
        let size = windowSize
        let pillX = Pref.string("hudSide") == "left"
            ? screen.frame.minX + Self.edgeMargin
            : screen.frame.maxX - Self.pillSize.width - Self.edgeMargin
        p.setFrame(NSRect(x: pillX - Self.bleed, y: screen.frame.midY - size.height / 2,
                          width: size.width, height: size.height), display: false)
    }
}

struct HUDView: View {
    @ObservedObject var state: HUDState
    @AppStorage("accentHex") private var accentHex = "#0A84FF"

    @State private var stretch: CGFloat = 0
    @State private var stretchOffset: CGFloat = 0

    private let width = HUDController.pillSize.width
    private let height = HUDController.pillSize.height

    private var level: Double { state.muted && state.kind == .volume ? 0 : min(1, max(0, state.value)) }

    private var symbol: String {
        switch state.kind {
        case .brightness:
            return "sun.max.fill"
        case .volume:
            if level < 0.01 { return "speaker.slash.fill" }
            if level < 0.33 { return "speaker.wave.1.fill" }
            return level < 0.66 ? "speaker.wave.2.fill" : "speaker.wave.3.fill"
        }
    }

    var body: some View {
        ZStack {
            glass
                .clipShape(Capsule())
                .overlay { Capsule().stroke(.white.opacity(0.1), lineWidth: 1) }

            // Füllung wächst vom Boden nach oben und geht bis ganz unten durch.
            GeometryReader { g in
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    Rectangle()
                        .fill(LinearGradient(colors: [Color(hex: accentHex).opacity(0.92), Color(hex: accentHex)],
                                             startPoint: .top, endPoint: .bottom))
                        .frame(height: g.size.height * level)
                        .animation(.interactiveSpring(response: 0.55, dampingFraction: 0.85, blendDuration: 0.3), value: level)
                }
            }
            .clipShape(Capsule())

            VStack(spacing: 0) {
                Text("\(Int((level * 100).rounded()))")
                    .font(.system(size: 10, weight: .bold).monospacedDigit())
                    .foregroundStyle(level > 0.85 ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                    .contentTransition(.numericText(value: level))
                    .animation(.easeOut(duration: 0.15), value: level)
                    .padding(.top, 9)
                Spacer(minLength: 0)
                Image(systemName: symbol)
                    .font(.system(size: width * 0.4, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(level > 0.15 ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                    .contentTransition(.symbolEffect(.replace))
                    .padding(.bottom, width * 0.35)
            }
        }
        .frame(width: width, height: height + stretch)
        .offset(y: stretchOffset)
        .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: state.bump.id) { _, _ in elastic(direction: state.bump.direction) }
    }

    /// Kurzes Dehnen in Änderungsrichtung, dann federt die Pille zurück (wie das Gummiband bei Atoll).
    private func elastic(direction: Int) {
        withAnimation(.interactiveSpring(response: 0.35, dampingFraction: 0.6)) {
            stretch = 12
            stretchOffset = CGFloat(direction) * -6
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.65)) {
                stretch = 0
                stretchOffset = 0
            }
        }
    }

    @ViewBuilder
    private var glass: some View {
        if #available(macOS 26.0, *) {
            Capsule().fill(.clear).glassEffect(.clear, in: .capsule)
        } else {
            Capsule().fill(.ultraThinMaterial)
        }
    }
}
