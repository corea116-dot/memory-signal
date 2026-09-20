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
                    ProcessMemoryEntry(pid: 100, name: "Unity", residentBytes: 2_136_829_952, executablePath: nil),
                    ProcessMemoryEntry(pid: 101, name: "WindowServer", residentBytes: 1_331_429_376, executablePath: nil),
                    ProcessMemoryEntry(pid: 102, name: "Codex (Renderer)", residentBytes: 1_116_692_480, executablePath: nil),
                    ProcessMemoryEntry(pid: 103, name: "Aside Daemon", residentBytes: 799_644_057, executablePath: nil),
                    ProcessMemoryEntry(pid: 104, name: "node", residentBytes: 510_027_366, executablePath: nil),
                    ProcessMemoryEntry(pid: 105, name: "ChatGPT", residentBytes: 375_285_350, executablePath: nil),
                    ProcessMemoryEntry(pid: 106, name: "BetterDisplay", residentBytes: 358_612_582, executablePath: nil),
                    ProcessMemoryEntry(pid: 107, name: "카카오톡", residentBytes: 324_429_414, executablePath: nil)
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
