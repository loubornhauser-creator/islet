import SwiftUI
import AppKit
import ApplicationServices

/// Reinigungsmodus: Tastatur (und auf Wunsch Trackpad) werden gesperrt, damit beim Abwischen nichts ausgelöst wird.
/// Ende automatisch nach der eingestellten Zeit oder jederzeit mit gedrückter Esc-Taste (3 Sekunden).
/// Braucht die Bedienungshilfen-Freigabe, weil die Ereignisse abgefangen werden.
final class CleaningLock: ObservableObject {
    static let shared = CleaningLock()

    @Published var active = false
    @Published var endDate: Date?
    @Published var escProgress: Double = 0

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var endTimer: Timer?
    private var escTimer: Timer?
    private var escDownAt: Date?
    private var overlay = CleaningOverlay()
    private(set) var blocksPointer = true

    static let holdSeconds = 3.0

    /// Gibt false zurück, wenn die Freigabe fehlt (dann wird sie angefragt).
    @discardableResult
    func start(seconds: TimeInterval? = nil) -> Bool {
        guard !active else { return true }
        guard InputTap.trusted else { InputTap.requestPermission(); return false }
        blocksPointer = Pref.bool("cleaningTrackpad")

        var types: [CGEventType] = [.keyDown, .keyUp, .flagsChanged]
        var mask: CGEventMask = 0
        for t in types { mask |= CGEventMask(1) << CGEventMask(t.rawValue) }
        mask |= CGEventMask(1) << 14                      // Systemtasten (Lautstärke, Helligkeit, Medien)
        if blocksPointer {
            types = [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp,
                     .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .scrollWheel]
            for t in types { mask |= CGEventMask(1) << CGEventMask(t.rawValue) }
            for raw: UInt32 in [18, 19, 20, 29, 30, 31, 32, 33] { mask |= CGEventMask(1) << CGEventMask(raw) }  // Gesten
        }

        let callback: CGEventTapCallBack = { _, type, event, _ in
            let me = CleaningLock.shared
            switch type {
            case .tapDisabledByTimeout, .tapDisabledByUserInput:
                if let t = me.tap { CGEvent.tapEnable(tap: t, enable: true) }
                return nil
            case .keyDown, .keyUp:
                if event.getIntegerValueField(.keyboardEventKeycode) == 53 {   // Esc
                    let down = type == .keyDown
                    DispatchQueue.main.async { me.escChanged(down: down) }
                }
                return nil
            default:
                return nil
            }
        }
        guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                        eventsOfInterest: mask, callback: callback, userInfo: nil) else { return false }
        tap = t
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, t, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)

        let duration = min(600, max(10, seconds ?? Double(Pref.int("cleaningMinutes")) * 60))
        let end = Date().addingTimeInterval(duration)
        endDate = end
        active = true
        endTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in self?.stop() }
        overlay.show()
        return true
    }

    func stop() {
        guard active else { return }
        if let t = tap { CGEvent.tapEnable(tap: t, enable: false) }
        if let s = source { CFRunLoopRemoveSource(CFRunLoopGetMain(), s, .commonModes) }
        tap = nil; source = nil
        endTimer?.invalidate(); endTimer = nil
        escTimer?.invalidate(); escTimer = nil
        escDownAt = nil; escProgress = 0
        active = false; endDate = nil
        overlay.hide()
    }

    // MARK: Esc 3 Sekunden halten

    private func escChanged(down: Bool) {
        if down {
            guard escDownAt == nil else { return }       // Wiederholungs-Ereignisse ignorieren
            escDownAt = Date()
            escTimer?.invalidate()
            escTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                guard let self, let t = self.escDownAt else { return }
                let p = Date().timeIntervalSince(t) / Self.holdSeconds
                self.escProgress = min(1, p)
                if p >= 1 { self.stop() }
            }
        } else {
            escDownAt = nil
            escTimer?.invalidate(); escTimer = nil
            escProgress = 0
        }
    }
}

/// Dunkles Overlay mit Restzeit, damit man den Bildschirm beim Putzen nicht versehentlich bedient.
final class CleaningOverlay {
    private var windows: [NSWindow] = []

    func show() {
        hide()
        let dim = Pref.bool("cleaningDim")
        let screens = dim ? NSScreen.screens : [NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens[0]]
        for s in screens {
            let frame = dim ? s.frame : NSRect(x: s.frame.midX - 190, y: s.frame.maxY - 150, width: 380, height: 130)
            let w = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
            w.isOpaque = false
            w.backgroundColor = .clear
            w.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) - 1)
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            w.ignoresMouseEvents = true
            w.animationBehavior = .none
            w.contentView = NSHostingView(rootView: CleaningView(dim: dim))
            w.setFrame(frame, display: true)
            w.orderFrontRegardless()
            windows.append(w)
        }
    }

    func hide() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
    }
}

struct CleaningView: View {
    let dim: Bool
    @ObservedObject private var lock = CleaningLock.shared
    @AppStorage("activeHex") private var activeHex = "#30D158"

    var body: some View {
        let card = VStack(spacing: 10) {
            Image(systemName: "keyboard").font(.system(size: dim ? 54 : 28, weight: .light))
            Text(lock.blocksPointer ? "Tastatur und Trackpad gesperrt" : "Tastatur gesperrt").font(.system(size: dim ? 22 : 15, weight: .semibold))
            if let end = lock.endDate {
                Text(timerInterval: Date()...max(end, Date().addingTimeInterval(1)), countsDown: true, showsHours: false)
                    .monospacedDigit().font(.system(size: dim ? 44 : 22, weight: .light))
            }
            HStack(spacing: 8) {
                ZStack {
                    Circle().stroke(.white.opacity(0.2), lineWidth: 3)
                    Circle().trim(from: 0, to: lock.escProgress).stroke(Color(hex: activeHex), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: dim ? 22 : 16, height: dim ? 22 : 16)
                Text("Esc \(Int(CleaningLock.holdSeconds)) Sekunden halten zum Beenden").font(.system(size: dim ? 14 : 11)).opacity(0.7)
            }
        }
        .foregroundStyle(.white)
        .padding(dim ? 0 : 18)

        if dim {
            card.frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.black.opacity(0.88))
        } else {
            card.background(Color.black, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
    }
}
