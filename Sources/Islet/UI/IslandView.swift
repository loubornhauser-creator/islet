import SwiftUI

struct IslandView: View {
    @ObservedObject private var state = IslandState.shared
    @ObservedObject private var geo = IslandGeometry.shared
    @ObservedObject private var music = Music.shared
    @ObservedObject private var caffeine = Caffeine.shared
    @ObservedObject private var timer = CountdownTimer.shared
    @ObservedObject private var battery = Battery.shared

    @AppStorage("cornerRadius") private var corner = 30.0
    @AppStorage("expandedWidth") private var expW = 620.0
    @AppStorage("expandedHeight") private var expH = 214.0
    @AppStorage("style") private var style = "glass"
    @AppStorage("tintHex") private var tintHex = "#000000"
    @AppStorage("glassStrength") private var glassStrength = 0.55
    @AppStorage("modMusic") private var modMusic = true
    @AppStorage("modTimer") private var modTimer = true
    @AppStorage("modCaffeine") private var modCaffeine = true
    @AppStorage("modBattery") private var modBattery = true

    private var showMusic: Bool { modMusic && music.isPlaying && music.hasTrack }
    private var showCaffeine: Bool { modCaffeine && caffeine.active }
    private var showTimer: Bool { modTimer && timer.running }
    private var showCharge: Bool { modBattery && battery.hasBattery && battery.recentlyPlugged }

    private var leadingWidth: CGFloat { (showMusic || showCaffeine) ? 40 : 0 }
    private var trailingWidth: CGFloat { showTimer ? 64 : (showCharge ? 70 : 0) }
    private var compactWidth: CGFloat { geo.baseWidth + leadingWidth + trailingWidth }

    var body: some View {
        let expanded = state.expanded
        let shape = UnevenRoundedRectangle(topLeadingRadius: expanded ? 0 : 0,
                                           bottomLeadingRadius: expanded ? corner : 14,
                                           bottomTrailingRadius: expanded ? corner : 14,
                                           topTrailingRadius: 0, style: .continuous)
        ZStack(alignment: .top) {
            if expanded {
                PanelView()
                    .frame(width: expW, height: expH)
                    .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .top)))
            } else {
                CompactView(leading: leadingWidth, trailing: trailingWidth,
                            showMusic: showMusic, showCaffeine: showCaffeine,
                            showTimer: showTimer, showCharge: showCharge)
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
    private func background(shape: UnevenRoundedRectangle, expanded: Bool) -> some View {
        if expanded && style == "glass" {
            Color.clear.modifier(GlassBackground(shape: shape, strength: glassStrength, tint: Color(hex: tintHex)))
        } else {
            Color(hex: tintHex)    // kompakt immer vollflächig, damit es mit der Notch verschmilzt
        }
    }
}

struct CompactView: View {
    let leading: CGFloat
    let trailing: CGFloat
    let showMusic: Bool
    let showCaffeine: Bool
    let showTimer: Bool
    let showCharge: Bool

    @ObservedObject private var geo = IslandGeometry.shared
    @ObservedObject private var music = Music.shared
    @ObservedObject private var timer = CountdownTimer.shared
    @ObservedObject private var battery = Battery.shared
    @AppStorage("activeHex") private var activeHex = "#30D158"
    @AppStorage("accentHex") private var accentHex = "#0A84FF"

    var body: some View {
        HStack(spacing: 0) {
            Group {
                if showMusic {
                    if let art = music.artwork {
                        Image(nsImage: art).resizable().scaledToFill()
                            .frame(width: 22, height: 22).clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    } else {
                        Image(systemName: "music.note").foregroundStyle(Color(hex: accentHex))
                    }
                } else if showCaffeine {
                    Image(systemName: "cup.and.heat.waves.fill").foregroundStyle(Color(hex: activeHex)).font(.system(size: 13, weight: .semibold))
                }
            }
            .frame(width: leading)
            Spacer(minLength: geo.notchWidth > 0 ? geo.notchWidth : 0)
            Group {
                if showTimer, let end = timer.endDate {
                    Text(timerInterval: Date()...max(end, Date().addingTimeInterval(1)), countsDown: true, showsHours: false)
                        .monospacedDigit().font(.system(size: 12, weight: .semibold)).foregroundStyle(Color(hex: accentHex))
                } else if showCharge {
                    HStack(spacing: 3) {
                        Image(systemName: "bolt.fill").foregroundStyle(Color(hex: activeHex))
                        Text("\(battery.percent)%").monospacedDigit()
                    }.font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                }
            }
            .frame(width: trailing)
        }
        .frame(maxHeight: .infinity)
    }
}
