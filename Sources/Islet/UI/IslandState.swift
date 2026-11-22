import SwiftUI
import AppKit

/// Geometrie des Bildschirms (Notch-Breite und -Höhe).
final class IslandGeometry: ObservableObject {
    static let shared = IslandGeometry()
    @Published var notchWidth: CGFloat = 0
    @Published var notchHeight: CGFloat = 32

    static let pillBase: CGFloat = 132   // Breite auf Macs ohne Notch

    var baseWidth: CGFloat { notchWidth > 0 ? notchWidth : Self.pillBase }

    func update(for screen: NSScreen) {
        if screen.safeAreaInsets.top > 0,
           let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea {
            notchWidth = screen.frame.width - l.width - r.width
            notchHeight = screen.safeAreaInsets.top
        } else {
            notchWidth = 0
            notchHeight = 30
        }
    }
}

final class IslandState: ObservableObject {
    static let shared = IslandState()

    @Published var expanded = false
    private var pinned = false
    private var work: DispatchWorkItem?

    func hover(_ inside: Bool) {
        work?.cancel()
        if inside {
            guard Pref.bool("hoverExpand"), !expanded else { return }
            schedule(after: Pref.double("hoverDelay")) { self.set(true) }
        } else if expanded && !pinned {
            schedule(after: 0.28) { self.set(false) }
        }
    }

    func toggle() {
        work?.cancel()
        pinned = !expanded
        set(!expanded)
    }

    /// Kurz aufklappen (z. B. wenn der Timer abläuft).
    func peek() {
        work?.cancel()
        set(true)
        schedule(after: 3.5) { if !self.pinned { self.set(false) } }
    }

    private func schedule(after delay: TimeInterval, _ block: @escaping () -> Void) {
        let w = DispatchWorkItem(block: block)
        work = w
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: w)
    }

    private func set(_ value: Bool) {
        if !value { pinned = false }
        guard expanded != value else { return }
        expanded = value
        Caffeine.shared.setFast(value)
    }
}

/// Liquid Glass ab macOS 26, sonst Material. `strength` mischt das dunkle Tint dazu.
struct GlassBackground<S: Shape>: ViewModifier {
    var shape: S
    var strength: Double = 0.5
    var tint: Color = .black
    var interactive = false

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(interactive ? .regular.tint(tint.opacity(strength)).interactive()
                                            : .regular.tint(tint.opacity(strength)), in: shape)
        } else {
            content.background(.ultraThinMaterial, in: shape)
                .background(tint.opacity(strength), in: shape)
        }
    }
}
