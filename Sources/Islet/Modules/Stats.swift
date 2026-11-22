import Foundation
import IOKit

/// CPU / GPU / RAM. Läuft nur, solange ein Stats-Tile sichtbar ist (retain/release).
final class Stats: ObservableObject {
    static let shared = Stats()

    @Published var cpu: Double = 0
    @Published var gpu: Double = 0
    @Published var mem: Double = 0

    private var users = 0
    private var timer: Timer?
    private var last: (user: UInt32, sys: UInt32, idle: UInt32, nice: UInt32)?

    func retain() {
        users += 1
        guard users == 1 else { return }
        sample()
        let t = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.sample() }
        t.tolerance = 0.5
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func release() {
        users = max(0, users - 1)
        if users == 0 { timer?.invalidate(); timer = nil; last = nil }
    }

    private func sample() {
        cpu = readCPU()
        mem = readMem()
        gpu = readGPU()
    }

    private func readCPU() -> Double {
        var size = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        var info = host_cpu_load_info()
        let r = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &size)
            }
        }
        guard r == KERN_SUCCESS else { return cpu }
        let cur = (user: info.cpu_ticks.0, sys: info.cpu_ticks.1, idle: info.cpu_ticks.2, nice: info.cpu_ticks.3)
        defer { last = cur }
        guard let l = last else { return 0 }
        let busy = Double(cur.user &- l.user) + Double(cur.sys &- l.sys) + Double(cur.nice &- l.nice)
        let total = busy + Double(cur.idle &- l.idle)
        return total > 0 ? busy / total : 0
    }

    private func readMem() -> Double {
        var size = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        var vm = vm_statistics64_data_t()
        let r = withUnsafeMutablePointer(to: &vm) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &size)
            }
        }
        guard r == KERN_SUCCESS else { return mem }
        let used = Double(vm.active_count + vm.wire_count + vm.compressor_page_count) * Double(vm_kernel_page_size)
        return min(1, used / Double(ProcessInfo.processInfo.physicalMemory))
    }

    private func readGPU() -> Double {
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iter) == KERN_SUCCESS else { return gpu }
        defer { IOObjectRelease(iter) }
        var best = 0
        var entry = IOIteratorNext(iter)
        while entry != 0 {
            if let p = IORegistryEntryCreateCFProperty(entry, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any],
               let util = p["Device Utilization %"] as? Int {
                best = max(best, util)
            }
            IOObjectRelease(entry)
            entry = IOIteratorNext(iter)
        }
        return Double(best) / 100
    }
}
