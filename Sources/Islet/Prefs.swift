import SwiftUI
import AppKit

/// Alle Einstellungen liegen in UserDefaults (SwiftUI @AppStorage liest dieselben Schlüssel).
enum Pref {
    static let defaults: [String: Any] = [
        // Farben & Stil
        "accentHex": "#0A84FF",
        "activeHex": "#30D158",
        "tintHex": "#000000",
        "style": "solid",            // solid (schwarz) | glass
        "glassStrength": 0.55,
        // Größe
        "cornerRadius": 34.0,
        "expandedWidth": 560.0,
        "expandedHeight": 226.0,
        "hoverExpand": true,
        "hoverDelay": 0.12,
        "collapseDelay": 0.28,
        // Allgemein
        "showMenuBarIcon": true,
        "display": "notch",          // notch | main | mouse
        "hotkey": "ctrlOptSpace",    // off | ctrlOptSpace | cmdOptI | ctrlOptI
        "hideInFullscreen": true,
        "haptics": true,
        "startTab": "last",          // last | music | overview
        // Kompakte Insel
        "compactMusic": true,
        "compactCaffeine": true,
        "compactTimer": true,
        "compactCharge": true,
        "compactIndicators": true,
        "compactCalendar": true,
        "compactDevices": true,
        // Kalender
        "calendarDays": 2,
        "calendarSoonMinutes": 10,
        "calendarAllDay": true,
        "calendarExcluded": "[]",
        // Module
        "modCalendar": true,
        "modDevices": true,
        "modMusic": true,
        "modTimer": true,
        "modCaffeine": true,
        "modBattery": true,
        "modStats": true,
        "modToggles": true,
        "modClipboard": true,
        "modIndicators": true,
        "modHUD": true,
        "modGestures": true,
        "modActions": true,
        // Zwischenablage
        "clipboardMax": 10,
        // Koffein
        "caffeineMode": "full",      // full (-dims) | system (-ims, Display darf aus)
        "caffeineDefaultMinutes": 0, // 0 = unbegrenzt
        // Timer
        "timerDefaultMinutes": 10,
        "timerSound": true,
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
    static func int(_ k: String) -> Int { UserDefaults.standard.integer(forKey: k) }
    static func string(_ k: String) -> String { UserDefaults.standard.string(forKey: k) ?? "" }

    /// Alle Schlüssel für Export/Import und Zurücksetzen.
    static var allKeys: [String] { Array(defaults.keys) + ["actionsJSON"] }

    static func reset(_ keys: [String]) {
        for k in keys { UserDefaults.standard.set(defaults[k], forKey: k) }
    }

    static func exportJSON() -> Data? {
        var out: [String: Any] = [:]
        for k in allKeys { if let v = UserDefaults.standard.object(forKey: k) { out[k] = v } }
        return try? JSONSerialization.data(withJSONObject: out, options: [.prettyPrinted, .sortedKeys])
    }

    @discardableResult
    static func importJSON(_ data: Data) -> Bool {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        for (k, v) in obj where defaults[k] != nil { UserDefaults.standard.set(v, forKey: k) }
        return true
    }
}

/// Farbvorlagen für „Aussehen“.
struct Theme: Identifiable {
    let id: String, name: String, accent: String, active: String, tint: String
    static let all: [Theme] = [
        .init(id: "classic", name: "Klassisch", accent: "#0A84FF", active: "#30D158", tint: "#000000"),
        .init(id: "violet", name: "Violett", accent: "#BF5AF2", active: "#64D2FF", tint: "#0B0612"),
        .init(id: "sunset", name: "Sonnenuntergang", accent: "#FF9F0A", active: "#FF453A", tint: "#120805"),
        .init(id: "forest", name: "Wald", accent: "#30D158", active: "#FFD60A", tint: "#050D08"),
        .init(id: "rose", name: "Rosé", accent: "#FF375F", active: "#FFD60A", tint: "#12060A"),
        .init(id: "mono", name: "Mono", accent: "#FFFFFF", active: "#D1D1D6", tint: "#000000"),
    ]
    func apply() {
        let d = UserDefaults.standard
        d.set(accent, forKey: "accentHex"); d.set(active, forKey: "activeHex"); d.set(tint, forKey: "tintHex")
    }
}

/// Weiches Antippen-Feedback auf dem Trackpad.
enum Haptics {
    static func tap() {
        guard Pref.bool("haptics") else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }
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
