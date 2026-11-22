import SwiftUI

/// Schnell-Schalter in der Übersicht (iPad-Kontrollzentrum-Gefühl).

struct DarkModeTile: View {
    @State private var dark = Self.isDark

    static var isDark: Bool { UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark" }

    var body: some View {
        Tile(tint: dark ? Color(white: 0.28) : nil, action: toggle) {
            VStack(spacing: 4) {
                Image(systemName: dark ? "moon.fill" : "sun.max.fill").font(.system(size: 21, weight: .medium))
                    .contentTransition(.symbolEffect(.replace))
                Text(dark ? "Dunkel" : "Hell").font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(.white)
        }
        .onAppear { dark = Self.isDark }
        .help("Dunkel/Hell umschalten (braucht einmalig die Automation-Erlaubnis für „System Events“)")
    }

    private func toggle() {
        dark.toggle()
        DispatchQueue.global(qos: .userInitiated).async {
            var err: NSDictionary?
            NSAppleScript(source: "tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode")?
                .executeAndReturnError(&err)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { dark = Self.isDark }
        }
    }
}

struct MuteTile: View {
    @ObservedObject private var audio = AudioControl.shared

    var body: some View {
        Tile(tint: audio.muted ? Color(hex: "#FF453A") : nil, action: { audio.toggleMute() }) {
            VStack(spacing: 4) {
                Image(systemName: audio.muted ? "speaker.slash.fill" : "speaker.wave.2.fill").font(.system(size: 21, weight: .medium))
                    .contentTransition(.symbolEffect(.replace))
                Text(audio.muted ? "Stumm" : "\(Int((audio.volume * 100).rounded())) %").font(.system(size: 11, weight: .semibold)).monospacedDigit()
            }
            .foregroundStyle(.white)
        }
        .help("Stummschalten. Zeigt die aktuelle Lautstärke.")
    }
}

struct DisplayOffTile: View {
    var body: some View {
        Tile(action: {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
            p.arguments = ["displaysleepnow"]
            try? p.run()
        }) {
            VStack(spacing: 4) {
                Image(systemName: "display").font(.system(size: 21, weight: .medium))
                Text("Display aus").font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(.white)
        }
        .help("Bildschirm sofort ausschalten (sperrt, wenn „Kennwort sofort“ aktiv ist)")
    }
}

struct SettingsTile: View {
    var body: some View {
        Tile(action: { SettingsWindow.show() }) {
            VStack(spacing: 4) {
                Image(systemName: "slider.horizontal.3").font(.system(size: 21, weight: .medium))
                Text("Einstellungen").font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(.white)
        }
    }
}

struct CleaningTile: View {
    @ObservedObject private var lock = CleaningLock.shared

    var body: some View {
        Tile(tint: lock.active ? Color(hex: "#FF9F0A") : nil, action: { if lock.active { lock.stop() } else { lock.start() } }) {
            VStack(spacing: 4) {
                Image(systemName: "keyboard").font(.system(size: 21, weight: .medium))
                Text("Reinigen").font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(.white)
        }
        .contextMenu {
            ForEach([1, 2, 3, 5], id: \.self) { m in
                Button("\(m) Minute\(m == 1 ? "" : "n") sperren") { CleaningLock.shared.start(seconds: Double(m) * 60) }
            }
        }
        .help("Sperrt Tastatur und Trackpad zum Abwischen. Esc 3 Sekunden halten beendet es sofort.")
    }
}
