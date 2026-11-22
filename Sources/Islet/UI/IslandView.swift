import SwiftUI

/// Was die kompakte Insel links und rechts neben der Notch zeigen kann.
enum CompactItem: Hashable {
    case music, caffeine, timer, charge, camera, mic

    var width: CGFloat {
        switch self {
        case .music: return 30
        case .caffeine: return 26
        case .timer: return 58
        case .charge: return 64
        case .camera, .mic: return 16
        }
    }
}

func formatTime(_ s: TimeInterval) -> String {
    let t = Int(max(0, s.rounded(.up)))
    return t >= 3600 ? String(format: "%d:%02d:%02d", t / 3600, (t % 3600) / 60, t % 60)
                     : String(format: "%d:%02d", t / 60, t % 60)
}

struct IslandView: View {
    @ObservedObject private var state = IslandState.shared
    @ObservedObject private var geo = IslandGeometry.shared
    @ObservedObject private var music = Music.shared
    @ObservedObject private var caffeine = Caffeine.shared
    @ObservedObject private var timer = CountdownTimer.shared
    @ObservedObject private var battery = Battery.shared
    @ObservedObject private var indicators = Indicators.shared

    @AppStorage("cornerRadius") private var corner = 34.0
    @AppStorage("expandedWidth") private var expW = 560.0
    @AppStorage("expandedHeight") private var expH = 226.0
    @AppStorage("style") private var style = "solid"
    @AppStorage("tintHex") private var tintHex = "#000000"
    @AppStorage("glassStrength") private var glassStrength = 0.55

    @AppStorage("modMusic") private var modMusic = true
    @AppStorage("modTimer") private var modTimer = true
    @AppStorage("modCaffeine") private var modCaffeine = true
    @AppStorage("modBattery") private var modBattery = true
    @AppStorage("modIndicators") private var modIndicators = true
    @AppStorage("compactMusic") private var cMusic = true
    @AppStorage("compactCaffeine") private var cCaffeine = true
    @AppStorage("compactTimer") private var cTimer = true
    @AppStorage("compactCharge") private var cCharge = true
    @AppStorage("compactIndicators") private var cIndicators = true

    private var leadingItems: [CompactItem] {
        var i: [CompactItem] = []
        if modMusic && cMusic && music.isPlaying && music.hasTrack { i.append(.music) }
        if modCaffeine && cCaffeine && caffeine.active { i.append(.caffeine) }
        return i
    }

    private var trailingItems: [CompactItem] {
        var i: [CompactItem] = []
        if modTimer && cTimer && timer.running { i.append(.timer) }
        else if modBattery && cCharge && battery.hasBattery && battery.recentlyPlugged { i.append(.charge) }
        if modIndicators && cIndicators {
            if indicators.camActive { i.append(.camera) }
            if indicators.micActive { i.append(.mic) }
        }
        return i
    }

    private func width(of items: [CompactItem]) -> CGFloat {
        items.isEmpty ? 0 : items.reduce(CGFloat(18)) { $0 + $1.width }
    }

    private var compactWidth: CGFloat {
        // Symmetrisch erweitern, damit die Notch in der Mitte bleibt.
        let side = max(width(of: leadingItems), width(of: trailingItems))
        return side > 0 ? geo.baseWidth + (side + 6) * 2 : geo.baseWidth
    }

    private var compactColor: Color { geo.notchWidth > 0 ? .black : Color(hex: tintHex) }

    var body: some View {
        let expanded = state.expanded
        let shape = NotchShape(top: expanded ? 12 : 6, bottom: expanded ? corner : 14)
        let lead = leadingItems, trail = trailingItems
        ZStack(alignment: .top) {
            if expanded {
                PanelView()
                    .frame(width: expW, height: expH)
                    .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .top)))
            } else {
                CompactView(leading: lead, trailing: trail, sideWidth: max(width(of: lead), width(of: trail)))
                    .transition(.opacity)
            }
        }
        .frame(width: expanded ? expW : compactWidth, height: expanded ? expH : geo.notchHeight, alignment: .top)
        .background { background(shape: shape, expanded: expanded) }
        .clipShape(shape)
        .contentShape(shape)
        .onHover { state.hover($0) }
        .onTapGesture { if !expanded { state.toggle() } }
        .animation(.spring(response: 0.45, dampingFraction: 0.82), value: expanded)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: compactWidth)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private func background(shape: NotchShape, expanded: Bool) -> some View {
        if expanded && style == "glass" {
            Color.clear.modifier(GlassBackground(shape: shape, strength: glassStrength, tint: Color(hex: tintHex)))
        } else {
            (expanded ? Color(hex: tintHex) : compactColor)
        }
    }
}

struct CompactView: View {
    let leading: [CompactItem]
    let trailing: [CompactItem]
    let sideWidth: CGFloat

    @ObservedObject private var geo = IslandGeometry.shared
    @ObservedObject private var music = Music.shared
    @ObservedObject private var timer = CountdownTimer.shared
    @ObservedObject private var battery = Battery.shared
    @AppStorage("activeHex") private var activeHex = "#30D158"
    @AppStorage("accentHex") private var accentHex = "#0A84FF"

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 0) { ForEach(leading, id: \.self) { view(for: $0).frame(width: $0.width) } }
                .frame(width: sideWidth, alignment: .trailing)
                .padding(.trailing, 6)
            Spacer(minLength: geo.notchWidth > 0 ? geo.notchWidth : 0)
            HStack(spacing: 0) { ForEach(trailing, id: \.self) { view(for: $0).frame(width: $0.width) } }
                .frame(width: sideWidth, alignment: .leading)
                .padding(.leading, 6)
        }
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private func view(for item: CompactItem) -> some View {
        switch item {
        case .music:
            if let art = music.artwork {
                Image(nsImage: art).resizable().scaledToFill()
                    .frame(width: 22, height: 22).clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else {
                Image(systemName: "music.note").foregroundStyle(Color(hex: accentHex)).font(.system(size: 13, weight: .semibold))
            }
        case .caffeine:
            Image(systemName: "cup.and.heat.waves.fill").foregroundStyle(Color(hex: activeHex)).font(.system(size: 13, weight: .semibold))
        case .timer:
            Group {
                if let rest = timer.pausedRemaining {
                    Text(formatTime(rest)).foregroundStyle(.white.opacity(0.55))
                } else if let end = timer.endDate {
                    Text(timerInterval: Date()...max(end, Date().addingTimeInterval(1)), countsDown: true, showsHours: false)
                        .foregroundStyle(Color(hex: accentHex))
                }
            }
            .monospacedDigit().font(.system(size: 12, weight: .semibold))
        case .charge:
            HStack(spacing: 3) {
                Image(systemName: "bolt.fill").foregroundStyle(Color(hex: activeHex))
                Text("\(battery.percent)%").monospacedDigit()
            }.font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
        case .camera:
            Circle().fill(Color(hex: "#30D158")).frame(width: 8, height: 8)
        case .mic:
            Circle().fill(Color(hex: "#FF9F0A")).frame(width: 8, height: 8)
        }
    }
}
