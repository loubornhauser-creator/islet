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
    @AppStorage("modToggles") private var modToggles = true
    @AppStorage("modClipboard") private var modClipboard = true
    @AppStorage("modActions") private var modActions = true
    @AppStorage("modCalendar") private var modCalendar = true
    @AppStorage("modDevices") private var modDevices = true
    @Namespace private var tabSpace

    private var tabs: [IslandTab] {
        var t: [IslandTab] = []
        if modMusic { t.append(.music) }
        if modCaffeine || modTimer || modStats || modToggles || (modBattery && battery.hasBattery) { t.append(.overview) }
        if modCalendar { t.append(.calendar) }
        if modDevices { t.append(.devices) }
        if modClipboard { t.append(.clipboard) }
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
                case .calendar: CalendarView()
                case .devices: DevicesView()
                case .clipboard: ClipboardView()
                case .actions: ActionsView()
                case nil:
                    VStack(spacing: 8) {
                        Text("Alle Module sind aus.").font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
                        PillButton(title: "Einstellungen öffnen") { SettingsWindow.show() }
                    }
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
            HStack(spacing: tabs.count > 5 ? 2 : 4) {
                ForEach(tabs) { tab in
                    Button { Haptics.tap(); state.tab = tab } label: {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: tabs.count > 5 ? 31 : 34, height: 24)
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

struct PillButton: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(.white.opacity(0.14), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: Übersicht

/// Übersicht: oben Koffein, Timer, Akku, Stats; darunter Schnell-Schalter.
struct OverviewView: View {
    @AppStorage("modTimer") private var modTimer = true
    @AppStorage("modCaffeine") private var modCaffeine = true
    @AppStorage("modBattery") private var modBattery = true
    @AppStorage("modStats") private var modStats = true
    @AppStorage("modToggles") private var modToggles = true
    @ObservedObject private var battery = Battery.shared

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
            if modCaffeine { CaffeineTile() }
            if modTimer { TimerTile() }
            if modBattery && battery.hasBattery { BatteryTile() }
            if modStats { StatsTile() }
            if modToggles {
                DarkModeTile()
                MuteTile()
                DisplayOffTile()
                SettingsTile()
            }
        }
        .frame(maxHeight: .infinity, alignment: .center)
    }
}

/// Basis jeder Kachel: flach, dunkelgrau, optional farbig.
struct Tile<Content: View>: View {
    var tint: Color? = nil
    var action: (() -> Void)? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        Button(action: { Haptics.tap(); action?() }) {
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(6)
        }
        .buttonStyle(TilePressStyle())
        .frame(height: 76)
        .background(tint.map { AnyShapeStyle($0.opacity(0.92)) } ?? AnyShapeStyle(Color.white.opacity(0.10)), in: shape)
        .clipShape(shape)
        .animation(.easeOut(duration: 0.2), value: tint != nil)
    }
}

struct TilePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

private func tileLabel(_ s: String) -> some View {
    Text(s).font(.system(size: 11, weight: .semibold)).lineLimit(1)
}

// MARK: Koffein

struct CaffeineTile: View {
    @ObservedObject private var caffeine = Caffeine.shared
    @AppStorage("activeHex") private var activeHex = "#30D158"

    var body: some View {
        Tile(tint: caffeine.active ? Color(hex: activeHex) : nil, action: { caffeine.toggle() }) {
            VStack(spacing: 4) {
                Image(systemName: caffeine.active ? "cup.and.heat.waves.fill" : "cup.and.saucer")
                    .font(.system(size: 21, weight: .medium))
                    .contentTransition(.symbolEffect(.replace))
                if caffeine.active, let end = caffeine.endDate, end > Date() {
                    Text(timerInterval: Date()...end, countsDown: true).monospacedDigit()
                        .font(.system(size: 11, weight: .semibold))
                } else {
                    tileLabel(caffeine.active ? "Wach" : "Koffein")
                }
            }
            .foregroundStyle(.white)
        }
        .contextMenu {
            Button("15 Minuten") { caffeine.turnOn(seconds: 15 * 60) }
            Button("30 Minuten") { caffeine.turnOn(seconds: 30 * 60) }
            Button("1 Stunde") { caffeine.turnOn(seconds: 3600) }
            Button("3 Stunden") { caffeine.turnOn(seconds: 3 * 3600) }
            Button("Unbegrenzt") { caffeine.turnOn(seconds: nil) }
            if caffeine.active { Divider(); Button("Ausschalten") { caffeine.turnOff() } }
        }
        .help("Klick: an/aus. Rechtsklick: Dauer wählen. Zeigt live, ob caffeinate läuft (auch aus dem Terminal).")
    }
}

// MARK: Timer

struct TimerTile: View {
    @ObservedObject private var timer = CountdownTimer.shared
    @AppStorage("accentHex") private var accentHex = "#0A84FF"
    @AppStorage("timerDefaultMinutes") private var defaultMin = 10

    var body: some View {
        Tile(tint: timer.running && !timer.isPaused ? Color(hex: accentHex) : nil, action: tap) {
            VStack(spacing: 4) {
                if timer.running {
                    Group {
                        if let rest = timer.pausedRemaining {
                            Text(formatTime(rest))
                        } else if let end = timer.endDate {
                            Text(timerInterval: Date()...max(end, Date().addingTimeInterval(1)), countsDown: true, showsHours: false)
                        }
                    }
                    .monospacedDigit().font(.system(size: 19, weight: .semibold))
                    tileLabel(timer.label).opacity(0.8)
                } else {
                    Image(systemName: "timer").font(.system(size: 21, weight: .medium))
                    tileLabel("\(defaultMin) Min")
                }
            }
            .foregroundStyle(.white)
        }
        .contextMenu {
            ForEach([5, 10, 15, 25, 30, 45, 60], id: \.self) { m in
                Button("\(m) Minuten") { timer.start(minutes: Double(m)) }
            }
            Divider()
            Button("Pomodoro starten") { timer.startPomodoro() }
            if timer.running {
                Divider()
                Button("+ 5 Minuten") { timer.add(minutes: 5) }
                Button(timer.isPaused ? "Fortsetzen" : "Pausieren") { timer.togglePause() }
                Button("Stoppen") { timer.stop() }
            }
        }
        .help("Klick: starten, dann pausieren/fortsetzen. Rechtsklick: Dauer, Pomodoro, +5 Min, Stoppen.")
    }

    private func tap() { timer.running ? timer.togglePause() : timer.startDefault() }
}

// MARK: Akku

struct BatteryTile: View {
    @ObservedObject private var battery = Battery.shared
    @AppStorage("activeHex") private var activeHex = "#30D158"

    var body: some View {
        Tile {
            VStack(spacing: 3) {
                ZStack {
                    Circle().stroke(.white.opacity(0.18), lineWidth: 4)
                    Circle().trim(from: 0, to: CGFloat(battery.percent) / 100)
                        .stroke(battery.percent <= 20 && !battery.pluggedIn ? Color.red : Color(hex: activeHex),
                                style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(battery.percent)").font(.system(size: 12, weight: .bold)).monospacedDigit()
                }
                .frame(width: 38, height: 38)
                HStack(spacing: 2) {
                    if battery.pluggedIn { Image(systemName: "bolt.fill").font(.system(size: 8)) }
                    tileLabel(battery.charging ? "Lädt" : (battery.pluggedIn ? "Netz" : "Akku"))
                }
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
            .padding(.horizontal, 4)
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

// MARK: Eigene Aktionen

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
                PillButton(title: "Aktion anlegen") { SettingsWindow.show(page: .actions) }
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

struct ActionTile: View {
    let item: ActionItem
    var body: some View {
        Tile(action: { item.run() }) {
            VStack(spacing: 4) {
                Image(systemName: item.symbol).font(.system(size: 21, weight: .medium))
                tileLabel(item.title)
            }
            .foregroundStyle(.white)
        }
    }
}

// MARK: Zwischenablage

struct ClipboardView: View {
    @ObservedObject private var clip = Clipboard.shared

    var body: some View {
        if clip.items.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "doc.on.clipboard").font(.system(size: 24, weight: .light))
                Text("Noch nichts kopiert").font(.system(size: 12, weight: .medium)).opacity(0.7)
                Text("Texte, die du kopierst, erscheinen hier. Passwörter werden ignoriert.")
                    .font(.system(size: 10)).opacity(0.45)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 6) {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 4) {
                        ForEach(clip.items) { ClipRow(item: $0) }
                    }
                }
                HStack {
                    Text("\(clip.items.count) Einträge · Klick kopiert erneut").font(.system(size: 10)).opacity(0.45)
                    Spacer()
                    Button("Leeren") { clip.clear() }.buttonStyle(.plain).font(.system(size: 10, weight: .semibold)).opacity(0.6)
                }
                .foregroundStyle(.white)
            }
        }
    }
}

struct ClipRow: View {
    let item: ClipItem
    @State private var hover = false
    @State private var copied = false

    var body: some View {
        Button {
            Haptics.tap()
            Clipboard.shared.copy(item)
            copied = true
        } label: {
            HStack(spacing: 8) {
                Text(item.preview).font(.system(size: 12)).lineLimit(1)
                Spacer(minLength: 8)
                if copied {
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .bold))
                } else {
                    Text(item.date, style: .relative).font(.system(size: 10)).opacity(0.4)
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(.white.opacity(hover ? 0.16 : 0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
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
                    .frame(width: 112, height: 112)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .shadow(color: .black.opacity(0.5), radius: 8, y: 3)
                    .onTapGesture { music.open() }
                    .help("Spotify öffnen")

                    VStack(alignment: .leading, spacing: 0) {
                        Text(music.title).font(.system(size: 16, weight: .semibold)).lineLimit(1)
                        Text(music.artist).font(.system(size: 13)).opacity(0.6).lineLimit(1).padding(.top, 2)
                        Spacer(minLength: 6)
                        progress
                        controls.padding(.top, 8)
                    }
                    .frame(height: 112)
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "music.note").font(.system(size: 26, weight: .light))
                    Text(music.running ? "Nichts spielt" : "Spotify ist nicht geöffnet").font(.system(size: 12, weight: .medium)).opacity(0.7)
                    if !music.running { PillButton(title: "Spotify öffnen") { music.open() } }
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
                Text(formatTime(pos * dur)).font(.system(size: 10)).monospacedDigit().opacity(0.55).frame(width: 34, alignment: .leading)
                GlassSlider(value: Binding(get: { pos }, set: { scrub = $0 }), tint: .white,
                            onCommit: { v in music.seek(to: v * dur); scrub = nil })
                Text("-" + formatTime(max(0, dur - pos * dur))).font(.system(size: 10)).monospacedDigit().opacity(0.55).frame(width: 38, alignment: .trailing)
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 34) {
            Button { Haptics.tap(); music.previous() } label: { Image(systemName: "backward.fill").font(.system(size: 17)) }
            Button { Haptics.tap(); music.playPause() } label: { Image(systemName: music.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 22)).frame(width: 26) }
            Button { Haptics.tap(); music.next() } label: { Image(systemName: "forward.fill").font(.system(size: 17)) }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }
}
