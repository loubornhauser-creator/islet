import SwiftUI

/// Beschreibung und Anleitung zu einem Modul. Wird im ⓘ-Popover (Einstellungen → Module) und in der Einführung gezeigt.
struct ModuleDoc: Identifiable {
    let id: String          // Einstellungs-Schlüssel des Moduls, z. B. "modMusic"
    let symbol: String
    let color: Color
    let title: String
    let summary: String
    let steps: [String]
    let needs: String?
}

enum ModuleDocs {
    static func doc(for key: String) -> ModuleDoc? { all.first { $0.id == key } }

    static let all: [ModuleDoc] = [
        ModuleDoc(id: "modMusic", symbol: "music.note", color: .pink, title: "Musik",
                  summary: "Zeigt, was in Spotify läuft, und steuert die Wiedergabe.",
                  steps: ["Spotify öffnen und etwas abspielen.",
                          "Die Insel öffnen (Maus an die Notch) und den Reiter ♪ wählen.",
                          "Zurück, Pause und Weiter tippen. Auf die Zeitleiste klicken, um zu spulen.",
                          "Ein Klick auf das Cover öffnet Spotify.",
                          "Bei laufender Musik zeigt die geschlossene Insel das Cover neben der Notch."],
                  needs: "Automation für Spotify. macOS fragt beim ersten Zugriff."),
        ModuleDoc(id: "modCaffeine", symbol: "cup.and.saucer.fill", color: .orange, title: "Koffein",
                  summary: "Hält den Mac wach, wie der Terminal-Befehl „caffeinate“. Die Kachel zeigt live, ob er gerade läuft.",
                  steps: ["In der Übersicht die Kachel „Koffein“ antippen: Der Mac bleibt wach, die Kachel wird grün.",
                          "Rechtsklick wählt eine Dauer (15 Minuten bis unbegrenzt), die Restzeit wird angezeigt.",
                          "Läuft irgendwo im Terminal ein „caffeinate“, wird die Kachel ebenfalls grün.",
                          "Nochmal tippen schaltet wieder aus."],
                  needs: nil),
        ModuleDoc(id: "modTimer", symbol: "timer", color: .blue, title: "Timer & Pomodoro",
                  summary: "Ein Timer mit Pause, der auch in der geschlossenen Insel läuft.",
                  steps: ["In der Übersicht die Kachel „Timer“ tippen startet die Standard-Dauer (änderbar unter Koffein & Timer).",
                          "Nochmal tippen pausiert, erneut tippen setzt fort.",
                          "Rechtsklick: andere Dauer, Pomodoro (Fokus und Pause im Wechsel), +5 Minuten oder Stoppen.",
                          "Die Restzeit steht neben der Notch. Am Ende klappt die Insel kurz auf, dazu gibt es einen Ton."],
                  needs: nil),
        ModuleDoc(id: "modBattery", symbol: "battery.100.bolt", color: .green, title: "Akku & Laden",
                  summary: "Ladestand als Kachel und ein kurzer Hinweis beim Anstecken.",
                  steps: ["Die Kachel „Akku“ in der Übersicht zeigt Prozent und ob geladen wird.",
                          "Beim Anstecken des Netzteils erscheint kurz ein Blitz mit Prozent neben der Notch."],
                  needs: nil),
        ModuleDoc(id: "modStats", symbol: "cpu", color: .indigo, title: "Stats",
                  summary: "CPU, GPU und Arbeitsspeicher als drei Balken.",
                  steps: ["Die Kachel steht in der Übersicht.",
                          "Gemessen wird nur, solange die Insel offen ist. Im Leerlauf kostet es nichts."],
                  needs: nil),
        ModuleDoc(id: "modToggles", symbol: "switch.2", color: .teal, title: "Schnell-Schalter",
                  summary: "Dunkel/Hell, Stumm, Display aus und Tastatur reinigen mit einem Tipp.",
                  steps: ["Die Kacheln stehen in der Übersicht, zweite Reihe.",
                          "Dunkel/Hell wechselt das Erscheinungsbild des Macs.",
                          "Display aus schaltet den Bildschirm sofort aus.",
                          "Reinigen sperrt Tastatur und Trackpad, damit du den Mac abwischen kannst. Die Restzeit läuft groß auf dem Bildschirm. Esc 3 Sekunden gedrückt halten beendet es sofort."],
                  needs: "Dunkel/Hell: Automation für „System Events“. Reinigen: Bedienungshilfen."),
        ModuleDoc(id: "modCalendar", symbol: "calendar", color: .red, title: "Kalender & Erinnerungen",
                  summary: "Deine nächsten Termine und offenen Apple-Erinnerungen.",
                  steps: ["Der Reiter „Kalender“ zeigt Termine und Erinnerungen, überfällige oben in Rot.",
                          "Den Kreis neben einer Erinnerung antippen: erledigt.",
                          "Ein Klick auf einen Termin öffnet den Kalender.",
                          "Kurz vor einem Termin zählt die geschlossene Insel herunter.",
                          "Zeitraum, Kalender und Listen stellst du unter Kalender & Geräte ein."],
                  needs: "Kalender und Erinnerungen. macOS fragt beim ersten Start. Islet liest nur, außer beim Abhaken."),
        ModuleDoc(id: "modDevices", symbol: "airpodspro", color: .mint, title: "Geräte & AirPods",
                  summary: "Verbundene Bluetooth-Geräte mit Akkustand.",
                  steps: ["Der Reiter „Geräte“ listet AirPods (links, rechts, Hülle), Maus, Tastatur und mehr mit Prozent.",
                          "Verbindest du AirPods, erscheinen Symbol und Akkustand kurz neben der Notch.",
                          "Der Akkustand wird alle 60 Sekunden aktualisiert, solange der Reiter offen ist."],
                  needs: nil),
        ModuleDoc(id: "modIndicators", symbol: "mic.fill", color: .red, title: "Mikrofon & Kamera",
                  summary: "Ein Punkt neben der Notch zeigt, wenn eine App Mikrofon oder Kamera benutzt.",
                  steps: ["Orange: das Mikrofon ist in Gebrauch. Grün: die Kamera.",
                          "Das erscheint von selbst, es gibt nichts einzustellen."],
                  needs: nil),
        ModuleDoc(id: "modClaude", symbol: "sparkles", color: .orange, title: "Claude-Limits",
                  summary: "Zeigt dein Claude-Nutzungslimit live: Session (5 Stunden) und Woche.",
                  steps: ["Den Reiter ✦ öffnen und „Aktivieren“ tippen.",
                          "macOS fragt einmal nach Zugriff auf die Anmeldung von Claude Code. Das ist gewollt, Islet liest damit nur die Limits bei api.anthropic.com ab.",
                          "Du siehst Prozent, Farbe und die Zeit bis zum Reset.",
                          "Ist die Anmeldung abgelaufen, starte Claude Code kurz, danach aktualisiert sich die Anzeige."],
                  needs: "Claude Code muss auf dem Mac angemeldet sein. Die Schnittstelle ist nicht offiziell dokumentiert."),
        ModuleDoc(id: "modClipboard", symbol: "doc.on.clipboard.fill", color: .brown, title: "Zwischenablage",
                  summary: "Ein Verlauf der zuletzt kopierten Texte.",
                  steps: ["Alles, was du als Text kopierst, erscheint im Reiter ⎘.",
                          "Ein Klick auf einen Eintrag kopiert ihn erneut.",
                          "Passwörter aus Passwort-Managern werden ignoriert. Nichts wird auf die Festplatte geschrieben."],
                  needs: nil),
        ModuleDoc(id: "modHUD", symbol: "speaker.wave.3.fill", color: .cyan, title: "Lautstärke & Helligkeit",
                  summary: "Eine Seiten-Bar wie auf iPhone und iPad ersetzt die System-Anzeige.",
                  steps: ["Drücke die Lautstärke- oder Helligkeitstasten: Am Bildschirmrand erscheint die Bar.",
                          "⇧⌥ gedrückt halten und Taste drücken: feine Schritte.",
                          "Seite, Anzeigedauer und ob die System-Anzeige ersetzt wird, stellst du unter Lautstärke & Gesten ein."],
                  needs: "Bedienungshilfen, damit die Tasten abgefangen werden können."),
        ModuleDoc(id: "modGestures", symbol: "hand.draw.fill", color: .purple, title: "Trackpad-Gesten",
                  summary: "Am Rand des Trackpads wischen regelt Lautstärke oder Helligkeit.",
                  steps: ["Lege einen Finger an den linken oder rechten Rand des Trackpads und wische nach oben oder unten.",
                          "Standard: links Lautstärke, rechts Helligkeit. Du kannst es vertauschen.",
                          "Randbreite und Empfindlichkeit sind einstellbar, das Scrollen wird währenddessen unterdrückt."],
                  needs: "Bedienungshilfen."),
        ModuleDoc(id: "modActions", symbol: "bolt.fill", color: .yellow, title: "Eigene Aktionen",
                  summary: "Deine eigenen Kacheln: ein Befehl, eine App oder ein Link, mit einem Tipp.",
                  steps: ["Öffne Einstellungen → Aktionen und tippe „Neue Aktion“ oder „Vorlage hinzufügen“.",
                          "Wähle Befehl (Terminal), App oder Link, gib Titel und Symbol an.",
                          "Im Reiter ⚡︎ erscheinen die Aktionen als Kacheln. Ein Klick führt sie aus.",
                          "Mit Ziehen sortierst du die Liste um."],
                  needs: nil),
        ModuleDoc(id: "modFace", symbol: "faceid", color: .green, title: "Face Unlock",
                  summary: "Entsperrt den Mac mit deinem Gesicht. Eine Komfort-Funktion, kein Ersatz für Face ID.",
                  steps: ["Einstellungen → Face Unlock → „Einrichten“: Passwort bestätigen, Gesicht einlernen.",
                          "„Face Unlock aktiv“ einschalten. Zuerst läuft ein Probelauf: Islet erkennt dich und zeigt die Animation, tippt aber nichts.",
                          "Mac sperren (⌃⌘Q) und in die Kamera schauen: Die Notch zeigt „Suche dein Gesicht“, dann „Gesicht erkannt“.",
                          "Passt alles, schalte „Passwort wirklich tippen“ ein.",
                          "Stelle die Strenge auf „Normal“ oder „Streng“, wenn andere nicht durchkommen sollen."],
                  needs: "Kamera und Bedienungshilfen (zum Tippen). Die Mac-Kamera hat keine Tiefensensorik, ein Foto könnte sie täuschen."),
    ]
}

/// Inhalt des ⓘ-Popovers.
struct ModuleInfoView: View {
    let doc: ModuleDoc

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: doc.symbol)
                    .font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(doc.color.gradient, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(doc.title).font(.system(size: 16, weight: .bold))
                    Text(doc.summary).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Divider()
            Text("So funktioniert es").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(doc.steps.enumerated()), id: \.offset) { i, step in
                    HStack(alignment: .top, spacing: 9) {
                        Text("\(i + 1)").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 18, height: 18).background(Color.accentColor, in: Circle())
                        Text(step).font(.callout).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if let needs = doc.needs {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "hand.raised.fill").foregroundStyle(.orange).font(.system(size: 12))
                    Text(needs).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .padding(18)
        .frame(width: 380)
    }
}
