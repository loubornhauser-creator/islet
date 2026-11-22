import SwiftUI
import AVFoundation

/// Einstellungsseite „Face Unlock“.
struct FacePage: View {
    @ObservedObject private var face = FaceUnlock.shared
    @AppStorage("modFace") private var enabled = false
    @AppStorage("faceTypePassword") private var typePassword = false
    @AppStorage("faceOnWake") private var onWake = true
    @AppStorage("faceOnScreensaver") private var onSaver = true
    @AppStorage("faceOnActivity") private var onActivity = true
    @AppStorage("faceOnLock") private var onLock = false
    @AppStorage("faceScanSeconds") private var seconds = 10.0
    @AppStorage("faceStrictness") private var strictness = "normal"
    @AppStorage("faceCamera") private var cameraID = "auto"
    @AppStorage("faceShowIsland") private var showIsland = true
    @AppStorage("faceLockScreenOverlay") private var overlay = true
    @State private var showSetup = false
    @State private var confirmDelete = false
    @State private var trusted = InputTap.trusted
    @State private var cam = AVCaptureDevice.authorizationStatus(for: .video)

    var body: some View {
        Form {
            Section {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text("Komfort-Funktion, kein Ersatz für Face ID. Die Mac-Kamera sieht nur ein normales Farbbild ohne Tiefe, ein Foto oder Video von dir könnte sie täuschen. Dein Passwort funktioniert immer.")
                        .font(.callout)
                }
            }
            Section("Status") {
                statusRow("Gesicht eingelernt", face.enrolled)
                statusRow("Kamera erlaubt", cam == .authorized)
                statusRow("Bedienungshilfen (zum Tippen)", trusted)
            }
            Section {
                ToggleRow(title: "Face Unlock aktiv", subtitle: "Die Kamera läuft nur während eines Scans, die grüne LED zeigt es.", isOn: $enabled)
                    .disabled(!face.enrolled)
                HStack {
                    Button(face.enrolled ? "Neu einlernen …" : "Einrichten …") { showSetup = true }
                    Button("Testen") { face.testScan() }.disabled(!face.enrolled)
                    Spacer()
                    Button("Löschen", role: .destructive) { confirmDelete = true }.disabled(!face.enrolled)
                }
            }
            Section {
                ToggleRow(title: "Passwort wirklich tippen", subtitle: face.enrolled ? "Aus = Probelauf: erkennt dich und zeigt die Animation, tippt aber nichts. Erst einschalten, wenn die Auslöser am Sperrbildschirm stimmen." : "Zuerst Gesicht einlernen.", isOn: $typePassword)
                    .disabled(!face.enrolled)
            } header: { Text("Entsperren") } footer: {
                Text("Islet tippt das Passwort nur, wenn der Bildschirm wirklich gesperrt ist, nie in andere Apps, und höchstens zweimal, damit dein Account nicht gesperrt wird. Nach einem Neustart (FileVault) musst du einmal von Hand entsperren.")
            }
            Section("Auslöser") {
                ToggleRow(title: "Beim Aufwachen des Bildschirms", isOn: $onWake)
                ToggleRow(title: "Wenn der Bildschirmschoner endet", isOn: $onSaver)
                ToggleRow(title: "Bei Mausbewegung oder Taste am Sperrbildschirm", isOn: $onActivity)
                ToggleRow(title: "Sofort beim Sperren", subtitle: "Scannt direkt nach dem Sperren, nützlich zum Testen.", isOn: $onLock)
                SliderRow(title: "Scan-Dauer", value: $seconds, range: 4...20, step: 1, format: { "\(Int($0)) s" })
            }
            Section("Erkennung") {
                Picker("Strenge", selection: $strictness) {
                    ForEach(FaceMatcher.Strictness.allCases, id: \.rawValue) { Text($0.label).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                Picker("Kamera", selection: $cameraID) {
                    Text("Automatisch (eingebaut, sonst extern)").tag("auto")
                    ForEach(FaceCamera.devices(), id: \.uniqueID) { Text($0.localizedName).tag($0.uniqueID) }
                }
                if face.phase == .scanning {
                    LabeledContent("Treffer jetzt") { ProgressView(value: Double(face.score)).frame(width: 160) }
                }
            }
            Section("Anzeige") {
                ToggleRow(title: "Animation in der Notch", isOn: $showIsland)
                ToggleRow(title: "Über dem Sperrbildschirm anzeigen (experimentell)", subtitle: "Nutzt eine private macOS-Funktion. Ohne sie läuft die Erkennung trotzdem, nur die Animation fehlt am Sperrbildschirm.", isOn: $overlay)
            }
            if !face.log.isEmpty {
                Section {
                    ForEach(face.log.prefix(10), id: \.self) { Text($0).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary) }
                    Button("Protokolldatei im Finder zeigen") { NSWorkspace.shared.activateFileViewerSelecting([FaceLog.url]) }
                } header: { Text("Protokoll") } footer: {
                    Text("Nur Ereignisse und Zeiten, keine Bilder und keine Passwörter. Hilft zu sehen, wo beim Entsperren Zeit verloren geht.")
                }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showSetup) { FaceSetupView { showSetup = false; face.reloadCredentials() } }
        .confirmationDialog("Gesicht und Passwort löschen?", isPresented: $confirmDelete) {
            Button("Löschen", role: .destructive) { face.forgetEverything(); enabled = false; typePassword = false }
        } message: { Text("Beides wird aus dem Schlüsselbund entfernt. Face Unlock wird ausgeschaltet.") }
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            trusted = InputTap.trusted
            cam = AVCaptureDevice.authorizationStatus(for: .video)
        }
    }

    private func statusRow(_ title: String, _ ok: Bool) -> some View {
        HStack {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill").foregroundStyle(ok ? .green : .orange)
            Text(title)
            Spacer()
            Text(ok ? "OK" : "Fehlt").foregroundStyle(.secondary).font(.caption)
        }
    }
}
