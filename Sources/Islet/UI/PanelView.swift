import SwiftUI

/// Ausgeklapptes Panel: links Musik, rechts ein Raster aus Kacheln. Jedes Modul ist abschaltbar.
struct PanelView: View {
    @AppStorage("modMusic") private var modMusic = true
    @AppStorage("modTimer") private var modTimer = true
    @AppStorage("modCaffeine") private var modCaffeine = true
    @AppStorage("modBattery") private var modBattery = true
    @AppStorage("modStats") private var modStats = true
    @AppStorage("modActions") private var modActions = true
    @AppStorage("actionsJSON") private var actionsJSON = "[]"
    @ObservedObject private var battery = Battery.shared

    private var actions: [ActionItem] {
        (try? JSONDecoder().decode([ActionItem].self, from: Data(actionsJSON.utf8))) ?? []
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if modMusic { MusicTile().frame(width: 292) }
            let cols = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
            LazyVGrid(columns: cols, spacing: 10) {
                if modCaffeine { CaffeineTile() }
                if modTimer { TimerTile() }
                if modBattery && battery.hasBattery { BatteryTile() }
                if modStats { StatsTile() }
                if modActions { ForEach(actions) { ActionTile(item: $0) } }
            }
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .padding(.top, IslandGeometry.shared.notchHeight > 0 ? 14 : 12)
        .padding([.horizontal, .bottom], 14)
    }
}

/// Basis jeder Kachel: quadratisch, Glas, optional farbig getönt.
struct Tile<Content: View>: View {
    var tint: Color? = nil
    var action: (() -> Void)? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        Button(action: { action?() }) {
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(8)
        }
        .buttonStyle(TilePressStyle())
        .frame(height: 84)
        .modifier(GlassBackground(shape: shape, strength: tint == nil ? 0.15 : 0.7, tint: tint ?? .white, interactive: true))
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

struct MusicTile: View {
    @ObservedObject private var music = Music.shared
    @ObservedObject private var audio = AudioControl.shared
    @AppStorage("accentHex") private var accentHex = "#0A84FF"
    @State private var scrub: Double? = nil

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)
        VStack(alignment: .leading, spacing: 8) {
            if music.running && music.hasTrack {
                HStack(spacing: 11) {
                    Group {
                        if let art = music.artwork { Image(nsImage: art).resizable().scaledToFill() }
                        else { Image(systemName: "music.note").font(.title2).frame(maxWidth: .infinity, maxHeight: .infinity).background(.white.opacity(0.12)) }
                    }
                    .frame(width: 62, height: 62)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(music.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                        Text(music.artist).font(.system(size: 12)).opacity(0.7).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                progress
                controls
            } else {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "music.note").font(.system(size: 26, weight: .light))
                    Text(music.running ? "Nichts spielt" : "Spotify ist nicht geöffnet").font(.system(size: 12, weight: .medium)).opacity(0.75)
                    if !music.running { Button("Spotify öffnen") { music.open() }.buttonStyle(.plain).font(.system(size: 12, weight: .semibold)).foregroundStyle(Color(hex: accentHex)) }
                }
                .frame(maxWidth: .infinity)
                Spacer()
            }
            volume
        }
        .foregroundStyle(.white)
        .padding(12)
        .frame(maxHeight: .infinity, alignment: .top)
        .modifier(GlassBackground(shape: shape, strength: 0.15, tint: .white))
        .clipShape(shape)
    }

    private var progress: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let dur = max(1, music.duration)
            let pos = scrub ?? (music.position / dur)
            HStack(spacing: 6) {
                Text(fmt(pos * dur)).font(.system(size: 9)).monospacedDigit().opacity(0.7)
                GlassSlider(value: Binding(get: { pos }, set: { scrub = $0 }), tint: .white,
                            onCommit: { v in music.seek(to: v * dur); scrub = nil })
                Text(fmt(dur)).font(.system(size: 9)).monospacedDigit().opacity(0.7)
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 26) {
            Spacer()
            Button { music.previous() } label: { Image(systemName: "backward.fill") }
            Button { music.playPause() } label: { Image(systemName: music.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 20)) }
            Button { music.next() } label: { Image(systemName: "forward.fill") }
            Spacer()
        }
        .buttonStyle(.plain).font(.system(size: 16))
    }

    private var volume: some View {
        HStack(spacing: 7) {
            Image(systemName: audio.muted || audio.volume == 0 ? "speaker.slash.fill" : "speaker.fill").font(.system(size: 10)).opacity(0.7).frame(width: 14)
            GlassSlider(value: Binding(get: { Double(audio.volume) }, set: { audio.setVolume(Float($0)) }), tint: Color(hex: accentHex))
            Image(systemName: "speaker.wave.3.fill").font(.system(size: 10)).opacity(0.7)
        }
    }

    private func fmt(_ s: Double) -> String {
        let t = Int(max(0, s))
        return String(format: "%d:%02d", t / 60, t % 60)
    }
}
