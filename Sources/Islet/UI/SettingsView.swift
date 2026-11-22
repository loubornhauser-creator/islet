import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            ModulesTab().tabItem { Label("Module", systemImage: "square.grid.2x2") }
            AppearanceTab().tabItem { Label("Aussehen", systemImage: "paintpalette") }
            HUDTab().tabItem { Label("HUD & Gesten", systemImage: "slider.vertical.3") }
            ActionsTab().tabItem { Label("Aktionen", systemImage: "bolt") }
        }
        .frame(width: 520, height: 460)
        .padding(12)
    }
}

private func colorBinding(_ hex: Binding<String>) -> Binding<Color> {
    Binding(get: { Color(hex: hex.wrappedValue) }, set: { hex.wrappedValue = $0.hex })
}

struct ModulesTab: View {
    @AppStorage("modMusic") private var music = true
    @AppStorage("modTimer") private var timer = true
    @AppStorage("modCaffeine") private var caffeine = true
    @AppStorage("modBattery") private var battery = true
    @AppStorage("modStats") private var stats = true
    @AppStorage("modHUD") private var hud = true
    @AppStorage("modGestures") private var gestures = true
    @AppStorage("modActions") private var actions = true
    @AppStorage("pomoWork") private var work = 25
    @AppStorage("pomoBreak") private var rest = 5

    var body: some View {
        Form {
            Section("Module an/aus (ein ausgeschaltetes Modul verbraucht nichts)") {
                Toggle("Spotify & Musik", isOn: $music)
                Toggle("Timer & Pomodoro", isOn: $timer)
                Toggle("Koffein-Button", isOn: $caffeine)
                Toggle("Akku & Laden", isOn: $battery)
                Toggle("Stats (CPU, GPU, RAM)", isOn: $stats)
                Toggle("Lautstärke/Helligkeit als Seiten-Bar", isOn: $hud)
                Toggle("Trackpad-Gesten am Rand", isOn: $gestures)
                Toggle("Eigene Aktionen", isOn: $actions)
            }
            Section("Pomodoro") {
                Stepper("Fokus: \(work) Min", value: $work, in: 1...120)
                Stepper("Pause: \(rest) Min", value: $rest, in: 1...60)
            }
        }
        .formStyle(.grouped)
    }
}

struct AppearanceTab: View {
    @AppStorage("accentHex") private var accent = "#0A84FF"
    @AppStorage("activeHex") private var active = "#30D158"
    @AppStorage("tintHex") private var tint = "#000000"
    @AppStorage("style") private var style = "solid"
    @AppStorage("glassStrength") private var strength = 0.55
    @AppStorage("cornerRadius") private var corner = 34.0
    @AppStorage("expandedWidth") private var width = 540.0
    @AppStorage("expandedHeight") private var height = 188.0
    @AppStorage("hoverExpand") private var hover = true
    @AppStorage("hoverDelay") private var delay = 0.12

    var body: some View {
        Form {
            Section("Farben") {
                ColorPicker("Akzent (Slider, Timer, Stats)", selection: colorBinding($accent), supportsOpacity: false)
                ColorPicker("Aktiv (Koffein an, Akku)", selection: colorBinding($active), supportsOpacity: false)
                ColorPicker("Insel-Grundfarbe", selection: colorBinding($tint), supportsOpacity: false)
                Picker("Stil", selection: $style) {
                    Text("Schwarz (wie iPhone)").tag("solid")
                    Text("Liquid Glass").tag("glass")
                }
                if style == "glass" {
                    LabeledContent("Tönung") { Slider(value: $strength, in: 0...1).frame(width: 200) }
                }
            }
            Section("Größe & Form") {
                LabeledContent("Breite \(Int(width))") { Slider(value: $width, in: 480...900, step: 10).frame(width: 200) }
                LabeledContent("Höhe \(Int(height))") { Slider(value: $height, in: 160...340, step: 2).frame(width: 200) }
                LabeledContent("Rundung \(Int(corner))") { Slider(value: $corner, in: 12...46).frame(width: 200) }
            }
            Section("Verhalten") {
                Toggle("Beim Überfahren aufklappen", isOn: $hover)
                LabeledContent("Verzögerung \(String(format: "%.2f", delay)) s") { Slider(value: $delay, in: 0...0.8).frame(width: 200) }
            }
            Section {
                Button("Auf Standard zurücksetzen") {
                    for k in ["accentHex", "activeHex", "tintHex", "style", "glassStrength", "cornerRadius", "expandedWidth", "expandedHeight", "hoverExpand", "hoverDelay"] {
                        UserDefaults.standard.set(Pref.defaults[k], forKey: k)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct HUDTab: View {
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
            Section("Seiten-Bar") {
                Picker("Seite", selection: $side) { Text("Rechts").tag("right"); Text("Links").tag("left") }
                LabeledContent("Anzeigedauer \(String(format: "%.1f", seconds)) s") { Slider(value: $seconds, in: 0.6...5).frame(width: 200) }
                Toggle("System-HUD ersetzen (Tasten abfangen)", isOn: $replace)
            }
            Section("Trackpad-Gesten") {
                Picker("Linker Rand", selection: $left) { Text("Lautstärke").tag("volume"); Text("Helligkeit").tag("brightness"); Text("Aus").tag("off") }
                Picker("Rechter Rand", selection: $right) { Text("Lautstärke").tag("volume"); Text("Helligkeit").tag("brightness"); Text("Aus").tag("off") }
                LabeledContent("Randbreite \(Int(edge * 100)) %") { Slider(value: $edge, in: 0.04...0.2).frame(width: 200) }
                LabeledContent("Empfindlichkeit \(String(format: "%.1f", sens))") { Slider(value: $sens, in: 0.4...3).frame(width: 200) }
            }
            Section("Berechtigung") {
                HStack {
                    Image(systemName: trusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(trusted ? .green : .orange)
                    Text(trusted ? "Bedienungshilfen erlaubt" : "Bedienungshilfen fehlen (für Tasten und Gesten nötig)")
                    Spacer()
                    if !trusted {
                        Button("Anfragen") { InputTap.requestPermission() }
                    }
                    Button("Neu prüfen") { trusted = InputTap.trusted }
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct ActionsTab: View {
    @State private var items = ActionItem.load()

    var body: some View {
        VStack(alignment: .leading) {
            Text("Eigene Kacheln im Panel: Befehl, App oder Link.").font(.callout).foregroundStyle(.secondary)
            List {
                ForEach($items) { $item in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: item.symbol).frame(width: 22)
                            TextField("Titel", text: $item.title)
                            TextField("SF Symbol", text: $item.symbol).frame(width: 130)
                        }
                        HStack {
                            Picker("", selection: $item.kind) {
                                ForEach(ActionItem.Kind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                            }.labelsHidden().frame(width: 90)
                            TextField(placeholder(item.kind), text: $item.value)
                            Button(role: .destructive) { items.removeAll { $0.id == item.id } } label: { Image(systemName: "trash") }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            HStack {
                Button { items.append(ActionItem()) } label: { Label("Aktion hinzufügen", systemImage: "plus") }
                Spacer()
            }
        }
        .padding()
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
