import Foundation
import Security
import OpenDirectory
import Vision

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

/// Schlüsselbund und Passwort-Prüfung. Nichts davon landet in einer Datei oder in den Einstellungen.
enum FaceStore {
    private static let service = "app.islet.faceunlock"

    private static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    @discardableResult
    static func save(_ data: Data, account: String) -> Bool {
        SecItemDelete(query(account) as CFDictionary)
        var q = query(account)
        q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
    }

    static func load(account: String) -> Data? {
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        return SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess ? out as? Data : nil
    }

    static func delete(account: String) { SecItemDelete(query(account) as CFDictionary) }

    static func exists(account: String) -> Bool {
        var q = query(account)
        q[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
        return SecItemCopyMatching(q as CFDictionary, nil) != errSecItemNotFound
    }

    static var hasPassword: Bool { exists(account: "password") }
    static var hasTemplate: Bool { exists(account: "template") }

    static func savePassword(_ pw: String) -> Bool { save(Data(pw.utf8), account: "password") }
    static func loadPassword() -> String? { load(account: "password").flatMap { String(data: $0, encoding: .utf8) } }
    static func saveTemplate(_ t: FaceTemplate) -> Bool { t.encoded().map { save($0, account: "template") } ?? false }
    static func loadTemplate() -> FaceTemplate? { load(account: "template").flatMap(FaceTemplate.decode) }

    static func deleteAll() { delete(account: "password"); delete(account: "template") }

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
