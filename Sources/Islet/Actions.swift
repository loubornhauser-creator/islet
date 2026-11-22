import AppKit

/// Eigene Aktionen: Shell-Befehl, App oder URL. Gespeichert als JSON in UserDefaults.
struct ActionItem: Codable, Identifiable, Equatable {
    enum Kind: String, Codable, CaseIterable {
        case shell = "Befehl", app = "App", url = "Link"
    }
    var id = UUID()
    var title = "Neu"
    var symbol = "star.fill"
    var kind: Kind = .shell
    var value = ""

    func run() {
        switch kind {
        case .shell:
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/zsh")
            p.arguments = ["-lc", value]
            try? p.run()
        case .app:
            if value.hasPrefix("/") {
                NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: value), configuration: NSWorkspace.OpenConfiguration())
            } else {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                p.arguments = ["-a", value]
                try? p.run()
            }
        case .url:
            if let u = URL(string: value) { NSWorkspace.shared.open(u) }
        }
    }

    static func load() -> [ActionItem] {
        let json = UserDefaults.standard.string(forKey: "actionsJSON") ?? "[]"
        return (try? JSONDecoder().decode([ActionItem].self, from: Data(json.utf8))) ?? []
    }

    static func save(_ items: [ActionItem]) {
        if let d = try? JSONEncoder().encode(items), let s = String(data: d, encoding: .utf8) {
            UserDefaults.standard.set(s, forKey: "actionsJSON")
        }
    }
}
