import SwiftUI
import AppKit

/// Geometrie des Bildschirms (Notch-Breite und -Höhe).
final class IslandGeometry: ObservableObject {
    static let shared = IslandGeometry()
    @Published var notchWidth: CGFloat = 0
    @Published var notchHeight: CGFloat = 32

    static let pillBase: CGFloat = 132   // Breite auf Macs ohne Notch

    var baseWidth: CGFloat { notchWidth > 0 ? notchWidth : Self.pillBase }

    /// Mindestbreite der geöffneten Insel: Links und rechts der Notch muss Platz für die Reiter bleiben,
    /// damit die echte Notch nie in die Bedienelemente hineinragt (3 Reiter links, 3 Reiter + Zahnrad rechts).
    var minExpandedWidth: CGFloat { notchWidth > 0 ? notchWidth + 350 : 480 }
    /// Mindesthöhe: Notch-Leiste plus Platz für die Übersicht mit zwei Kachelreihen.
    var minExpandedHeight: CGFloat { notchHeight + 182 }

    /// Die tatsächlich verwendete Größe: Einstellung, aber nie kleiner als die Mindestmaße.
    var expandedWidth: CGFloat { max(CGFloat(Pref.double("expandedWidth")), minExpandedWidth) }
    var expandedHeight: CGFloat { max(CGFloat(Pref.double("expandedHeight")), minExpandedHeight) }

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

/// Ansichten der geöffneten Insel (Leiste oben, wie bei Atoll).
enum IslandTab: String, CaseIterable, Identifiable {
    case music, overview, calendar, devices, claude, clipboard, actions
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .music: return "music.note"
        case .overview: return "square.grid.2x2.fill"
        case .calendar: return "calendar"
        case .devices: return "headphones"
        case .claude: return "sparkles"
        case .clipboard: return "doc.on.clipboard.fill"
        case .actions: return "bolt.fill"
        }
    }
    var title: String {
        switch self {
        case .music: return "Musik"
        case .overview: return "Übersicht"
        case .calendar: return "Kalender"
        case .devices: return "Geräte"
        case .claude: return "Claude-Limits"
        case .clipboard: return "Zwischenablage"
        case .actions: return "Aktionen"
        }
    }
}

/// Wie die Insel auf- und zuklappt. Hülle (Größe) und Inhalt (Einblenden) laufen getrennt, damit sie
/// wie bei der iPhone-Insel erst als Notch-Form wächst und der Inhalt danach von oben nach unten erscheint.
enum IslandMotion {
    static var style: String { Pref.string("animStyle") }

    static var open: Animation {
        switch style {
        case "smooth": return .spring(response: 0.52, dampingFraction: 1.0)
        case "quick": return .spring(response: 0.28, dampingFraction: 0.92)
        default: return .spring(response: 0.46, dampingFraction: 0.82)
        }
    }
    static var close: Animation {
        switch style {
        case "smooth": return .spring(response: 0.42, dampingFraction: 1.0)
        case "quick": return .spring(response: 0.24, dampingFraction: 1.0)
        default: return .spring(response: 0.36, dampingFraction: 0.92)
        }
    }
    /// Pause, bis der Inhalt nach dem Start des Wachsens einblendet.
    static var contentDelay: TimeInterval {
        switch style {
        case "smooth": return 0.10
        case "quick": return 0.04
        default: return 0.11
        }
    }
    static let contentIn = Animation.easeOut(duration: 0.24)
    static let contentOut = Animation.easeIn(duration: 0.12)
}

final class IslandState: ObservableObject {
    static let shared = IslandState()

    /// Hülle ist aufgeklappt.
    @Published var expanded = false
    /// Inhalt ist eingeblendet (folgt der Hülle zeitversetzt).
    @Published var contentVisible = false
    @Published var tab: IslandTab = .music
    /// Breite der geschlossenen Insel (nur >Notch, wenn Live-Anzeigen neben der Notch an sind).
    @Published var compactWidth: CGFloat = 0
    private var pinned = false
    private var work: DispatchWorkItem?
    private var phaseWork: DispatchWorkItem?
    /// Gewünschter Zustand (die Hülle folgt zeitversetzt).
    private(set) var target = false
    /// Der Controller vergrößert hier das Fenster, bevor die Animation startet.
    var prepareWindow: (() -> Void)?

    func hover(_ inside: Bool) {
        work?.cancel()
        if inside {
            guard Pref.bool("hoverExpand"), !target else { return }
            schedule(after: Pref.double("hoverDelay")) { self.set(true) }
        } else if target && !pinned {
            schedule(after: Pref.double("collapseDelay")) { self.set(false) }
        }
    }

    /// Tastenkürzel: öffnet fest (bleibt offen) oder schließt.
    func hotkeyToggle() { toggle() }

    func toggle() {
        work?.cancel()
        pinned = !target
        set(!target)
    }

    /// Kurz aufklappen (z. B. wenn der Timer abläuft).
    func peek() {
        work?.cancel()
        set(true)
        schedule(after: 3.5) { if !self.pinned { self.set(false) } }
    }

    /// Für Test-Screenshots: sofort offen, ohne Animation.
    func openImmediately() { target = true; expanded = true; contentVisible = true }

    private func schedule(after delay: TimeInterval, _ block: @escaping () -> Void) {
        let w = DispatchWorkItem(block: block)
        work = w
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: w)
    }

    private func set(_ value: Bool) {
        if !value { pinned = false }
        guard value != target else { return }
        target = value
        phaseWork?.cancel()
        if value {
            switch Pref.string("startTab") {
            case "music": tab = .music
            case "overview": tab = .overview
            default: break
            }
            Haptics.tap()
            // 1. Fenster zuerst vergrößern, solange die Hülle noch Notch-groß ist. Passiert beides gleichzeitig,
            //    sitzt die Hülle für einen Moment am falschen Rand und wandert von unten nach oben.
            prepareWindow?()
            // 2. Kurz danach die Hülle aus der Notch heraus wachsen lassen, 3. dann den Inhalt einblenden.
            let w = DispatchWorkItem { [weak self] in
                guard let self, self.target else { return }
                self.expanded = true
                let c = DispatchWorkItem { [weak self] in
                    guard let self, self.target else { return }
                    self.contentVisible = true
                }
                self.phaseWork = c
                DispatchQueue.main.asyncAfter(deadline: .now() + IslandMotion.contentDelay, execute: c)
            }
            phaseWork = w
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: w)
        } else {
            // Erst Inhalt ausblenden, dann Hülle zur Notch zurückschrumpfen.
            contentVisible = false
            let w = DispatchWorkItem { [weak self] in
                guard let self, !self.target else { return }
                self.expanded = false
            }
            phaseWork = w
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.09, execute: w)
        }
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
