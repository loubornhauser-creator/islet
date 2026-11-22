import SwiftUI
import AppKit

/// Zeigt den Gesichts-Scan in der Notch: Die Hülle wächst aus der Notch, „Suche dein Gesicht …“, dann das grüne Zeichen.
final class ScanState: ObservableObject {
    enum Kind: Equatable { case searching, recognized, recognizedDry, unlocking, denied, error(String) }
    @Published var kind: Kind = .searching
    @Published var visible = false
}

final class FaceScanIsland {
    static let shared = FaceScanIsland()
    let state = ScanState()
    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?

    func show(_ kind: ScanState.Kind, locked: Bool) {
        guard Pref.bool("faceShowIsland") else { return }
        hideWork?.cancel()
        let p = panel ?? makePanel()
        place(p)
        p.orderFrontRegardless()
        if locked && Pref.bool("faceLockScreenOverlay") { LockScreenSpace.place(window: p) }
        state.kind = kind
        if !state.visible { withAnimation(IslandMotion.open) { state.visible = true } }
        switch kind {
        case .searching, .unlocking: break
        default: scheduleHide(after: 1.8)
        }
    }

    func hide() { scheduleHide(after: 0) }

    private func scheduleHide(after delay: TimeInterval) {
        hideWork?.cancel()
        let w = DispatchWorkItem { [weak self] in
            withAnimation(IslandMotion.close) { self?.state.visible = false }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                guard let self, !self.state.visible else { return }
                self.panel?.orderOut(nil)
            }
        }
        hideWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: w)
    }

    private func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 130), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        p.ignoresMouseEvents = true
        p.animationBehavior = .none
        p.contentView = NSHostingView(rootView: FaceScanView(state: state))
        panel = p
        return p
    }

    private func place(_ p: NSPanel) {
        let screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens[0]
        let size = p.frame.size
        p.setFrame(NSRect(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height, width: size.width, height: size.height), display: false)
    }
}

struct FaceScanView: View {
    @ObservedObject var state: ScanState
    @ObservedObject private var geo = IslandGeometry.shared
    @AppStorage("activeHex") private var activeHex = "#30D158"
    @AppStorage("tintHex") private var tintHex = "#000000"

    private var green: Color { Color(hex: activeHex) }

    var body: some View {
        let open = state.visible
        let w: CGFloat = open ? 290 : geo.baseWidth
        let h: CGFloat = open ? geo.notchHeight + 64 : geo.notchHeight
        ZStack(alignment: .top) {
            NotchShape(top: 8, bottom: open ? 28 : 14).fill(Color.black)
            VStack(spacing: 0) {
                Spacer().frame(height: geo.notchHeight + 6)
                HStack(spacing: 12) {
                    icon.frame(width: 34, height: 34)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                        if let sub = subtitle { Text(sub).font(.system(size: 11)).foregroundStyle(.white.opacity(0.55)) }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 24)
                .opacity(open ? 1 : 0)
                .blur(radius: open ? 0 : 8)
                .animation(.easeOut(duration: 0.22).delay(open ? 0.1 : 0), value: open)
            }
        }
        .frame(width: w, height: h, alignment: .top)
        .clipShape(NotchShape(top: 8, bottom: open ? 28 : 14))
        .animation(open ? IslandMotion.open : IslandMotion.close, value: open)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder private var icon: some View {
        switch state.kind {
        case .searching:
            ScanBrackets().stroke(.white.opacity(0.9), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .overlay(Image(systemName: "faceid").font(.system(size: 18, weight: .light)).foregroundStyle(.white.opacity(0.9))
                    .symbolEffect(.pulse, options: .repeating))
        case .recognized, .recognizedDry:
            Image(systemName: "faceid").font(.system(size: 28, weight: .regular)).foregroundStyle(green)
                .contentTransition(.symbolEffect(.replace))
        case .unlocking:
            Image(systemName: "lock.open.fill").font(.system(size: 24)).foregroundStyle(green)
        case .denied:
            Image(systemName: "xmark.circle").font(.system(size: 26)).foregroundStyle(.red)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 22)).foregroundStyle(.orange)
        }
    }

    private var title: String {
        switch state.kind {
        case .searching: return "Suche dein Gesicht …"
        case .recognized: return "Gesicht erkannt"
        case .recognizedDry: return "Gesicht erkannt"
        case .unlocking: return "Entsperre …"
        case .denied: return "Nicht erkannt"
        case .error: return "Face Unlock"
        }
    }

    private var subtitle: String? {
        switch state.kind {
        case .recognizedDry: return "Probelauf, nichts getippt"
        case .error(let m): return m
        case .denied: return "Passwort von Hand eingeben"
        default: return nil
        }
    }
}

/// Vier Ecken wie beim Face-ID-Rahmen.
struct ScanBrackets: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let l = r.width * 0.28, c = r.width * 0.12
        for (x, y, dx, dy) in [(r.minX, r.minY, 1.0, 1.0), (r.maxX, r.minY, -1.0, 1.0), (r.minX, r.maxY, 1.0, -1.0), (r.maxX, r.maxY, -1.0, -1.0)] {
            p.move(to: CGPoint(x: x, y: y + dy * l))
            p.addLine(to: CGPoint(x: x, y: y + dy * c))
            p.addQuadCurve(to: CGPoint(x: x + dx * c, y: y), control: CGPoint(x: x, y: y))
            p.addLine(to: CGPoint(x: x + dx * l, y: y))
        }
        return p
    }
}
