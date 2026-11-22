import SwiftUI
import AppKit

private func colorBinding(_ hex: Binding<String>) -> Binding<Color> {
    Binding(get: { Color(hex: hex.wrappedValue) }, set: { hex.wrappedValue = $0.hex })
}

/// Farbfeld mit Hex-Anzeige.
struct ColorRow: View {
    let title: String
    let subtitle: String?
    @Binding var hex: String

    var body: some View {
        LabeledContent {
            HStack(spacing: 8) {
                Text(hex.uppercased()).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                ColorPicker("", selection: colorBinding($hex), supportsOpacity: false).labelsHidden()
            }
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
            }
        }
    }
}

struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double? = nil
    var format: (Double) -> String

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 10) {
                Group {
                    if let step { Slider(value: $value, in: range, step: step) } else { Slider(value: $value, in: range) }
                }
                .frame(width: 210)
                Text(format(value)).monospacedDigit().foregroundStyle(.secondary).frame(width: 58, alignment: .trailing)
            }
        }
    }
}

struct ToggleRow: View {
    let title: String
    var subtitle: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
            }
        }
    }
}

/// Zeile für ein Modul: farbiges Symbol, Titel, Erklärung, Schalter.
struct ModuleRow: View {
    let symbol: String
    let color: Color
    let title: String
    let subtitle: String
    @AppStorage private var isOn: Bool

    init(symbol: String, color: Color, title: String, subtitle: String, key: String, defaultOn: Bool = true) {
        self.symbol = symbol; self.color = color; self.title = title; self.subtitle = subtitle
        self.key = key
        _isOn = AppStorage(wrappedValue: defaultOn, key)
    }

    @State private var showInfo = false
    private var key = ""
    private var doc: ModuleDoc? { ModuleDocs.doc(for: key) }

    var body: some View {
        HStack(spacing: 8) {
            Toggle(isOn: $isOn) {
                HStack(spacing: 11) {
                    Image(systemName: symbol)
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(color.gradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title)
                        Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .toggleStyle(.switch)
            if let doc {
                Button { showInfo.toggle() } label: {
                    Image(systemName: "info.circle").font(.system(size: 15)).foregroundStyle(.secondary).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Beschreibung und Anleitung")
                .popover(isPresented: $showInfo, arrowEdge: .trailing) { ModuleInfoView(doc: doc) }
            }
        }
    }
}

/// Kleine, ehrliche Vorschau der Insel mit den aktuellen Farben und Maßen.
struct IslandPreview: View {
    @AppStorage("accentHex") private var accent = "#0A84FF"
    @AppStorage("activeHex") private var active = "#30D158"
    @AppStorage("tintHex") private var tint = "#000000"
    @AppStorage("style") private var style = "solid"
    @AppStorage("glassStrength") private var strength = 0.55
    @AppStorage("cornerRadius") private var corner = 34.0
    @AppStorage("expandedWidth") private var expW = 560.0
    @AppStorage("expandedHeight") private var expH = 226.0

    var body: some View {
        let w: CGFloat = 340
        let geo = IslandGeometry.shared
        let effW = max(CGFloat(expW), geo.minExpandedWidth), effH = max(CGFloat(expH), geo.minExpandedHeight)
        let scale = w / effW
        let h = effH * scale
        let shape = NotchShape(top: 12 * scale, bottom: CGFloat(corner) * scale)
        ZStack(alignment: .top) {
            LinearGradient(colors: [Color(hex: "#5E5CE6").opacity(0.55), Color(hex: "#FF6B6B").opacity(0.45)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            ZStack(alignment: .top) {
                shape.fill(Color(hex: tint).opacity(style == "glass" ? max(0.35, strength) : 1))
                    .overlay { if style == "glass" { shape.fill(.ultraThinMaterial).opacity(0.6) } }
                VStack(spacing: 8 * scale + 2) {
                    HStack(spacing: 4) {
                        ForEach(0..<3, id: \.self) { i in
                            Capsule().fill(.white.opacity(i == 0 ? 0.3 : 0.12)).frame(width: 18, height: 9)
                        }
                        Spacer()
                        Capsule().fill(.black).frame(width: 64, height: 12)
                        Spacer()
                        Circle().fill(.white.opacity(0.2)).frame(width: 9, height: 9)
                    }
                    .padding(.horizontal, 16)
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color(hex: accent).opacity(0.9)).frame(width: h * 0.42, height: h * 0.42)
                        VStack(alignment: .leading, spacing: 5) {
                            Capsule().fill(.white.opacity(0.85)).frame(width: 90, height: 6)
                            Capsule().fill(.white.opacity(0.4)).frame(width: 60, height: 5)
                            Capsule().fill(.white.opacity(0.18)).frame(width: 120, height: 4)
                            Capsule().fill(Color(hex: accent)).frame(width: 52, height: 4).frame(width: 120, alignment: .leading)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 22)
                    HStack(spacing: 6) {
                        tile(Color(hex: active))
                        tile(Color(hex: accent))
                        tile(.white.opacity(0.12))
                        tile(.white.opacity(0.12))
                    }
                    .padding(.horizontal, 22)
                }
                .padding(.top, 6)
            }
            .frame(width: w, height: h)
            .padding(.top, 10)
            .animation(.easeOut(duration: 0.2), value: corner)
            .animation(.easeOut(duration: 0.2), value: expW)
        }
        .frame(width: w + 40, height: h + 26)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .frame(maxWidth: .infinity)
    }

    private func tile<S: ShapeStyle>(_ s: S) -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous).fill(s).frame(height: 22)
    }
}

/// Eine Farbvorlage als Kreis mit Akzent- und Aktiv-Farbe.
struct ThemeSwatch: View {
    let theme: Theme
    @AppStorage("accentHex") private var accent = "#0A84FF"
    @AppStorage("activeHex") private var active = "#30D158"
    @AppStorage("tintHex") private var tint = "#000000"
    private var selected: Bool { accent == theme.accent && active == theme.active && tint == theme.tint }

    var body: some View {
        Button { theme.apply() } label: {
            VStack(spacing: 5) {
                ZStack {
                    Circle().fill(Color(hex: theme.tint))
                    Circle().fill(Color(hex: theme.accent)).frame(width: 18, height: 18).offset(x: -6, y: -3)
                    Circle().fill(Color(hex: theme.active)).frame(width: 12, height: 12).offset(x: 8, y: 6)
                }
                .frame(width: 42, height: 42)
                .overlay(Circle().strokeBorder(selected ? Color.accentColor : Color.white.opacity(0.25), lineWidth: selected ? 2.5 : 1))
                Text(theme.name).font(.system(size: 10)).foregroundStyle(selected ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
    }
}

/// Aktueller Speicherverbrauch dieses Prozesses (phys_footprint, wie die Aktivitätsanzeige).
func memoryFootprintMB() -> Double {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let r = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    return r == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0
}

/// Berechtigungen abfragen, ohne Dialoge auszulösen.
enum Perm {
    enum State { case granted, denied, notAsked, notRunning, unknown
        var label: String {
            switch self {
            case .granted: return "Erlaubt"
            case .denied: return "Abgelehnt"
            case .notAsked: return "Noch nicht gefragt"
            case .notRunning: return "App läuft nicht"
            case .unknown: return "Unbekannt"
            }
        }
    }

    static func automation(_ bundleID: String, ask: Bool = false) -> State {
        let target = NSAppleEventDescriptor(bundleIdentifier: bundleID)
        let status = AEDeterminePermissionToAutomateTarget(target.aeDesc, AEEventClass(typeWildCard), AEEventID(typeWildCard), ask)
        switch Int(status) {
        case 0: return .granted
        case -1743: return .denied
        case -1744: return .notAsked
        case -600: return .notRunning
        default: return .unknown
        }
    }
}
