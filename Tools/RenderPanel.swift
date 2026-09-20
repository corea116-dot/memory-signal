import AppKit

@main
struct RenderPanel {
    @MainActor static func main() throws {
        guard CommandLine.arguments.count == 2 else { return }
        let directory = URL(fileURLWithPath: CommandLine.arguments[1])
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let panel = MemoryPanel()
        let now = ProcessInfo.processInfo.systemUptime
        for dark in [false, true] {
            panel.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            for pressure in Pressure.allCases {
                var history = PressureHistory()
                for offset in stride(from: 118, through: 0, by: -2) {
                    history.append(pressure, at: now - Double(offset))
                }
                let snapshot = MemorySnapshot(physical: 25_769_803_776, used: 19_628_671_877,
                    cached: 5_841_155_523, swap: 408_210_637)
                let processes = [
                    ProcessMemoryEntry(pid: 100, name: "Unity", memoryBytes: 2_136_829_952, executablePath: nil),
                    ProcessMemoryEntry(pid: 101, name: "Codex (Renderer)", memoryBytes: 1_116_692_480, executablePath: nil),
                    ProcessMemoryEntry(pid: 102, name: "Codex (Service)", memoryBytes: 736_414_515, executablePath: nil),
                    ProcessMemoryEntry(pid: 103, name: "Aside Helper", memoryBytes: 524_603_392, executablePath: nil),
                    ProcessMemoryEntry(pid: 104, name: "codex", memoryBytes: 419_430_400, executablePath: nil),
                    ProcessMemoryEntry(pid: 105, name: "bun", memoryBytes: 396_361_728, executablePath: nil),
                    ProcessMemoryEntry(pid: 106, name: "BetterDisplay", memoryBytes: 358_612_582, executablePath: nil),
                    ProcessMemoryEntry(pid: 107, name: "ChatGPT", memoryBytes: 337_641_472, executablePath: nil),
                    ProcessMemoryEntry(pid: 108, name: "node", memoryBytes: 327_155_712, executablePath: nil),
                    ProcessMemoryEntry(pid: 109, name: "카카오톡", memoryBytes: 323_485_696, executablePath: nil),
                    ProcessMemoryEntry(pid: 110, name: "Spotlight", memoryBytes: 244_318_208, executablePath: nil),
                    ProcessMemoryEntry(pid: 111, name: "Finder", memoryBytes: 192_937_984, executablePath: nil)
                ]
                panel.update(snapshot: snapshot, history: history, pressure: pressure, processes: processes)
                guard let bitmap = panel.bitmapImageRepForCachingDisplay(in: panel.bounds) else { continue }
                panel.cacheDisplay(in: panel.bounds, to: bitmap)
                guard let data = bitmap.representation(using: .png, properties: [:]) else { continue }
                try data.write(to: directory.appendingPathComponent("panel-\(pressure.asset)-\(dark ? "dark" : "light").png"))
            }
        }
        print("Rendered six fixture previews; no app lifecycle, login registration, notification, or live sampling executed.")
    }
}
