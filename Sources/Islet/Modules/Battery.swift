import Foundation
import IOKit.ps

/// Akku-Status über IOPS-Benachrichtigungen (ereignisgesteuert, kein Polling).
final class Battery: ObservableObject {
    static let shared = Battery()

    @Published var hasBattery = false
    @Published var percent = 0
    @Published var charging = false
    @Published var pluggedIn = false
    @Published var recentlyPlugged = false

    private var source: CFRunLoopSource?
    private var hideWork: DispatchWorkItem?

    func start() {
        guard source == nil else { return }
        refresh(initial: true)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        if let s = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            Unmanaged<Battery>.fromOpaque(ctx).takeUnretainedValue().refresh(initial: false)
        }, ctx)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), s, .commonModes)
            source = s
        }
    }

    func stop() {
        if let s = source { CFRunLoopRemoveSource(CFRunLoopGetMain(), s, .commonModes) }
        source = nil
        recentlyPlugged = false
    }

    func refresh(initial: Bool) {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return }
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
                  (d[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }
            let cur = d[kIOPSCurrentCapacityKey] as? Int ?? 0
            let max = d[kIOPSMaxCapacityKey] as? Int ?? 100
            let plugged = (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            let wasPlugged = pluggedIn
            hasBattery = true
            percent = max > 0 ? cur * 100 / max : cur
            charging = d[kIOPSIsChargingKey] as? Bool ?? false
            pluggedIn = plugged
            if !initial && plugged && !wasPlugged { flashPlugged() }
            return
        }
        hasBattery = false
    }

    private func flashPlugged() {
        recentlyPlugged = true
        hideWork?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.recentlyPlugged = false }
        hideWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5, execute: w)
    }
}
