import Darwin
import Foundation

struct ProcessMemoryEntry {
    let pid: pid_t
    let name: String
    let residentBytes: UInt64
    let executablePath: String?
}

enum ProcessMemorySnapshot {
    static func read(limit: Int = 8) -> [ProcessMemoryEntry] {
        let byteCount = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard byteCount > 0 else { return [] }

        var pids = [pid_t](repeating: 0, count: Int(byteCount) / MemoryLayout<pid_t>.stride + 32)
        let usedBytes = pids.withUnsafeMutableBytes { buffer in
            proc_listpids(UInt32(PROC_ALL_PIDS), 0, buffer.baseAddress, Int32(buffer.count))
        }
        guard usedBytes > 0 else { return [] }

        let count = min(pids.count, Int(usedBytes) / MemoryLayout<pid_t>.stride)
        return pids.prefix(count).compactMap(entry(for:)).filter { $0.residentBytes > 0 }
            .sorted { lhs, rhs in
                if lhs.residentBytes == rhs.residentBytes { return lhs.pid < rhs.pid }
                return lhs.residentBytes > rhs.residentBytes
            }
            .prefix(max(0, limit)).map { $0 }
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
        guard readSize == taskInfoSize else { return nil }

        var nameBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let nameLength = proc_name(pid, &nameBuffer, UInt32(nameBuffer.count))
        let name = nameLength > 0
            ? String(decoding: nameBuffer.prefix(Int(nameLength)).map(UInt8.init(bitPattern:)), as: UTF8.self)
            : "프로세스 \(pid)"

        var pathBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let pathLength = proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count))
        let path = pathLength > 0
            ? String(decoding: pathBuffer.prefix(Int(pathLength)).map(UInt8.init(bitPattern:)), as: UTF8.self)
            : nil
        return ProcessMemoryEntry(pid: pid, name: name,
            residentBytes: taskInfo.pti_resident_size, executablePath: path)
    }
}
