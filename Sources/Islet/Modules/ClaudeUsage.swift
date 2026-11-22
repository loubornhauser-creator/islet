import Foundation
import Security

struct UsageWindow: Equatable {
    let title: String
    /// 0...100
    let percent: Double
    let resetsAt: Date?
}

/// Zeigt die Claude-Limits (Session 5 Stunden, Woche) live an.
/// Quelle: dieselben Zahlen wie unter claude.ai → Einstellungen → Nutzung. Islet liest dafür die Anmeldung, die
/// Claude Code im Schlüsselbund ablegt (macOS fragt dabei einmal um Erlaubnis), und fragt api.anthropic.com ab.
/// Das ist eine nicht offiziell dokumentierte Schnittstelle und kann sich ändern. Es wird nur gelesen, nie geschrieben.
final class ClaudeUsage: ObservableObject {
    static let shared = ClaudeUsage()

    enum State: Equatable { case off, loading, ok, noLogin, expired, denied, offline, failed(String) }

    @Published var state: State = .off
    @Published var windows: [UsageWindow] = []
    @Published var plan = ""
    @Published var updated: Date?

    private var lastFetch = Date.distantPast
    private var timer: Timer?
    private var busy = false

    func start() {
        guard timer == nil else { return }
        refresh(force: true)
        let t = Timer(timeInterval: 120, repeats: true) { [weak self] _ in self?.refresh() }
        t.tolerance = 20
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate(); timer = nil
        windows = []; state = .off; updated = nil
    }

    func refresh(force: Bool = false) {
        guard timer != nil, !busy else { return }
        if !force, Date().timeIntervalSince(lastFetch) < 25 { return }
        lastFetch = Date(); busy = true
        if windows.isEmpty { state = .loading }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let result = Self.fetch()
            DispatchQueue.main.async {
                guard let self else { return }
                self.busy = false
                switch result {
                case .success(let r):
                    self.windows = r.windows; self.plan = r.plan; self.updated = Date(); self.state = .ok
                case .failure(let e):
                    self.state = e.state
                }
            }
        }
    }

    // MARK: Abruf

    private struct Failure: Error { let state: State }

    private static func credentials() -> Result<(token: String, plan: String, expires: Date?), Failure> {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: "Claude Code-credentials",
                                kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var out: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &out)
        if status == errSecItemNotFound { return .failure(Failure(state: .noLogin)) }
        if status != errSecSuccess { return .failure(Failure(state: .denied)) }
        guard let data = out as? Data,
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let oauth = obj["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String else { return .failure(Failure(state: .noLogin)) }
        let expires = (oauth["expiresAt"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }
        let plan = (oauth["subscriptionType"] as? String)?.capitalized ?? ""
        return .success((token, plan, expires))
    }

    private static func fetch() -> Result<(windows: [UsageWindow], plan: String), Failure> {
        let creds: (token: String, plan: String, expires: Date?)
        switch credentials() { case .success(let c): creds = c; case .failure(let f): return .failure(f) }
        if let e = creds.expires, e < Date() { return .failure(Failure(state: .expired)) }

        var req = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!, timeoutInterval: 12)
        req.setValue("Bearer \(creds.token)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let sem = DispatchSemaphore(value: 0)
        var body: Data?, code = 0, netError: Error?
        URLSession(configuration: .ephemeral).dataTask(with: req) { d, r, e in
            body = d; code = (r as? HTTPURLResponse)?.statusCode ?? 0; netError = e; sem.signal()
        }.resume()
        sem.wait()

        if netError != nil { return .failure(Failure(state: .offline)) }
        if code == 401 || code == 403 { return .failure(Failure(state: .expired)) }
        guard code == 200, let body, let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] else {
            return .failure(Failure(state: .failed("HTTP \(code)")))
        }

        func window(_ key: String, _ title: String) -> UsageWindow? {
            guard let w = json[key] as? [String: Any], let u = w["utilization"] as? Double else { return nil }
            return UsageWindow(title: title, percent: u, resetsAt: (w["resets_at"] as? String).flatMap(parseDate))
        }
        let list = [window("five_hour", "Session (5 Stunden)"), window("seven_day", "Woche (7 Tage)"),
                    window("seven_day_opus", "Woche Opus"), window("seven_day_sonnet", "Woche Sonnet")].compactMap { $0 }
        return list.isEmpty ? .failure(Failure(state: .failed("Keine Limits in der Antwort"))) : .success((list, creds.plan))
    }

    private static func parseDate(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
}
