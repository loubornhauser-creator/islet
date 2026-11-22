import AppKit
import ImageIO

/// Spotify per AppleScript + verteilte Benachrichtigungen (kein Polling, kein API-Key).
final class Music: ObservableObject {
    static let shared = Music()
    static let bundleID = "com.spotify.client"

    @Published var running = false
    @Published var title = ""
    @Published var artist = ""
    @Published var album = ""
    @Published var isPlaying = false
    @Published var duration: Double = 0
    @Published var artwork: NSImage?

    private var posBase: Double = 0
    private var posDate = Date()
    private var artURL = ""
    private var enabled = false
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private let queue = DispatchQueue(label: "islet.spotify", qos: .utility)

    var hasTrack: Bool { !title.isEmpty }
    var position: Double {
        isPlaying ? min(duration, posBase + Date().timeIntervalSince(posDate)) : posBase
    }

    func start() {
        guard !enabled else { return }
        enabled = true
        let dn = DistributedNotificationCenter.default()
        let o1 = dn.addObserver(forName: .init("com.spotify.client.PlaybackStateChanged"), object: nil, queue: .main) { [weak self] n in
            self?.handle(n.userInfo)
        }
        observers.append((dn, o1))

        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            let o = ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] n in
                guard let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      app.bundleIdentifier == Music.bundleID else { return }
                self?.refresh()
            }
            observers.append((ws, o))
        }
        refresh()
    }

    func stop() {
        guard enabled else { return }
        enabled = false
        observers.forEach { $0.0.removeObserver($0.1) }
        observers.removeAll()
        running = false; title = ""; artist = ""; album = ""; isPlaying = false; artwork = nil; artURL = ""
    }

    // MARK: Zustand

    private var isSpotifyRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: Music.bundleID).isEmpty
    }

    func refresh() {
        running = isSpotifyRunning
        guard running else { title = ""; artist = ""; isPlaying = false; artwork = nil; artURL = ""; return }
        let script = """
        tell application "Spotify"
            if player state is stopped then return "stopped"
            set t to current track
            return (player state as string) & "§" & (name of t) & "§" & (artist of t) & "§" & (album of t) & "§" & (duration of t) & "§" & (player position) & "§" & (artwork url of t)
        end tell
        """
        run(script) { [weak self] out in
            guard let self, let out else { return }
            let p = out.components(separatedBy: "§")
            guard p.count >= 7 else { self.isPlaying = false; return }
            self.isPlaying = p[0] == "playing"
            self.title = p[1]; self.artist = p[2]; self.album = p[3]
            self.duration = (Double(p[4].replacingOccurrences(of: ",", with: ".")) ?? 0) / 1000
            self.posBase = Double(p[5].replacingOccurrences(of: ",", with: ".")) ?? 0
            self.posDate = Date()
            self.loadArtwork(p[6])
        }
    }

    private func handle(_ info: [AnyHashable: Any]?) {
        guard let info else { return }
        running = true
        let state = info["Player State"] as? String ?? ""
        let newTitle = info["Name"] as? String ?? ""
        let trackChanged = newTitle != title
        title = newTitle
        artist = info["Artist"] as? String ?? ""
        album = info["Album"] as? String ?? ""
        isPlaying = state == "Playing"
        duration = ((info["Duration"] as? NSNumber)?.doubleValue ?? 0) / 1000
        posBase = (info["Playback Position"] as? NSNumber)?.doubleValue ?? 0
        posDate = Date()
        if state == "Stopped" { title = ""; artist = ""; artwork = nil; artURL = "" }
        else if trackChanged || artwork == nil { fetchArtworkURL() }
    }

    private func fetchArtworkURL() {
        run("tell application \"Spotify\" to return artwork url of current track") { [weak self] url in
            if let url { self?.loadArtwork(url) }
        }
    }

    private func loadArtwork(_ url: String) {
        guard url != artURL, let u = URL(string: url), !url.isEmpty else { return }
        artURL = url
        URLSession.shared.dataTask(with: u) { [weak self] data, _, _ in
            guard let data,
                  let src = CGImageSourceCreateWithData(data as CFData, nil),
                  let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: 200,
                  ] as CFDictionary) else { return }
            let img = NSImage(cgImage: cg, size: NSSize(width: 100, height: 100))
            DispatchQueue.main.async { if self?.artURL == url { self?.artwork = img } }
        }.resume()
    }

    // MARK: Steuerung

    func playPause() { guard isSpotifyRunning else { open(); return }; isPlaying.toggle(); posBase = position; posDate = Date(); run("tell application \"Spotify\" to playpause") }
    func next() { command("next track") }
    func previous() { command("previous track") }
    func seek(to seconds: Double) {
        posBase = seconds; posDate = Date()
        command("set player position to \(Int(seconds))")
    }
    func open() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Music.bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    private func command(_ cmd: String) {
        guard isSpotifyRunning else { return }
        run("tell application \"Spotify\" to \(cmd)")
    }

    /// Führt AppleScript nur aus, wenn Spotify läuft (sonst würde macOS Spotify starten).
    private func run(_ source: String, completion: ((String?) -> Void)? = nil) {
        guard isSpotifyRunning else { completion?(nil); return }
        queue.async {
            var err: NSDictionary?
            let result = NSAppleScript(source: source)?.executeAndReturnError(&err)
            let s = result?.stringValue
            if let completion { DispatchQueue.main.async { completion(s) } }
        }
    }
}
