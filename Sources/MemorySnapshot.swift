import Foundation

struct MemorySnapshot {
    let physical: UInt64
    let used: UInt64?
    let cached: UInt64?
    let swap: UInt64?

    static func read() -> MemorySnapshot {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        var pageSize: vm_size_t = 0
        let pagesValid = host_page_size(host, &pageSize) == KERN_SUCCESS && pageSize > 0
        let page = UInt64(pageSize)
        var swap = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        let swapOK = sysctlbyname("vm.swapusage", &swap, &size, nil, 0) == 0
        let physical = ProcessInfo.processInfo.physicalMemory
        let used = result == KERN_SUCCESS && pagesValid
            ? min(physical, (UInt64(stats.internal_page_count) - min(UInt64(stats.internal_page_count), UInt64(stats.purgeable_count))
                + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * page) : nil
        let cached = result == KERN_SUCCESS && pagesValid
            ? min(physical, (UInt64(stats.external_page_count) + UInt64(stats.purgeable_count)) * page) : nil
        return MemorySnapshot(physical: physical, used: used, cached: cached, swap: swapOK ? swap.xsu_used : nil)
    }

    static func format(_ bytes: UInt64?, smallUnits: Bool = false) -> String {
        guard let bytes else { return "—" }
        if smallUnits && bytes < 1_073_741_824 {
            return String(format: "%.1fMB", Double(bytes) / 1_048_576)
        }
        return String(format: "%.2fGB", Double(bytes) / 1_073_741_824)
    }
}

struct PressureSample {
    let time: TimeInterval
    let pressure: Pressure?
}

struct PressureHistory {
    private(set) var samples: [PressureSample] = []
    mutating func append(_ pressure: Pressure?, at time: TimeInterval) {
        if let last = samples.last, time - last.time < 1 { return }
        samples.append(PressureSample(time: time, pressure: pressure))
        samples.removeAll { $0.time < time - 120 }
    }
}
