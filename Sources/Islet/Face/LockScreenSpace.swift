import AppKit
import Darwin

/// Holt ein Fenster über den Sperrbildschirm, indem es in einen eigenen Space mit höchster Ebene gelegt wird.
/// Nutzt private SkyLight-Funktionen, zur Laufzeit geladen. Fehlt eine, passiert einfach nichts (die Animation
/// ist dann am Sperrbildschirm nicht sichtbar, die Erkennung läuft trotzdem).
enum LockScreenSpace {
    private typealias MainConnection = @convention(c) () -> Int32
    private typealias SpaceCreate = @convention(c) (Int32, Int32, CFDictionary?) -> Int32
    private typealias SetLevel = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias ShowSpaces = @convention(c) (Int32, CFArray) -> Int32
    private typealias AddWindows = @convention(c) (Int32, CFArray, CFArray) -> Int32

    private static let lib = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
    private static func sym<T>(_ name: String, as type: T.Type) -> T? {
        guard let lib, let p = dlsym(lib, name) else { return nil }
        return unsafeBitCast(p, to: type)
    }

    private static var space: Int32 = 0

    @discardableResult
    static func place(window: NSWindow) -> Bool {
        guard let mainConn = sym("SLSMainConnectionID", as: MainConnection.self),
              let create = sym("SLSSpaceCreate", as: SpaceCreate.self),
              let setLevel = sym("SLSSpaceSetAbsoluteLevel", as: SetLevel.self),
              let show = sym("SLSShowSpaces", as: ShowSpaces.self),
              let add = sym("SLSAddWindowsToSpaces", as: AddWindows.self) else { return false }
        let conn = mainConn()
        if space == 0 {
            space = create(conn, 1, nil)
            _ = setLevel(conn, space, 2_147_483_647)
        }
        guard space != 0 else { return false }
        _ = show(conn, [space] as CFArray)
        _ = add(conn, [window.windowNumber] as CFArray, [space] as CFArray)
        return true
    }
}
