import SwiftUI
import ServiceManagement
import UniformTypeIdentifiers
import EventKit
import AVFoundation

struct SettingsView: View {
    @ObservedObject private var nav = SettingsNav.shared

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(spacing: 0) {
                Text(nav.page.title).font(.system(size: 22, weight: .bold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 26).padding(.top, 34).padding(.bottom, 4)
                detail.id(nav.page)
            }
        }
        .frame(width: 820, height: 600)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Image(systemName: "capsule.fill").font(.system(size: 14, weight: .bold))
                Text("Islet").font(.system(size: 15, weight: .bold))
            }
            .padding(.horizontal, 12).padding(.top, 34).padding(.bottom, 14)
            ForEach(SettingsPage.allCases) { page in
                Button { nav.page = page } label: {
                    HStack(spacing: 9) {
                        Image(systemName: page.symbol)
                            .font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(page.color.gradient, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        Text(page.title).font(.system(size: 13))
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(nav.page == page ? Color.accentColor.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 8)
        .frame(width: 210)
        .background(Color(nsColor: .underPageBackgroundColor).opacity(0.5))
    }

    @ViewBuilder
    private var detail: some View {
        switch nav.page {
        case .general: GeneralPage()
        case .modules: ModulesPage()
        case .appearance: AppearancePage()
        case .tools: ToolsPage()
        case .calendarDevices: CalendarDevicesPage()
        case .face: FacePage()
        case .volume: VolumePage()
        case .actions: ActionsPage()
        case .permissions: PermissionsPage()
        case .about: AboutPage()
        }
    }
}

// MARK: Allgemein

struct GeneralPage: View {
    @AppStorage("showMenuBarIcon") private var menuIcon = true
    @AppStorage("display") private var display = "notch"
    @AppStorage("hotkey") private var hotkey = "ctrlOptSpace"
    @AppStorage("hideInFullscreen") private var hideFullscreen = false
    @AppStorage("haptics") private var haptics = true
    @AppStorage("hoverExpand") private var hover = true
    @AppStorage("hoverDelay") private var delay = 0.12
    @AppStorage("collapseDelay") private var collapseDelay = 0.28
    @AppStorage("startTab") private var startTab = "last"
    @AppStorage("animStyle") private var animStyle = "island"
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @State private var confirmReset = false
    @State private var note: String?

    var body: some View {
        Form {
            Section("Start") {
                ToggleRow(title: "Beim Anmelden starten", subtitle: loginError ?? "Islet startet automatisch mit dem Mac.", isOn: Binding(
                    get: { launchAtLogin },
                    set: { setLaunch($0) }))
                ToggleRow(title: "Symbol in der Menüleiste", subtitle: "Ohne Symbol öffnest du die Einstellungen über das Zahnrad der Insel.", isOn: $menuIcon)
            }
            Section("Insel") {
                Picker("Bildschirm", selection: $display) {
                    Text("Notch-Display (Standard)").tag("notch")
                    Text("Hauptbildschirm").tag("main")
                    Text("Bildschirm mit der Maus").tag("mouse")
                }
                Picker("Tastenkürzel zum Öffnen", selection: $hotkey) {
                    ForEach(Hotkey.options, id: \.id) { Text($0.label).tag($0.id) }
                }
                Picker("Start-Ansicht", selection: $startTab) {
                    Text("Zuletzt benutzte").tag("last")
                    Text("Musik").tag("music")
                    Text("Übersicht").tag("overview")
                }
                ToggleRow(title: "In Vollbild-Apps ausblenden", subtitle: "Aus: Die Insel bleibt auch in Vollbild-Apps sichtbar und bedienbar.", isOn: $hideFullscreen)
                ToggleRow(title: "Haptisches Feedback", subtitle: "Leichtes Klopfen auf dem Trackpad beim Aufklappen und Antippen.", isOn: $haptics)
            }
            Section {
                Picker("Öffnen-Animation", selection: $animStyle) {
                    Text("Aus der Insel wachsen (Standard)").tag("island")
                    Text("Sanft, ohne Nachfedern").tag("smooth")
                    Text("Schnell").tag("quick")
                }
                ToggleRow(title: "Beim Überfahren aufklappen", subtitle: "Aus: Die Insel öffnet nur per Klick oder Tastenkürzel.", isOn: $hover)
                SliderRow(title: "Aufklappen nach", value: $delay, range: 0...0.8, format: { String(format: "%.2f s", $0) })
                    .disabled(!hover)
                SliderRow(title: "Zuklappen nach", value: $collapseDelay, range: 0.05...1.5, format: { String(format: "%.2f s", $0) })
            } header: { Text("Verhalten") } footer: {
                Text("Die Insel startet immer als Notch, wächst von dort nach unten und zur Seite, und der Inhalt blendet danach von oben nach unten ein.")
            }
            Section("Einstellungen sichern") {
                HStack {
                    Button("Exportieren …") { export() }
                    Button("Importieren …") { importFile() }
                    Spacer()
                    Button("Alles zurücksetzen", role: .destructive) { confirmReset = true }
                }
                if let note { Text(note).font(.caption).foregroundStyle(.secondary) }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Alle Einstellungen auf Standard zurücksetzen?", isPresented: $confirmReset) {
            Button("Zurücksetzen", role: .destructive) {
                Pref.reset(Pref.allKeys)
                note = "Alles zurückgesetzt."
            }
        } message: { Text("Das betrifft Module, Farben, Größen und eigene Aktionen.") }
    }

    private func setLaunch(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "Nicht möglich: \(error.localizedDescription)"
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func export() {
        guard let data = Pref.exportJSON() else { return }
        let p = NSSavePanel()
        p.allowedContentTypes = [.json]
        p.nameFieldStringValue = "islet-einstellungen.json"
        if p.runModal() == .OK, let url = p.url {
            do { try data.write(to: url); note = "Exportiert nach \(url.lastPathComponent)." }
            catch { note = "Export fehlgeschlagen: \(error.localizedDescription)" }
        }
    }

    private func importFile() {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.json]
        if p.runModal() == .OK, let url = p.url, let data = try? Data(contentsOf: url) {
            note = Pref.importJSON(data) ? "Importiert aus \(url.lastPathComponent)." : "Datei konnte nicht gelesen werden."
        }
    }
}

// MARK: Module

struct ModulesPage: View {
    var body: some View {
        Form {
            Section {
                ModuleRow(symbol: "music.note", color: .pink, title: "Musik", subtitle: "Spotify: Cover, Titel, Steuerung, Fortschritt.", key: "modMusic")
                ModuleRow(symbol: "cup.and.saucer.fill", color: .orange, title: "Koffein", subtitle: "Mac wach halten, mit Live-Status von caffeinate.", key: "modCaffeine")
                ModuleRow(symbol: "timer", color: .blue, title: "Timer & Pomodoro", subtitle: "Mit Pause, +5 Min und Anzeige in der Insel.", key: "modTimer")
                ModuleRow(symbol: "battery.100.bolt", color: .green, title: "Akku & Laden", subtitle: "Ladestand, Hinweis beim Anstecken.", key: "modBattery")
                ModuleRow(symbol: "cpu", color: .indigo, title: "Stats", subtitle: "CPU, GPU, RAM. Läuft nur bei offener Insel.", key: "modStats")
                ModuleRow(symbol: "switch.2", color: .teal, title: "Schnell-Schalter", subtitle: "Dunkel/Hell, Stumm, Display aus, Einstellungen.", key: "modToggles")
                ModuleRow(symbol: "calendar", color: .red, title: "Kalender", subtitle: "Nächste Termine, Countdown in der kompakten Insel.", key: "modCalendar")
                ModuleRow(symbol: "airpodspro", color: .mint, title: "Geräte & AirPods", subtitle: "Bluetooth-Geräte mit Akkustand, Hinweis beim Verbinden.", key: "modDevices")
                ModuleRow(symbol: "sparkles", color: .orange, title: "Claude-Limits", subtitle: "Session- und Wochen-Limit live, über die Anmeldung von Claude Code.", key: "modClaude", defaultOn: false)
                ModuleRow(symbol: "faceid", color: .green, title: "Face Unlock", subtitle: "Entsperren per Kamera (Komfort-Funktion), Einrichtung unter „Face Unlock“.", key: "modFace", defaultOn: false)
                ModuleRow(symbol: "doc.on.clipboard.fill", color: .brown, title: "Zwischenablage", subtitle: "Verlauf der letzten Texte, nur im Arbeitsspeicher.", key: "modClipboard")
                ModuleRow(symbol: "mic.fill", color: .red, title: "Mikrofon & Kamera", subtitle: "Orange/grüner Punkt, wenn eins benutzt wird.", key: "modIndicators")
                ModuleRow(symbol: "speaker.wave.3.fill", color: .cyan, title: "Lautstärke & Helligkeit", subtitle: "Seiten-Bar statt System-HUD.", key: "modHUD")
                ModuleRow(symbol: "hand.draw.fill", color: .purple, title: "Trackpad-Gesten", subtitle: "Am Rand wischen für Lautstärke/Helligkeit.", key: "modGestures")
                ModuleRow(symbol: "bolt.fill", color: .yellow, title: "Eigene Aktionen", subtitle: "Deine Befehle, Apps und Links als Kacheln.", key: "modActions")
            } footer: {
                Text("Ein ausgeschaltetes Modul läuft nicht und verbraucht weder Speicher noch Rechenzeit.")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: Aussehen

struct AppearancePage: View {
    @AppStorage("accentHex") private var accent = "#0A84FF"
    @AppStorage("activeHex") private var active = "#30D158"
    @AppStorage("tintHex") private var tint = "#000000"
    @AppStorage("style") private var style = "solid"
    @AppStorage("glassStrength") private var strength = 0.55
    @AppStorage("cornerRadius") private var corner = 34.0
    @AppStorage("expandedWidth") private var width = 560.0
    @AppStorage("expandedHeight") private var height = 226.0
    @AppStorage("compactMusic") private var cMusic = true
    @AppStorage("compactCaffeine") private var cCaffeine = true
    @AppStorage("compactTimer") private var cTimer = true
    @AppStorage("compactCharge") private var cCharge = true
    @AppStorage("compactIndicators") private var cInd = true
    @AppStorage("compactCalendar") private var cCal = true
    @AppStorage("compactDevices") private var cDev = true
    @AppStorage("liveSideItems") private var liveSide = true
    @ObservedObject private var geo = IslandGeometry.shared

    var body: some View {
        Form {
            Section {
                IslandPreview().padding(.vertical, 4)
            }
            Section("Farbvorlagen") {
                HStack(spacing: 16) { ForEach(Theme.all) { ThemeSwatch(theme: $0) } }
                    .frame(maxWidth: .infinity).padding(.vertical, 4)
            }
            Section("Farben") {
                ColorRow(title: "Akzent", subtitle: "Regler, Timer, Statistik, Musik-Symbole", hex: $accent)
                ColorRow(title: "Aktiv", subtitle: "Koffein an, Akku, Lade-Hinweis", hex: $active)
                ColorRow(title: "Grundfarbe", subtitle: "Hintergrund der geöffneten Insel. Die kompakte Insel bleibt neben der Notch schwarz.", hex: $tint)
                Picker("Stil", selection: $style) {
                    Text("Schwarz").tag("solid")
                    Text("Liquid Glass").tag("glass")
                }
                .pickerStyle(.segmented)
                if style == "glass" {
                    SliderRow(title: "Tönung", value: $strength, range: 0...1, format: { "\(Int($0 * 100)) %" })
                }
            }
            Section("Größe & Form") {
                SliderRow(title: "Breite", value: $width, range: max(500, geo.minExpandedWidth)...max(900, geo.minExpandedWidth + 40), step: 10, format: { "\(Int($0)) pt" })
                SliderRow(title: "Höhe", value: $height, range: geo.minExpandedHeight...max(360, geo.minExpandedHeight + 40), step: 2, format: { "\(Int($0)) pt" })
                SliderRow(title: "Rundung", value: $corner, range: 12...46, format: { "\(Int($0)) pt" })
            }
            Section {
                ToggleRow(title: "Live-Anzeigen neben der Notch", subtitle: "Musik, Timer, Koffein usw. erscheinen neben der Notch. Ohne laufende Anzeige ist die Insel exakt so groß wie die Notch. Aus: nie breiter als die Notch.", isOn: $liveSide)
                Group {
                    ToggleRow(title: "Cover bei laufender Musik", isOn: $cMusic)
                    ToggleRow(title: "Koffein-Symbol, wenn aktiv", isOn: $cCaffeine)
                    ToggleRow(title: "Timer-Restzeit", isOn: $cTimer)
                    ToggleRow(title: "Lade-Hinweis beim Anstecken", isOn: $cCharge)
                    ToggleRow(title: "Mikrofon- und Kamera-Punkt", isOn: $cInd)
                    ToggleRow(title: "Termin-Countdown", subtitle: "Kurz vor Beginn eines Termins.", isOn: $cCal)
                    ToggleRow(title: "Neu verbundene AirPods mit Akkustand", isOn: $cDev)
                }
                .disabled(!liveSide)
            } header: { Text("Geschlossene Insel") } footer: {
                Text("Mindestgröße der geöffneten Insel: \(Int(geo.minExpandedWidth)) × \(Int(geo.minExpandedHeight)) pt. Darunter würde die echte Notch in die Reiter ragen, deshalb lässt sich die Insel nicht kleiner stellen.")
            }
            Section {
                Button("Aussehen zurücksetzen") {
                    Pref.reset(["accentHex", "activeHex", "tintHex", "style", "glassStrength", "cornerRadius", "expandedWidth", "expandedHeight",
                                "compactMusic", "compactCaffeine", "compactTimer", "compactCharge", "compactIndicators", "compactCalendar", "compactDevices", "liveSideItems"])
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: Koffein & Timer

struct ToolsPage: View {
    @AppStorage("caffeineMode") private var mode = "full"
    @AppStorage("caffeineDefaultMinutes") private var cafMin = 0
    @AppStorage("timerDefaultMinutes") private var timerMin = 10
    @AppStorage("timerSound") private var sound = true
    @AppStorage("pomoWork") private var work = 25
    @AppStorage("pomoBreak") private var rest = 5
    @AppStorage("clipboardMax") private var clipMax = 10
    @AppStorage("cleaningMinutes") private var cleanMin = 2
    @AppStorage("cleaningTrackpad") private var cleanPad = true
    @AppStorage("cleaningDim") private var cleanDim = true
    @AppStorage("modClaude") private var claude = false

    var body: some View {
        Form {
            Section {
                Picker("Modus", selection: $mode) {
                    Text("Display und System wach").tag("full")
                    Text("Nur System wach (Display darf ausgehen)").tag("system")
                }
                Picker("Standard-Dauer", selection: $cafMin) {
                    Text("Unbegrenzt").tag(0)
                    Text("15 Minuten").tag(15)
                    Text("30 Minuten").tag(30)
                    Text("1 Stunde").tag(60)
                    Text("2 Stunden").tag(120)
                    Text("4 Stunden").tag(240)
                    Text("8 Stunden").tag(480)
                }
            } header: { Text("Koffein") } footer: {
                Text("Der Button startet `caffeinate` mit diesen Werten und ist grün, solange irgendein caffeinate läuft, auch wenn du es selbst im Terminal gestartet hast. Rechtsklick wählt eine andere Dauer.")
            }
            Section("Timer") {
                Stepper("Standard-Dauer: \(timerMin) Min", value: $timerMin, in: 1...180)
                ToggleRow(title: "Ton beim Ablauf", isOn: $sound)
            }
            Section("Pomodoro") {
                Stepper("Fokus: \(work) Min", value: $work, in: 1...120)
                Stepper("Pause: \(rest) Min", value: $rest, in: 1...60)
            }
            Section("Zwischenablage") {
                Stepper("Einträge im Verlauf: \(clipMax)", value: $clipMax, in: 3...30)
            }
            Section {
                Picker("Standard-Dauer", selection: $cleanMin) {
                    ForEach([1, 2, 3, 5, 10], id: \.self) { Text("\($0) Minute\($0 == 1 ? "" : "n")").tag($0) }
                }
                ToggleRow(title: "Auch das Trackpad sperren", isOn: $cleanPad)
                ToggleRow(title: "Bildschirm abdunkeln", subtitle: "Zeigt Restzeit groß an und verhindert versehentliche Klicks.", isOn: $cleanDim)
            } header: { Text("Tastatur reinigen") } footer: {
                Text("In der Übersicht auf „Reinigen“ tippen. Tastatur und Trackpad sind dann gesperrt, bis die Zeit abgelaufen ist oder du Esc 3 Sekunden hältst. Braucht die Bedienungshilfen-Freigabe.")
            }
            Section {
                ToggleRow(title: "Claude-Limits anzeigen", subtitle: "Reiter mit Session- und Wochen-Limit (aktualisiert sich alle 2 Minuten).", isOn: $claude)
            } header: { Text("Claude") } footer: {
                Text("Islet liest die Anmeldung, die Claude Code im Schlüsselbund ablegt (macOS fragt einmal um Erlaubnis), und ruft damit dieselben Zahlen wie unter claude.ai/settings/usage von api.anthropic.com ab. Es wird nichts geschrieben. Die Schnittstelle ist nicht offiziell dokumentiert und kann sich ändern.")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: Kalender & Geräte

struct CalendarDevicesPage: View {
    @AppStorage("calendarDays") private var days = 2
    @AppStorage("calendarSoonMinutes") private var soon = 10
    @AppStorage("calendarAllDay") private var allDay = true
    @AppStorage("calendarReminders") private var reminders = true
    @ObservedObject private var cal = CalendarModule.shared
    @ObservedObject private var dev = Devices.shared
    @State private var calendars: [CalInfo] = []
    @State private var excluded = Set(CalendarModule.excludedList())

    var body: some View {
        Form {
            Section("Termine") {
                if cal.status != .fullAccess {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text(cal.status == .notDetermined ? "Islet braucht deine Erlaubnis für den Kalender." : "Kalender-Zugriff fehlt. Bitte in den Systemeinstellungen erlauben.")
                        Spacer()
                        if cal.status == .notDetermined { Button("Erlauben") { cal.requestAccess() } }
                        else { Button("Öffnen") { openPane() } }
                    }
                }
                Picker("Zeitraum", selection: $days) {
                    Text("Nur heute").tag(1)
                    Text("Heute und morgen").tag(2)
                    Text("3 Tage").tag(3)
                    Text("7 Tage").tag(7)
                }
                Picker("Countdown in der Insel ab", selection: $soon) {
                    ForEach([5, 10, 15, 30], id: \.self) { Text("\($0) Minuten vorher").tag($0) }
                }
                ToggleRow(title: "Ganztägige Termine anzeigen", isOn: $allDay)
                ToggleRow(title: "Erinnerungen anzeigen", subtitle: "Offene Apple-Erinnerungen mit Fälligkeit, überfällige oben. Abhaken geht direkt in der Insel.", isOn: $reminders)
                if reminders && cal.reminderStatus != .fullAccess {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text(cal.reminderStatus == .notDetermined ? "Für Erinnerungen fehlt noch deine Erlaubnis." : "Zugriff auf Erinnerungen fehlt (Systemeinstellungen → Datenschutz → Erinnerungen).")
                        Spacer()
                        if cal.reminderStatus == .notDetermined { Button("Erlauben") { cal.requestRemindersAccess() } }
                    }
                }
            }
            if !calendars.isEmpty {
                Section("Angezeigte Kalender und Listen") {
                    ForEach(calendars) { c in
                        Toggle(isOn: Binding(
                            get: { !excluded.contains(c.id) },
                            set: { on in
                                if on { excluded.remove(c.id) } else { excluded.insert(c.id) }
                                CalendarModule.setExcluded(Array(excluded))
                            })) {
                            HStack(spacing: 8) {
                                Circle().fill(c.color).frame(width: 10, height: 10)
                                Text(c.title)
                                if !c.source.isEmpty { Text(c.source).font(.caption).foregroundStyle(.secondary) }
                                if c.isReminderList { Image(systemName: "checklist").font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                    }
                }
            }
            Section {
                if dev.connected.isEmpty {
                    Text("Keine Bluetooth-Geräte verbunden.").foregroundStyle(.secondary)
                } else {
                    ForEach(dev.connected) { d in
                        LabeledContent {
                            Text(d.batteries.map { "\($0.label) \($0.percent) %" }.joined(separator: "  ·  ")).foregroundStyle(.secondary).font(.caption)
                        } label: {
                            Label(d.name, systemImage: d.symbol)
                        }
                    }
                }
                Button(dev.refreshing ? "Lese Akkustand …" : "Jetzt aktualisieren") { dev.refresh(force: true) }
                    .disabled(dev.refreshing)
            } header: { Text("Bluetooth-Geräte") } footer: {
                Text("Islet erkennt neue Verbindungen von AirPods und Co. und zeigt kurz Symbol und Akkustand neben der Notch. Den Akkustand liest es über die Systeminformationen, dafür ist keine Bluetooth-Berechtigung nötig.")
            }
        }
        .formStyle(.grouped)
        .onAppear { calendars = cal.allCalendars(); dev.refresh() }
    }

    private func openPane() {
        if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") { NSWorkspace.shared.open(u) }
    }
}

// MARK: Lautstärke & Gesten

struct VolumePage: View {
    @AppStorage("hudSide") private var side = "right"
    @AppStorage("hudSeconds") private var seconds = 1.6
    @AppStorage("hudReplaceSystem") private var replace = true
    @AppStorage("gestureEdge") private var edge = 0.08
    @AppStorage("gestureSensitivity") private var sens = 1.2
    @AppStorage("gestureLeft") private var left = "volume"
    @AppStorage("gestureRight") private var right = "brightness"
    @State private var trusted = InputTap.trusted

    var body: some View {
        Form {
            if !trusted {
                Section {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text("Für Tasten und Gesten fehlt die Bedienungshilfen-Freigabe.")
                        Spacer()
                        Button("Freigeben") { InputTap.requestPermission() }
                    }
                }
            }
            Section("Seiten-Bar") {
                Picker("Seite", selection: $side) { Text("Rechts").tag("right"); Text("Links").tag("left") }
                    .pickerStyle(.segmented)
                SliderRow(title: "Anzeigedauer", value: $seconds, range: 0.6...5, format: { String(format: "%.1f s", $0) })
                ToggleRow(title: "System-Anzeige ersetzen", subtitle: "Fängt die Lautstärke- und Helligkeitstasten ab (Bedienungshilfen nötig). ⇧⌥ + Taste = feine Schritte.", isOn: $replace)
            }
            Section {
                Picker("Linker Rand", selection: $left) { gestureOptions }
                Picker("Rechter Rand", selection: $right) { gestureOptions }
                SliderRow(title: "Randbreite", value: $edge, range: 0.04...0.2, format: { "\(Int($0 * 100)) %" })
                SliderRow(title: "Empfindlichkeit", value: $sens, range: 0.4...3, format: { String(format: "%.1f×", $0) })
            } header: { Text("Trackpad-Gesten") } footer: {
                Text("Mit einem Finger am Rand des Trackpads nach oben oder unten wischen. Das Scrollen wird dabei unterdrückt.")
            }
        }
        .formStyle(.grouped)
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            trusted = InputTap.trusted
            InputTap.startIfNeeded()
        }
    }

    @ViewBuilder private var gestureOptions: some View {
        Text("Lautstärke").tag("volume")
        Text("Helligkeit").tag("brightness")
        Text("Aus").tag("off")
    }
}

// MARK: Aktionen

struct ActionsPage: View {
    @State private var items = ActionItem.load()

    private static let templates: [ActionItem] = [
        ActionItem(title: "Screenshot", symbol: "camera.viewfinder", kind: .shell, value: "screencapture -ic"),
        ActionItem(title: "Terminal", symbol: "terminal", kind: .app, value: "Terminal"),
        ActionItem(title: "Safari", symbol: "safari", kind: .app, value: "Safari"),
        ActionItem(title: "Notizen", symbol: "note.text", kind: .app, value: "Notes"),
        ActionItem(title: "Downloads", symbol: "arrow.down.circle", kind: .shell, value: "open ~/Downloads"),
        ActionItem(title: "Systemeinst.", symbol: "gearshape", kind: .app, value: "System Settings"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Jede Aktion erscheint als Kachel im Reiter ⚡︎ der Insel. Ziehen sortiert um.")
                .font(.callout).foregroundStyle(.secondary).padding(.horizontal, 26).padding(.top, 6)
            List {
                ForEach($items) { $item in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Image(systemName: item.symbol).frame(width: 24).foregroundStyle(.secondary)
                            TextField("Titel", text: $item.title)
                            TextField("SF Symbol", text: $item.symbol).frame(width: 140).foregroundStyle(.secondary)
                        }
                        HStack(spacing: 8) {
                            Picker("", selection: $item.kind) {
                                ForEach(ActionItem.Kind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                            }
                            .labelsHidden().frame(width: 100)
                            TextField(placeholder(item.kind), text: $item.value)
                            Button(role: .destructive) { items.removeAll { $0.id == item.id } } label: { Image(systemName: "trash") }
                                .buttonStyle(.borderless)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onMove { items.move(fromOffsets: $0, toOffset: $1) }
            }
            .listStyle(.inset)
            HStack {
                Button { items.append(ActionItem()) } label: { Label("Neue Aktion", systemImage: "plus") }
                Menu("Vorlage hinzufügen") {
                    ForEach(Self.templates) { t in
                        Button { var n = t; n.id = UUID(); items.append(n) } label: { Label(t.title, systemImage: t.symbol) }
                    }
                }
                .fixedSize()
                Spacer()
                Text("\(items.count) Aktionen").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 26).padding(.bottom, 16)
        }
        .onChange(of: items) { ActionItem.save($0) }
    }

    private func placeholder(_ k: ActionItem.Kind) -> String {
        switch k {
        case .shell: return "z. B. open -a Safari"
        case .app: return "App-Name oder Pfad"
        case .url: return "https://…"
        }
    }
}

// MARK: Berechtigungen

struct PermissionsPage: View {
    @State private var trusted = InputTap.trusted
    @State private var spotify = Perm.automation("com.spotify.client")
    @State private var events = Perm.automation("com.apple.systemevents")
    @State private var calStatus = EKEventStore.authorizationStatus(for: .event)
    @State private var remStatus = EKEventStore.authorizationStatus(for: .reminder)
    @State private var camStatus = AVCaptureDevice.authorizationStatus(for: .video)

    var body: some View {
        Form {
            Section {
                row(symbol: "hand.raised.fill", title: "Bedienungshilfen", detail: "Lautstärke-/Helligkeitstasten abfangen und Scrollen bei Gesten unterdrücken.",
                    ok: trusted, label: trusted ? "Erlaubt" : "Fehlt") {
                    InputTap.requestPermission()
                } open: { open("Privacy_Accessibility") }
                row(symbol: "music.note", title: "Automation: Spotify", detail: "Titel, Cover und Steuerung. Spotify muss dafür laufen.",
                    ok: spotify == .granted, label: spotify.label) {
                    spotify = Perm.automation("com.spotify.client", ask: true)
                } open: { open("Privacy_Automation") }
                row(symbol: "moon.fill", title: "Automation: System Events", detail: "Nur für den Dunkel/Hell-Schalter. Die Abfrage erscheint beim ersten Umschalten.",
                    ok: events == .granted, label: events.label, canAsk: events != .notRunning) {
                    events = Perm.automation("com.apple.systemevents", ask: true)
                } open: { open("Privacy_Automation") }
                row(symbol: "calendar", title: "Kalender", detail: "Nächste Termine in der Insel. Islet liest nur und ändert nichts.",
                    ok: calStatus == .fullAccess, label: calLabel, canAsk: calStatus == .notDetermined) {
                    CalendarModule.shared.requestAccess()
                } open: { open("Privacy_Calendars") }
                row(symbol: "checklist", title: "Erinnerungen", detail: "Offene Erinnerungen in der Insel, Abhaken auf deinen Klick.",
                    ok: remStatus == .fullAccess, label: remStatus == .fullAccess ? "Erlaubt" : (remStatus == .notDetermined ? "Noch nicht gefragt" : "Abgelehnt"), canAsk: remStatus == .notDetermined) {
                    CalendarModule.shared.requestRemindersAccess()
                } open: { open("Privacy_Reminders") }
                row(symbol: "camera.fill", title: "Kamera", detail: "Nur für Face Unlock, nur während eines Scans.",
                    ok: camStatus == .authorized, label: camStatus == .authorized ? "Erlaubt" : (camStatus == .notDetermined ? "Noch nicht gefragt" : "Abgelehnt"), canAsk: camStatus == .notDetermined) {
                    AVCaptureDevice.requestAccess(for: .video) { _ in }
                } open: { open("Privacy_Camera") }
            } footer: {
                Text("Islet ist nur lokal signiert. Nach einem Neubau kann macOS die Freigaben neu verlangen. Dann in den Systemeinstellungen den Schalter für Islet aus- und wieder einschalten.")
            }
        }
        .formStyle(.grouped)
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in refresh() }
    }

    private func refresh() {
        trusted = InputTap.trusted
        InputTap.startIfNeeded()
        spotify = Perm.automation("com.spotify.client")
        events = Perm.automation("com.apple.systemevents")
        calStatus = EKEventStore.authorizationStatus(for: .event)
        remStatus = EKEventStore.authorizationStatus(for: .reminder)
        camStatus = AVCaptureDevice.authorizationStatus(for: .video)
    }

    private var calLabel: String {
        switch calStatus {
        case .fullAccess: return "Erlaubt"
        case .notDetermined: return "Noch nicht gefragt"
        case .writeOnly: return "Nur Schreiben"
        default: return "Abgelehnt"
        }
    }

    private func open(_ pane: String) {
        if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") { NSWorkspace.shared.open(u) }
    }

    private func row(symbol: String, title: String, detail: String, ok: Bool, label: String, canAsk: Bool = true,
                     ask: @escaping () -> Void, open: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 15)).frame(width: 26).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 5) {
                Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill").foregroundStyle(ok ? .green : .orange)
                Text(label).font(.caption).foregroundStyle(.secondary)
            }
            if !ok && canAsk { Button("Anfragen", action: ask) }
            Button("Öffnen", action: open)
        }
        .padding(.vertical, 3)
    }
}

// MARK: Über

struct AboutPage: View {
    @State private var mb = memoryFootprintMB()
    private var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0" }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(systemName: "capsule.fill").font(.system(size: 26)).frame(width: 56, height: 56)
                        .foregroundStyle(.white).background(Color.black.gradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Islet").font(.system(size: 18, weight: .bold))
                        Text("Version \(version) · macOS \(ProcessInfo.processInfo.operatingSystemVersion.majorVersion)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
            Section("Verbrauch jetzt") {
                LabeledContent("Arbeitsspeicher dieser App", value: String(format: "%.0f MB", mb))
                Text("Gemessen wie in der Aktivitätsanzeige (Speicherbedarf). Ein ausgeschaltetes Modul verbraucht nichts.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Open Source") {
                Text("Islet ist freie Software unter der MIT-Lizenz, geschrieben in Swift und SwiftUI ohne Fremdbibliotheken. Atoll steht unter GPL; Islet ist eine unabhängige Neuentwicklung ohne Atoll-Code.")
                    .font(.callout)
                Text("Helligkeit und Trackpad-Gesten nutzen private Apple-Schnittstellen, die zur Laufzeit geladen werden.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in mb = memoryFootprintMB() }
    }
}
