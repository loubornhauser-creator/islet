import SwiftUI
import AppKit

/// Alle Einstellungen liegen in UserDefaults (SwiftUI @AppStorage liest dieselben Schlüssel).
enum Pref {
    static let defaults: [String: Any] = [
        // Farben & Stil
        "accentHex": "#0A84FF",
        "activeHex": "#30D158",
        "tintHex": "#000000",
        "style": "glass",            // glass | solid
        "glassStrength": 0.55,
        // Größe
        "cornerRadius": 30.0,
        "expandedWidth": 620.0,
        "expandedHeight": 214.0,
        "hoverExpand": true,
        "hoverDelay": 0.12,
        // Module
        "modMusic": true,
        "modTimer": true,
        "modCaffeine": true,
        "modBattery": true,
        "modStats": true,
        "modHUD": true,
        "modGestures": true,
        "modActions": true,
        // HUD
        "hudSide": "right",          // left | right
        "hudSeconds": 1.6,
        "hudReplaceSystem": true,
        // Gesten
        "gestureEdge": 0.08,
        "gestureSensitivity": 1.2,
        "gestureLeft": "volume",     // volume | brightness | off
        "gestureRight": "brightness",
        // Timer
        "pomoWork": 25,
        "pomoBreak": 5,
        // Eigene Aktionen
        "actionsJSON": "[]",
    ]

    static func register() { UserDefaults.standard.register(defaults: defaults) }
    static func bool(_ k: String) -> Bool { UserDefaults.standard.bool(forKey: k) }
    static func double(_ k: String) -> Double { UserDefaults.standard.double(forKey: k) }
    static func string(_ k: String) -> String { UserDefaults.standard.string(forKey: k) ?? "" }
}

extension Color {
    init(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        self.init(.sRGB,
                  red: Double((v >> 16) & 255) / 255,
                  green: Double((v >> 8) & 255) / 255,
                  blue: Double(v & 255) / 255,
                  opacity: 1)
    }

    var hex: String {
        let c = NSColor(self).usingColorSpace(.sRGB) ?? .black
        return String(format: "#%02X%02X%02X",
                      Int(round(c.redComponent * 255)),
                      Int(round(c.greenComponent * 255)),
                      Int(round(c.blueComponent * 255)))
    }
}

/// Ein Pille-förmiger Slider ohne Key-Window-Abhängigkeit (funktioniert im nicht aktivierenden Panel).
struct GlassSlider: View {
    @Binding var value: Double
    var tint: Color
    var onCommit: ((Double) -> Void)? = nil

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.18)).frame(height: 6)
                Capsule().fill(tint).frame(width: max(6, g.size.width * value), height: 6)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in value = min(1, max(0, v.location.x / max(1, g.size.width))) }
                    .onEnded { _ in onCommit?(value) }
            )
        }
        .frame(height: 20)
    }
}
