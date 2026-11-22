import AppKit
import Darwin

/// Holt ein Fenster über den Sperrbildschirm: Es wird in einen eigenen Space gelegt, dessen Ebene so hoch ist wie die
/// des Mitteilungszentrums am Sperrbildschirm. Nutzt private SkyLight-Funktionen, zur Laufzeit geladen. Fehlt eine,
/// passiert einfach nichts (die Animation fehlt dann am Sperrbildschirm, die Erkennung läuft trotzdem).
/// Vorgehen wie bei bekannten Open-Source-Projekten (z. B. SkyLightWindow, MIT). Verwendung schließt den Mac App Store aus.
final class LockScreenSpace {
    static let shared: LockScreenSpace? = LockScreenSpace()

    private typealias MainConnection = @convention(c) () -> Int32
    private typealias SpaceCreate = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias SetLevel = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias ShowSpaces = @convention(c) (Int32, CFArray) -> Int32
    private typealias AddWindows = @convention(c) (Int32, Int32, CFArray, Int32) -> Int32
    private typealias RemoveWindows = @convention(c) (Int32, CFArray, CFArray) -> Int32

    private let connection: Int32
    private let space: Int32
    private let addWindows: AddWindows
    private let removeWindows: RemoveWindows

    private init?() {
        guard let h = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight", RTLD_NOW),
              let c = dlsym(h, "SLSMainConnectionID"), let cr = dlsym(h, "SLSSpaceCreate"),
              let lv = dlsym(h, "SLSSpaceSetAbsoluteLevel"), let sh = dlsym(h, "SLSShowSpaces"),
              let ad = dlsym(h, "SLSSpaceAddWindowsAndRemoveFromSpaces"), let rm = dlsym(h, "SLSRemoveWindowsFromSpaces") else { return nil }
        let mainConn = unsafeBitCast(c, to: MainConnection.self)
        let create = unsafeBitCast(cr, to: SpaceCreate.self)
        let setLevel = unsafeBitCast(lv, to: SetLevel.self)
        let show = unsafeBitCast(sh, to: ShowSpaces.self)
        addWindows = unsafeBitCast(ad, to: AddWindows.self)
        removeWindows = unsafeBitCast(rm, to: RemoveWindows.self)
        connection = mainConn()
        // Das Flag 1 ist wichtig: mit anderen Werten zeichnet der Finder Schreibtisch-Symbole in diesen Space.
        space = create(connection, 1, 0)
        _ = setLevel(connection, space, 400)   // Ebene des Mitteilungszentrums am Sperrbildschirm
        _ = show(connection, [space] as CFArray)
    }

    /// Nur aufrufen, solange der Bildschirm wirklich gesperrt ist.
    static func place(window: NSWindow) {
        guard let s = shared, window.windowNumber > 0 else { return }
        _ = s.addWindows(s.connection, s.space, [window.windowNumber] as CFArray, 7)
    }

    /// Sobald der Bildschirm entsperrt ist, wieder normal behandeln.
    static func remove(window: NSWindow) {
        guard let s = shared, window.windowNumber > 0 else { return }
        _ = s.removeWindows(s.connection, [window.windowNumber] as CFArray, [s.space] as CFArray)
    }
}
