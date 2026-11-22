import Foundation
import Security
import OpenDirectory
import Vision
import CryptoKit
import IOKit

/// Ein eingelernter Gesichtsabdruck: Bild-Fingerabdruck (Vision) plus Gesichtsproportionen, samt Kopfhaltung.
struct FaceSample {
    var feature: VNFeaturePrintObservation
    var geometry: [Float]
    var yaw: Float
    var pitch: Float
}

/// Gespeicherte Vorlage: alle Abdrücke plus die beim Einlernen gemessene Streuung (für die Schwellen).
struct FaceTemplate {
    var samples: [FaceSample]
    /// 90. Perzentil der nächsten Nachbar-Abstände innerhalb der eigenen Abdrücke.
    var baseFeature: Float
    var baseGeometry: Float

    private struct Stored: Codable {
        var features: [Data]; var geometry: [[Float]]; var yaw: [Float]; var pitch: [Float]
        var baseFeature: Float; var baseGeometry: Float
    }

    func encoded() -> Data? {
        var feats: [Data] = []
        for s in samples {
            guard let d = try? NSKeyedArchiver.archivedData(withRootObject: s.feature, requiringSecureCoding: true) else { return nil }
            feats.append(d)
        }
        let enc = JSONEncoder()
        enc.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        return try? enc.encode(Stored(features: feats, geometry: samples.map(\.geometry), yaw: samples.map(\.yaw),
                                       pitch: samples.map(\.pitch), baseFeature: baseFeature, baseGeometry: baseGeometry))
    }

    static func decode(_ data: Data) -> FaceTemplate? {
        let dec = JSONDecoder()
        dec.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        guard let s = try? dec.decode(Stored.self, from: data) else { return nil }
        var out: [FaceSample] = []
        for i in 0..<s.features.count {
            guard let f = try? NSKeyedUnarchiver.unarchivedObject(ofClass: VNFeaturePrintObservation.self, from: s.features[i]) else { return nil }
            out.append(FaceSample(feature: f, geometry: s.geometry[i], yaw: s.yaw[i], pitch: s.pitch[i]))
        }
        return FaceTemplate(samples: out, baseFeature: s.baseFeature, baseGeometry: s.baseGeometry)
    }
}

/// Speicher für Passwort und Gesichtsvorlage: eine verschlüsselte Datei (AES-GCM), ohne Schlüsselbund-Abfragen.
/// Der Schlüssel wird aus der Hardware-ID dieses Macs und dem Benutzernamen abgeleitet, die Datei ist also nur auf
/// diesem Mac und für diesen Benutzer lesbar und liegt nirgends im Klartext. Schutz gegen ein anderes Programm,
/// das unter deinem Benutzer läuft, bietet das nicht (das gilt für jeden Entsperrer, der ein Passwort tippen muss).
/// Warum nicht der Schlüsselbund: Seine Abfragen („Islet möchte auf … zugreifen“) erscheinen bei einer lokal signierten
/// App bei jedem Start und würden am Sperrbildschirm blockieren.
enum FaceStore {
    private struct Vault: Codable { var password: String?; var template: Data? }
    private struct Envelope: Codable { var salt: Data; var box: Data }

    private static let lock = NSLock()
    private static var cache: Vault?
    private static let legacyService = "app.islet.faceunlock"

    private static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Islet", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("face-vault.bin")
    }

    // MARK: Verschlüsselung

    private static func platformUUID() -> String {
        let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        defer { IOObjectRelease(svc) }
        let v = IORegistryEntryCreateCFProperty(svc, kIOPlatformUUIDKey as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
        return (v as? String) ?? "unknown-platform"
    }

    private static func key(salt: Data) -> SymmetricKey {
        let ikm = SymmetricKey(data: Data("\(platformUUID())|\(NSUserName())".utf8))
        return HKDF<SHA256>.deriveKey(inputKeyMaterial: ikm, salt: salt, info: Data("islet.faceunlock.vault.v1".utf8), outputByteCount: 32)
    }

    private static func readVault() -> Vault {
        lock.lock(); defer { lock.unlock() }
        if let c = cache { return c }
        var v = Vault(password: nil, template: nil)
        if let data = try? Data(contentsOf: fileURL),
           let env = try? JSONDecoder().decode(Envelope.self, from: data),
           let box = try? AES.GCM.SealedBox(combined: env.box),
           let plain = try? AES.GCM.open(box, using: key(salt: env.salt)),
           let decoded = try? JSONDecoder().decode(Vault.self, from: plain) {
            v = decoded
        }
        cache = v
        return v
    }

    @discardableResult
    private static func writeVault(_ v: Vault) -> Bool {
        lock.lock(); defer { lock.unlock() }
        cache = v
        if v.password == nil && v.template == nil { try? FileManager.default.removeItem(at: fileURL); return true }
        var salt = Data(count: 16)
        _ = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        guard let plain = try? JSONEncoder().encode(v),
              let box = try? AES.GCM.seal(plain, using: key(salt: salt)).combined,
              let out = try? JSONEncoder().encode(Envelope(salt: salt, box: box)) else { return false }
        do {
            try out.write(to: fileURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
            return true
        } catch { return false }
    }

    // MARK: Öffentliche Schnittstelle

    static var hasPassword: Bool { readVault().password != nil }
    static var hasTemplate: Bool { readVault().template != nil }

    @discardableResult static func savePassword(_ pw: String) -> Bool { var v = readVault(); v.password = pw; return writeVault(v) }
    static func loadPassword() -> String? { readVault().password }
    @discardableResult static func saveTemplate(_ t: FaceTemplate) -> Bool {
        guard let d = t.encoded() else { return false }
        var v = readVault(); v.template = d; return writeVault(v)
    }
    static func loadTemplate() -> FaceTemplate? { readVault().template.flatMap(FaceTemplate.decode) }

    static func deleteAll() {
        writeVault(Vault(password: nil, template: nil))
        deleteLegacy("password"); deleteLegacy("template")
    }

    // MARK: Einmalige Übernahme aus dem Schlüsselbund (frühere Versionen)

    private static func legacyQuery(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: legacyService, kSecAttrAccount as String: account]
    }

    private static func legacyExists(_ account: String) -> Bool {
        var q = legacyQuery(account)
        q[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
        let s = SecItemCopyMatching(q as CFDictionary, nil)
        return s == errSecSuccess || s == errSecInteractionNotAllowed
    }

    private static func legacyLoad(_ account: String) -> Data? {
        var q = legacyQuery(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        return SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess ? out as? Data : nil
    }

    private static func deleteLegacy(_ account: String) { SecItemDelete(legacyQuery(account) as CFDictionary) }

    /// Ein letztes Mal: Daten aus dem Schlüsselbund holen (macOS fragt dabei evtl. noch einmal), in die neue Datei
    /// schreiben und die Schlüsselbund-Einträge löschen. Danach gibt es keine Abfragen mehr.
    /// Gibt eine Meldung zurück, wenn etwas übernommen wurde.
    @discardableResult
    static func migrateLegacyIfNeeded() -> String? {
        guard !hasPassword || !hasTemplate, legacyExists("password") || legacyExists("template") else { return nil }
        var v = readVault()
        if v.password == nil, let d = legacyLoad("password"), let s = String(data: d, encoding: .utf8) { v.password = s }
        if v.template == nil, let d = legacyLoad("template") { v.template = d }
        guard v.password != nil || v.template != nil, writeVault(v) else { return nil }
        deleteLegacy("password"); deleteLegacy("template")
        return "Daten aus dem Schlüsselbund übernommen, ab jetzt keine Abfragen mehr"
    }

    // MARK: Passwort-Prüfung

    /// Prüft das Passwort gegen den angemeldeten Account, damit ein Tippfehler schon beim Einrichten auffällt.
    static func verifyLoginPassword(_ pw: String) -> Bool {
        do {
            let node = try ODNode(session: ODSession.default(), type: ODNodeType(kODNodeTypeAuthentication))
            let record = try node.record(withRecordType: kODRecordTypeUsers, name: NSUserName(), attributes: nil)
            try record.verifyPassword(pw)
            return true
        } catch {
            return false
        }
    }
}
