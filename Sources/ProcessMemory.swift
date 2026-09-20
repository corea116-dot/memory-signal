import Darwin
import Foundation

struct ProcessMemoryEntry: Sendable {
    let pid: pid_t
    let name: String
    let memoryBytes: UInt64
    let executablePath: String?
}

enum ProcessMemorySnapshot {
    static func read(limit: Int = 50) -> [ProcessMemoryEntry] {
        guard limit > 0 else { return [] }
        let byteCount = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard byteCount > 0 else { return [] }

        var pids = [pid_t](repeating: 0, count: Int(byteCount) / MemoryLayout<pid_t>.stride + 32)
        let usedBytes = pids.withUnsafeMutableBytes { buffer in
            proc_listpids(UInt32(PROC_ALL_PIDS), 0, buffer.baseAddress, Int32(buffer.count))
        }
        guard usedBytes > 0 else { return [] }

        let count = min(pids.count, Int(usedBytes) / MemoryLayout<pid_t>.stride)
        return pids.prefix(count).compactMap(entry(for:)).filter { $0.memoryBytes > 0 }
            .sorted { lhs, rhs in
                if lhs.memoryBytes == rhs.memoryBytes { return lhs.pid < rhs.pid }
                return lhs.memoryBytes > rhs.memoryBytes
            }
            .prefix(limit).map { $0 }
    }

    static func displayBytes(resident: UInt64?, footprint: UInt64?) -> UInt64? {
        footprint ?? resident
    }

    static func readProtectedFallback(limit: Int = 50) -> [ProcessMemoryEntry] {
        guard limit > 0 else { return [] }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/top")
        process.arguments = ["-l", "1", "-s", "0", "-o", "mem", "-stats", "pid,command,mem", "-n", String(limit)]
        process.environment = ["LC_ALL": "C", "LANG": "C", "PATH": "/usr/bin:/bin"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return []
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let text = String(data: data, encoding: .utf8) else { return [] }

        return text.split(separator: "\n").compactMap { line in
            let columns = line.split(whereSeparator: \Character.isWhitespace)
            guard columns.count >= 3,
                  let pid = pid_t(columns[0]),
                  let memoryBytes = parseTopMemory(String(columns.last!)) else { return nil }
            let topName = columns[1..<(columns.count - 1)].joined(separator: " ")
            return ProcessMemoryEntry(pid: pid, name: processName(for: pid, fallback: topName),
                memoryBytes: memoryBytes, executablePath: nil)
        }
    }

    static func merge(primary: [ProcessMemoryEntry], fallback: [ProcessMemoryEntry], limit: Int) -> [ProcessMemoryEntry] {
        guard limit > 0 else { return [] }
        var entriesByPID = Dictionary(uniqueKeysWithValues: fallback.map { ($0.pid, $0) })
        for entry in primary {
            entriesByPID[entry.pid] = entry
        }
        return entriesByPID.values.sorted { lhs, rhs in
            if lhs.memoryBytes == rhs.memoryBytes { return lhs.pid < rhs.pid }
            return lhs.memoryBytes > rhs.memoryBytes
        }.prefix(limit).map { $0 }
    }

    static func parseTopMemory(_ value: String) -> UInt64? {
        guard let suffix = value.last else { return nil }
        let multiplier: Double
        switch suffix {
        case "B": multiplier = 1
        case "K": multiplier = 1_024
        case "M": multiplier = 1_048_576
        case "G": multiplier = 1_073_741_824
        case "T": multiplier = 1_099_511_627_776
        default: return nil
        }
        guard let amount = Double(value.dropLast()), amount >= 0 else { return nil }
        return UInt64(amount * multiplier)
    }

    static func format(_ bytes: UInt64) -> String {
        if bytes >= 1_073_741_824 {
            return String(format: "%.2fGB", Double(bytes) / 1_073_741_824)
        }
        return String(format: "%.1fMB", Double(bytes) / 1_048_576)
    }

    private static func entry(for pid: pid_t) -> ProcessMemoryEntry? {
        guard pid > 0 else { return nil }
        var taskInfo = proc_taskinfo()
        let taskInfoSize = MemoryLayout<proc_taskinfo>.size
        let readSize = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &taskInfo, Int32(taskInfoSize))
        let resident = readSize == taskInfoSize ? taskInfo.pti_resident_size : nil

        var usage = rusage_info_v4()
        let usageResult = withUnsafeMutablePointer(to: &usage) { pointer in
            proc_pid_rusage(pid, RUSAGE_INFO_V4,
                UnsafeMutableRawPointer(pointer).assumingMemoryBound(to: rusage_info_t?.self))
        }
        let footprint = usageResult == 0 ? usage.ri_phys_footprint : nil
        guard let memoryBytes = displayBytes(resident: resident, footprint: footprint) else { return nil }

        var pathBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let pathLength = proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count))
        let path = pathLength > 0
            ? String(decoding: pathBuffer.prefix(Int(pathLength)).map(UInt8.init(bitPattern:)), as: UTF8.self)
            : nil
        return ProcessMemoryEntry(pid: pid, name: processName(for: pid),
            memoryBytes: memoryBytes, executablePath: path)
    }

    private static func processName(for pid: pid_t, fallback: String? = nil) -> String {
        var nameBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let nameLength = proc_name(pid, &nameBuffer, UInt32(nameBuffer.count))
        guard nameLength > 0 else { return fallback ?? "프로세스 \(pid)" }
        return String(decoding: nameBuffer.prefix(Int(nameLength)).map(UInt8.init(bitPattern:)), as: UTF8.self)
    }
}
