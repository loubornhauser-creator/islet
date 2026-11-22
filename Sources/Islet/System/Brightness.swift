import CoreGraphics
import Darwin

/// Helligkeit des eingebauten Displays über das (private) DisplayServices-Framework.
/// Wird zur Laufzeit geladen; fehlt es, ist die Funktion einfach nicht verfügbar.
enum Brightness {
    private typealias GetFn = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFn = @convention(c) (UInt32, Float) -> Int32

    private static let lib = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)
    private static let getFn: GetFn? = lib.flatMap { dlsym($0, "DisplayServicesGetBrightness") }.map { unsafeBitCast($0, to: GetFn.self) }
    private static let setFn: SetFn? = lib.flatMap { dlsym($0, "DisplayServicesSetBrightness") }.map { unsafeBitCast($0, to: SetFn.self) }

    static var displayID: UInt32 {
        var ids = [CGDirectDisplayID](repeating: 0, count: 8)
        var n: UInt32 = 0
        CGGetActiveDisplayList(8, &ids, &n)
        for i in 0..<Int(n) where CGDisplayIsBuiltin(ids[i]) != 0 { return ids[i] }
        return CGMainDisplayID()
    }

    static var available: Bool { getFn != nil && setFn != nil && current != nil }

    static var current: Float? {
        guard let getFn else { return nil }
        var v: Float = 0
        return getFn(displayID, &v) == 0 ? v : nil
    }

    @discardableResult
    static func set(_ value: Float) -> Float? {
        guard let setFn else { return nil }
        let v = min(1, max(0, value))
        return setFn(displayID, v) == 0 ? v : nil
    }

    @discardableResult
    static func adjust(_ delta: Float) -> Float? {
        guard let cur = current else { return nil }
        return set(cur + delta)
    }
}
