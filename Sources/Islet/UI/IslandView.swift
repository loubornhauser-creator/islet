import SwiftUI

/// Was die kompakte Insel links und rechts neben der Notch zeigen kann.
enum CompactItem: Hashable {
    case device, music, caffeine, timer, charge, deviceBattery, calendar, camera, mic

    var width: CGFloat {
        switch self {
        case .device: return 30
        case .music: return 30
        case .caffeine: return 26
        case .timer: return 58
        case .charge: return 64
        case .deviceBattery: return 46
        case .calendar: return 66
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
    @ObservedObject private var devices = Devices.shared
    @ObservedObject private var calendar = CalendarModule.shared

    @AppStorage("cornerRadius") private var corner = 34.0
    @AppStorage("expandedWidth") private var prefW = 560.0
    @AppStorage("expandedHeight") private var prefH = 226.0
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
    @AppStorage("modDevices") private var modDevices = true
    @AppStorage("compactDevices") private var cDevices = true
    @AppStorage("modCalendar") private var modCalendar = true
    @AppStorage("compactCalendar") private var cCalendar = true

    @AppStorage("liveSideItems") private var liveSide = true
    @AppStorage("animStyle") private var animStyle = "island"

    private var showDevice: Bool { modDevices && cDevices && devices.chip != nil }

    private var leadingItems: [CompactItem] {
        guard liveSide else { return [] }   // aus: geschlossen immer exakt Notch-Größe
        var i: [CompactItem] = []
        if showDevice { i.append(.device) }
        if modMusic && cMusic && music.isPlaying && music.hasTrack { i.append(.music) }
        if modCaffeine && cCaffeine && caffeine.active { i.append(.caffeine) }
        return i
    }

    private var trailingItems: [CompactItem] {
        guard liveSide else { return [] }
        var i: [CompactItem] = []
        if showDevice, devices.chip?.level != nil { i.append(.deviceBattery) }
        if modTimer && cTimer && timer.running { i.append(.timer) }
        else if modBattery && cCharge && battery.hasBattery && battery.recentlyPlugged { i.append(.charge) }
        if modCalendar && cCalendar && calendar.soon != nil { i.append(.calendar) }
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

    private var expW: CGFloat { max(CGFloat(prefW), geo.minExpandedWidth) }
    private var expH: CGFloat { max(CGFloat(prefH), geo.minExpandedHeight) }

    private var compactColor: Color { geo.notchWidth > 0 ? .black : Color(hex: tintHex) }

    var body: some View {
        let expanded = state.expanded
        let visible = state.contentVisible
        let shape = NotchShape(top: expanded ? 12 : 6, bottom: expanded ? corner : 14)
        ZStack(alignment: .top) {
            if expanded {
                PanelView()
                    .frame(width: expW, height: expH)
                    .opacity(visible ? 1 : 0)
                    .blur(radius: visible ? 0 : 10)
                    .scaleEffect(visible ? 1 : 0.9, anchor: .top)
                    .animation(visible ? IslandMotion.contentIn : IslandMotion.contentOut, value: visible)
            } else {
                CompactView(leading: leadingItems, trailing: trailingItems,
                            sideWidth: max(width(of: leadingItems), width(of: trailingItems)))
            }
        }
        .frame(width: expanded ? expW : compactWidth, height: expanded ? expH : geo.notchHeight, alignment: .top)
        .background { background(shape: shape, expanded: expanded) }
        .clipShape(shape)
        .contentShape(shape)
        .onHover { state.hover($0) }
        .onTapGesture { if !expanded { state.toggle() } }
        .animation(expanded ? IslandMotion.open : IslandMotion.close, value: expanded)
        .animation(.spring(response: 0.4, dampingFraction: 0.9), value: compactWidth)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { state.compactWidth = compactWidth }
        .onChange(of: compactWidth) { state.compactWidth = $0 }
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
    @ObservedObject private var devices = Devices.shared
    @ObservedObject private var calendar = CalendarModule.shared
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
        case .device:
            Image(systemName: devices.chip?.symbol ?? "headphones").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
        case .deviceBattery:
            if let level = devices.chip?.level {
                Text("\(level)%").monospacedDigit().font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(level <= 20 ? Color.red : Color.white)
            }
        case .calendar:
            if let e = calendar.soon {
                HStack(spacing: 4) {
                    Image(systemName: "calendar").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color(hex: accentHex))
                    Text(timerInterval: Date()...max(e.start, Date().addingTimeInterval(1)), countsDown: true, showsHours: false)
                        .monospacedDigit().font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                }
            }
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
