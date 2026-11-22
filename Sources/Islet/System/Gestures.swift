import Foundation
import CMultitouch

/// Wisch am linken/rechten Trackpad-Rand nach oben/unten regelt Lautstärke bzw. Helligkeit.
/// Nutzt die private MultitouchSupport-Schnittstelle (zur Laufzeit geladen).
final class Gestures {
    static let shared = Gestures()

    private(set) var running = false
    var onDelta: ((_ side: Side, _ delta: Float) -> Void)?

    enum Side { case left, right }

    // Nur vom Multitouch-Thread berührt.
    private var tracking: Side?
    private var lastY: Float = 0
    private var edge: Float = 0.08
    private var sensitivity: Float = 1.2

    @discardableResult
    func start() -> Bool {
        if running { return true }
        reloadSettings()
        let ok = cmt_start { fingers, x, y in Gestures.shared.frame(fingers: Int(fingers), x: x, y: y) }
        running = ok
        return ok
    }

    func stop() {
        guard running else { return }
        cmt_stop()
        running = false
        tracking = nil
        InputTap.shared.suppressScroll = false
    }

    func reloadSettings() {
        edge = Float(Pref.double("gestureEdge"))
        sensitivity = Float(Pref.double("gestureSensitivity"))
    }

    private func frame(fingers: Int, x: Float, y: Float) {
        guard fingers == 1 else {
            if tracking != nil { tracking = nil; InputTap.shared.suppressScroll = false }
            return
        }
        if tracking == nil {
            if x < edge { tracking = .left } else if x > 1 - edge { tracking = .right } else { return }
            lastY = y
            InputTap.shared.suppressScroll = true
            return
        }
        let dy = (y - lastY) * sensitivity
        guard abs(dy) > 0.004 else { return }
        lastY = y
        if let side = tracking { onDelta?(side, dy) }
    }
}
