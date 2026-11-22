import SwiftUI
import AppKit

/// Einführung beim ersten Start. Später jederzeit über Einstellungen → Über Islet oder das Menüleisten-Symbol erreichbar.
final class TutorialWindow: NSObject, NSWindowDelegate {
    private static let shared = TutorialWindow()
    private var window: NSWindow?

    static func show() { shared.present() }

    private func present() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 520),
                             styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            w.titleVisibility = .hidden
            w.titlebarAppearsTransparent = true
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.contentView = NSHostingView(rootView: TutorialView { [weak self] in self?.window?.close() })
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        UserDefaults.standard.set(true, forKey: "tutorialDone")
        window?.contentView = nil
        window?.delegate = nil
        window = nil
    }
}

private struct TutRow: View {
    let symbol: String
    let color: Color
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: symbol).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(color.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13.5, weight: .semibold))
                Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

struct TutorialView: View {
    let onFinish: () -> Void
    @State private var page: Int
    private let last = 5

    init(startPage: Int = 0, onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
        _page = State(initialValue: startPage)
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                switch page {
                case 0: welcome
                case 1: operate
                case 2: tabs
                case 3: background
                case 4: permissions
                default: finish
                }
            }
            .id(page)
            .transition(.opacity)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 42).padding(.top, 44)

            HStack(spacing: 7) {
                ForEach(0...last, id: \.self) { i in
                    Capsule().fill(i == page ? Color.accentColor : Color.primary.opacity(0.18))
                        .frame(width: i == page ? 18 : 7, height: 7)
                }
            }
            .padding(.bottom, 14)

            HStack {
                if page == 0 { Button("Überspringen") { onFinish() }.buttonStyle(.plain).foregroundStyle(.secondary) }
                else { Button("Zurück") { go(-1) } }
                Spacer()
                if page < last { Button("Weiter") { go(1) }.keyboardShortcut(.defaultAction).controlSize(.large) }
                else {
                    Button("Einstellungen öffnen") { onFinish(); SettingsWindow.show(page: .modules) }
                    Button("Los geht’s") { onFinish() }.keyboardShortcut(.defaultAction).controlSize(.large)
                }
            }
            .padding(.horizontal, 30).padding(.bottom, 24)
        }
        .frame(width: 640, height: 520)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func go(_ d: Int) { withAnimation(.easeInOut(duration: 0.2)) { page = min(last, max(0, page + d)) } }

    // MARK: Seiten

    private var welcome: some View {
        VStack(spacing: 16) {
            Image(systemName: "capsule.fill").font(.system(size: 40, weight: .bold)).foregroundStyle(.white)
                .frame(width: 92, height: 92)
                .background(Color.black.gradient, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            Text("Willkommen bei Islet").font(.system(size: 28, weight: .bold))
            Text("Islet macht aus der Notch deines Macs eine Dynamic Island: Musik, Timer, Termine, Geräte und vieles mehr, direkt am oberen Bildschirmrand.")
                .multilineTextAlignment(.center).font(.system(size: 15)).foregroundStyle(.secondary)
            Text("Diese kurze Tour zeigt dir in einer Minute, was möglich ist. Alles lässt sich später in den Einstellungen ein- und ausschalten und anpassen.")
                .multilineTextAlignment(.center).font(.callout).foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var operate: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("So bedienst du die Insel").font(.system(size: 22, weight: .bold))
            TutRow(symbol: "cursorarrow.motionlines", color: .blue, title: "Maus an die Notch",
                   text: "Fahre mit der Maus an die Notch, die Insel wächst auf. Wenn du weggehst, klappt sie wieder zu.")
            TutRow(symbol: "hand.tap.fill", color: .indigo, title: "Klicken hält sie offen",
                   text: "Ein Klick auf die Insel lässt sie offen. Noch ein Klick (oder das Tastenkürzel) schließt sie.")
            TutRow(symbol: "keyboard", color: .gray, title: "Tastenkürzel ⌃⌥ Leertaste",
                   text: "Öffnet und schließt die Insel von der Tastatur aus. Das Kürzel änderst du unter Einstellungen → Allgemein.")
            TutRow(symbol: "square.grid.2x2.fill", color: .teal, title: "Reiter oben",
                   text: "Links und rechts neben der Notch wechselst du zwischen Musik, Übersicht, Kalender und mehr.")
            TutRow(symbol: "gearshape.fill", color: .orange, title: "Zahnrad für die Einstellungen",
                   text: "Oder das Kapsel-Symbol in der Menüleiste. Dort stellst du Module, Farben und Größe ein.")
            Spacer()
        }
    }

    private var tabs: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("Die Reiter").font(.system(size: 22, weight: .bold))
            TutRow(symbol: "music.note", color: .pink, title: "Musik", text: "Spotify: Cover, Titel, Steuerung und Zeitleiste.")
            TutRow(symbol: "square.grid.2x2.fill", color: .indigo, title: "Übersicht",
                   text: "Koffein, Timer, Akku, Statistik und Schnell-Schalter (Dunkel/Hell, Stumm, Display aus, Tastatur reinigen).")
            TutRow(symbol: "calendar", color: .red, title: "Kalender", text: "Nächste Termine und Apple-Erinnerungen, abhaken per Klick.")
            TutRow(symbol: "headphones", color: .mint, title: "Geräte", text: "AirPods, Maus und Tastatur mit Akkustand.")
            TutRow(symbol: "sparkles", color: .orange, title: "Claude", text: "Dein Claude-Limit live. Muss einmal aktiviert werden.")
            TutRow(symbol: "doc.on.clipboard.fill", color: .brown, title: "Zwischenablage und Aktionen", text: "Verlauf der kopierten Texte und deine eigenen Kacheln.")
            Spacer()
        }
    }

    private var background: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Das passiert im Hintergrund").font(.system(size: 22, weight: .bold))
            TutRow(symbol: "capsule", color: .blue, title: "Live-Anzeigen neben der Notch",
                   text: "Läuft Musik, ein Timer oder Koffein, zeigt die geschlossene Insel es an. Ohne Anzeige ist sie exakt so groß wie die Notch.")
            TutRow(symbol: "speaker.wave.3.fill", color: .cyan, title: "Lautstärke und Helligkeit",
                   text: "Eine Seiten-Bar wie auf iPhone und iPad. Am Trackpad-Rand wischen regelt sie auch.")
            TutRow(symbol: "mic.fill", color: .red, title: "Mikrofon und Kamera",
                   text: "Ein orangener oder grüner Punkt zeigt, wenn eine App sie benutzt.")
            TutRow(symbol: "faceid", color: .green, title: "Face Unlock (optional)",
                   text: "Entsperrt den Mac mit deinem Gesicht. Eine Komfort-Funktion, kein Ersatz für Face ID. Einrichtung unter Einstellungen → Face Unlock.")
            Spacer()
        }
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Freigaben").font(.system(size: 22, weight: .bold))
            Text("Islet fragt nur, wenn eine Funktion es braucht. Du kannst jederzeit Nein sagen, dann bleibt nur diese Funktion aus.")
                .font(.callout).foregroundStyle(.secondary)
            TutRow(symbol: "calendar", color: .red, title: "Kalender und Erinnerungen", text: "Für den Reiter Kalender. Islet liest nur, außer wenn du eine Erinnerung abhakst.")
            TutRow(symbol: "hand.raised.fill", color: .green, title: "Bedienungshilfen", text: "Für Lautstärke-Tasten, Trackpad-Gesten, Tastatur reinigen und das Passwort-Tippen bei Face Unlock.")
            TutRow(symbol: "camera.fill", color: .gray, title: "Kamera", text: "Nur für Face Unlock und nur während eines Scans. Es werden keine Bilder gespeichert.")
            TutRow(symbol: "applescript", color: .orange, title: "Automation", text: "Für Spotify und den Dunkel/Hell-Schalter.")
            Text("Den Stand siehst du unter Einstellungen → Berechtigungen.").font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var finish: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 54)).foregroundStyle(.green)
            Text("Fertig").font(.system(size: 28, weight: .bold))
            Text("Unter Einstellungen → Module kannst du jede Funktion ein- und ausschalten. Neben jedem Modul steht ein ⓘ: Dort findest du eine Beschreibung und eine Schritt-für-Schritt-Anleitung.")
                .multilineTextAlignment(.center).font(.system(size: 15)).foregroundStyle(.secondary)
            Text("Diese Einführung findest du später unter Einstellungen → Über Islet wieder.")
                .multilineTextAlignment(.center).font(.callout).foregroundStyle(.secondary)
            Spacer()
        }
    }
}
