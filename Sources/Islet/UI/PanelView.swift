import SwiftUI

/// Geöffnete Insel: oben eine Leiste (links Ansichten, rechts Zahnrad, dazwischen die Notch),
/// darunter die gewählte Ansicht. Schwarz, ruhig, wie die Dynamic Island auf dem iPhone.
struct PanelView: View {
    @ObservedObject private var state = IslandState.shared
    @ObservedObject private var geo = IslandGeometry.shared
    @ObservedObject private var battery = Battery.shared
    @AppStorage("modMusic") private var modMusic = true
    @AppStorage("modTimer") private var modTimer = true
    @AppStorage("modCaffeine") private var modCaffeine = true
    @AppStorage("modBattery") private var modBattery = true
    @AppStorage("modStats") private var modStats = true
    @AppStorage("modActions") private var modActions = true
    @Namespace private var tabSpace

    private var tabs: [IslandTab] {
        var t: [IslandTab] = []
        if modMusic { t.append(.music) }
        if modCaffeine || modTimer || modStats || (modBattery && battery.hasBattery) { t.append(.overview) }
        if modActions { t.append(.actions) }
        return t
    }

    private var current: IslandTab? { tabs.contains(state.tab) ? state.tab : tabs.first }

    var body: some View {
        VStack(spacing: 0) {
            header
            Group {
                switch current {
                case .music: MusicView()
                case .overview: OverviewView()
                case .actions: ActionsView()
                case nil: Text("Alle Module sind aus.").font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
                }
            }
            .id(current)
            .transition(.opacity.combined(with: .scale(scale: 0.97)))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 22)
            .padding(.bottom, 18)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.86), value: current)
    }

    /// Leiste auf Höhe der Notch: Ansichten links, Zahnrad rechts, Lücke für die Notch in der Mitte.
    private var header: some View {
        HStack(spacing: 0) {
            HStack(spacing: 4) {
                ForEach(tabs) { tab in
                    Button { state.tab = tab } label: {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 34, height: 24)
                            .foregroundStyle(current == tab ? .white : .white.opacity(0.45))
                            .background {
                                if current == tab {
                                    Capsule().fill(.white.opacity(0.16)).matchedGeometryEffect(id: "tab", in: tabSpace)
                                }
                            }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help(tab.title)
                }
            }
            Spacer(minLength: geo.notchWidth > 0 ? geo.notchWidth + 24 : 8)
            Button { SettingsWindow.show() } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 34, height: 24)
                    .foregroundStyle(.white.opacity(0.45))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Einstellungen öffnen")
        }
        .padding(.horizontal, 20)
        .frame(height: max(geo.notchHeight, 30))
    }
}

/// Übersicht: Koffein, Timer, Akku und Stats in einer ruhigen Reihe.
struct OverviewView: View {
    @AppStorage("modTimer") private var modTimer = true
    @AppStorage("modCaffeine") private var modCaffeine = true
    @AppStorage("modBattery") private var modBattery = true
    @AppStorage("modStats") private var modStats = true
    @ObservedObject private var battery = Battery.shared

    var body: some View {
        HStack(spacing: 10) {
            if modCaffeine { CaffeineTile() }
            if modTimer { TimerTile() }
            if modBattery && battery.hasBattery { BatteryTile() }
            if modStats { StatsTile() }
        }
        .frame(maxHeight: .infinity)
    }
}

/// Eigene Aktionen als Kacheln.
struct ActionsView: View {
    @AppStorage("actionsJSON") private var actionsJSON = "[]"

    private var actions: [ActionItem] {
        (try? JSONDecoder().decode([ActionItem].self, from: Data(actionsJSON.utf8))) ?? []
    }

    var body: some View {
        if actions.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "bolt").font(.system(size: 24, weight: .light))
                Text("Noch keine Aktionen").font(.system(size: 12, weight: .medium)).opacity(0.7)
                Button("Aktion anlegen") { SettingsWindow.show() }
                    .buttonStyle(.plain).font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 12).padding(.vertical, 5).background(.white.opacity(0.14), in: Capsule())
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                    ForEach(actions) { ActionTile(item: $0) }
                }
            }
        }
    }
}

/// Basis jeder Kachel: flach, dunkelgrau, optional farbig.
struct Tile<Content: View>: View {
    var tint: Color? = nil
    var action: (() -> Void)? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        Button(action: { action?() }) {
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(8)
        }
        .buttonStyle(TilePressStyle())
        .frame(height: 92)
        .background(tint.map { AnyShapeStyle($0.opacity(0.92)) } ?? AnyShapeStyle(Color.white.opacity(0.10)), in: shape)
        .clipShape(shape)
    }
}

struct TilePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: Koffein

struct CaffeineTile: View {
    @ObservedObject private var caffeine = Caffeine.shared
    @AppStorage("activeHex") private var activeHex = "#30D158"

    var body: some View {
        Tile(tint: caffeine.active ? Color(hex: activeHex) : nil, action: { caffeine.toggle() }) {
            VStack(spacing: 5) {
                Image(systemName: caffeine.active ? "cup.and.heat.waves.fill" : "cup.and.saucer")
                    .font(.system(size: 22, weight: .medium))
                    .contentTransition(.symbolEffect(.replace))
                Text(caffeine.active ? "Wach" : "Koffein").font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(.white)
        }
        .contextMenu {
            Button("15 Minuten") { caffeine.turnOn(seconds: 15 * 60) }
            Button("1 Stunde") { caffeine.turnOn(seconds: 3600) }
            Button("3 Stunden") { caffeine.turnOn(seconds: 3 * 3600) }
            Button("Unbegrenzt") { caffeine.turnOn(seconds: nil) }
            if caffeine.active { Divider(); Button("Ausschalten") { caffeine.turnOff() } }
        }
        .help("Klick: an/aus. Rechtsklick: Dauer wählen. Zeigt live, ob caffeinate läuft.")
    }
}

// MARK: Timer

struct TimerTile: View {
    @ObservedObject private var timer = CountdownTimer.shared
    @AppStorage("accentHex") private var accentHex = "#0A84FF"

    var body: some View {
        Tile(tint: timer.running ? Color(hex: accentHex) : nil, action: { if timer.running { timer.stop() } else { timer.start(minutes: 10) } }) {
            VStack(spacing: 5) {
                if timer.running, let end = timer.endDate {
                    Text(timerInterval: Date()...max(end, Date().addingTimeInterval(1)), countsDown: true, showsHours: false)
                        .monospacedDigit().font(.system(size: 19, weight: .semibold))
                    Text(timer.label).font(.system(size: 11, weight: .semibold)).opacity(0.8)
                } else {
                    Image(systemName: "timer").font(.system(size: 22, weight: .medium))
                    Text("Timer").font(.system(size: 11, weight: .semibold))
                }
            }
            .foregroundStyle(.white)
        }
        .contextMenu {
            Button("5 Minuten") { timer.start(minutes: 5) }
            Button("10 Minuten") { timer.start(minutes: 10) }
            Button("15 Minuten") { timer.start(minutes: 15) }
            Button("30 Minuten") { timer.start(minutes: 30) }
            Button("60 Minuten") { timer.start(minutes: 60) }
            Divider()
            Button("Pomodoro starten") { timer.startPomodoro() }
            if timer.running { Divider(); Button("Stoppen") { timer.stop() } }
        }
        .help("Klick: 10 Minuten starten/stoppen. Rechtsklick: Dauer oder Pomodoro.")
    }
}

// MARK: Akku

struct BatteryTile: View {
    @ObservedObject private var battery = Battery.shared
    @AppStorage("activeHex") private var activeHex = "#30D158"

    var body: some View {
        Tile {
            VStack(spacing: 5) {
                ZStack {
                    Circle().stroke(.white.opacity(0.18), lineWidth: 4)
                    Circle().trim(from: 0, to: CGFloat(battery.percent) / 100)
                        .stroke(battery.percent <= 20 && !battery.pluggedIn ? Color.red : Color(hex: activeHex),
                                style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    if battery.pluggedIn { Image(systemName: "bolt.fill").font(.system(size: 11)) }
                }
                .frame(width: 34, height: 34)
                Text("\(battery.percent)%").font(.system(size: 11, weight: .semibold)).monospacedDigit()
            }
            .foregroundStyle(.white)
        }
    }
}

// MARK: Stats

struct StatsTile: View {
    @ObservedObject private var stats = Stats.shared
    @AppStorage("accentHex") private var accentHex = "#0A84FF"

    var body: some View {
        Tile {
            VStack(spacing: 6) {
                row("CPU", stats.cpu)
                row("GPU", stats.gpu)
                row("RAM", stats.mem)
            }
            .foregroundStyle(.white)
        }
        .onAppear { Stats.shared.retain() }
        .onDisappear { Stats.shared.release() }
    }

    private func row(_ name: String, _ v: Double) -> some View {
        HStack(spacing: 5) {
            Text(name).font(.system(size: 9, weight: .bold)).frame(width: 24, alignment: .leading).opacity(0.8)
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.18))
                GeometryReader { g in Capsule().fill(Color(hex: accentHex)).frame(width: max(3, g.size.width * v)) }
            }
            .frame(height: 5)
        }
    }
}

// MARK: Eigene Aktion

struct ActionTile: View {
    let item: ActionItem
    var body: some View {
        Tile(action: { item.run() }) {
            VStack(spacing: 5) {
                Image(systemName: item.symbol).font(.system(size: 22, weight: .medium))
                Text(item.title).font(.system(size: 11, weight: .semibold)).lineLimit(1)
            }
            .foregroundStyle(.white)
        }
    }
}

// MARK: Musik

/// Musik wie die Live Activity auf dem iPhone: Cover links, Titel, Fortschritt, Tasten.
struct MusicView: View {
    @ObservedObject private var music = Music.shared
    @AppStorage("accentHex") private var accentHex = "#0A84FF"
    @State private var scrub: Double? = nil

    var body: some View {
        Group {
            if music.running && music.hasTrack {
                HStack(spacing: 18) {
                    Group {
                        if let art = music.artwork { Image(nsImage: art).resizable().scaledToFill() }
                        else { Image(systemName: "music.note").font(.system(size: 28, weight: .light)).frame(maxWidth: .infinity, maxHeight: .infinity).background(.white.opacity(0.10)) }
                    }
                    .frame(width: 100, height: 100)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .shadow(color: .black.opacity(0.5), radius: 8, y: 3)

                    VStack(alignment: .leading, spacing: 0) {
                        Text(music.title).font(.system(size: 16, weight: .semibold)).lineLimit(1)
                        Text(music.artist).font(.system(size: 13)).opacity(0.6).lineLimit(1).padding(.top, 2)
                        Spacer(minLength: 6)
                        progress
                        controls.padding(.top, 8)
                    }
                    .frame(height: 100)
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "music.note").font(.system(size: 26, weight: .light))
                    Text(music.running ? "Nichts spielt" : "Spotify ist nicht geöffnet").font(.system(size: 12, weight: .medium)).opacity(0.7)
                    if !music.running {
                        Button("Spotify öffnen") { music.open() }
                            .buttonStyle(.plain).font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 12).padding(.vertical, 5).background(.white.opacity(0.14), in: Capsule())
                    }
                }
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var progress: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let dur = max(1, music.duration)
            let pos = scrub ?? (music.position / dur)
            HStack(spacing: 7) {
                Text(fmt(pos * dur)).font(.system(size: 10)).monospacedDigit().opacity(0.55).frame(width: 32, alignment: .leading)
                GlassSlider(value: Binding(get: { pos }, set: { scrub = $0 }), tint: .white,
                            onCommit: { v in music.seek(to: v * dur); scrub = nil })
                Text("-" + fmt(max(0, dur - pos * dur))).font(.system(size: 10)).monospacedDigit().opacity(0.55).frame(width: 36, alignment: .trailing)
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 34) {
            Button { music.previous() } label: { Image(systemName: "backward.fill").font(.system(size: 17)) }
            Button { music.playPause() } label: { Image(systemName: music.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 22)).frame(width: 26) }
            Button { music.next() } label: { Image(systemName: "forward.fill").font(.system(size: 17)) }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    private func fmt(_ s: Double) -> String {
        let t = Int(max(0, s))
        return String(format: "%d:%02d", t / 60, t % 60)
    }
}
