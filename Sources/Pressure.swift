import Foundation

enum Pressure: Int32, CaseIterable {
    case normal = 1
    case warning = 2
    case critical = 4

    var label: String {
        switch self {
        case .normal: return "정상"
        case .warning: return "주의"
        case .critical: return "위험"
        }
    }

    var asset: String {
        switch self {
        case .normal: return "normal"
        case .warning: return "warning"
        case .critical: return "critical"
        }
    }

    static func read() -> Pressure? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        // Read-only XNU sysctl exposes dispatch values 1, 2, 4, not internal VM enum values.
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &value, &size, nil, 0) == 0,
              size == MemoryLayout<Int32>.size else { return nil }
        return Pressure(rawValue: value)
    }
}

struct AlertEpisode {
    var notified: Bool
    private(set) var generation = 0
    private var pending = false
    private var retryAfter: TimeInterval = 0

    init(notified: Bool) { self.notified = notified }

    mutating func observe(_ pressure: Pressure?, canNotify: Bool,
        now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Bool {
        guard let pressure else { return false }
        if pressure == .normal {
            notified = false
            pending = false
            retryAfter = 0
            generation += 1
            return false
        }
        guard canNotify, !notified, !pending, now >= retryAfter else { return false }
        pending = true
        return true
    }

    mutating func complete(generation: Int, success: Bool,
        now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard generation == self.generation, pending else { return }
        pending = false
        notified = success
        retryAfter = success ? 0 : now + 60
    }
}
