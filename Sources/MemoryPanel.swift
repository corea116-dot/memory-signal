import AppKit

@MainActor
final class PressureGraph: NSView {
    var samples: [PressureSample] = []
    var now: TimeInterval = 0

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 1, dy: 1)
        NSColor.separatorColor.setStroke()
        let grid = NSBezierPath()
        for fraction in [0.0, 0.5, 1.0] {
            let y = rect.minY + rect.height * fraction
            grid.move(to: NSPoint(x: rect.minX, y: y))
            grid.line(to: NSPoint(x: rect.maxX, y: y))
        }
        grid.lineWidth = 0.5
        grid.stroke()
        for (index, sample) in samples.enumerated() {
            guard let pressure = sample.pressure else { continue }
            let next = index + 1 < samples.count ? samples[index + 1].time : now
            let end = min(next, sample.time + 4)
            let x = rect.minX + rect.width * max(0, (sample.time - (now - 120)) / 120)
            let right = rect.minX + rect.width * min(1, (end - (now - 120)) / 120)
            guard right > x else { continue }
            let height: CGFloat
            let color: NSColor
            switch pressure {
            case .normal: height = rect.height * 0.2; color = .systemGreen
            case .warning: height = rect.height * 0.55; color = .systemYellow
            case .critical: height = rect.height * 0.9; color = .systemRed
            }
            color.withAlphaComponent(0.3).setFill()
            NSRect(x: x, y: rect.minY, width: right - x, height: height).fill()
            color.setStroke()
            let line = NSBezierPath()
            line.move(to: NSPoint(x: x, y: rect.minY + height))
            line.line(to: NSPoint(x: right, y: rect.minY + height))
            line.lineWidth = 1
            line.stroke()
        }
    }
}

@MainActor
final class MemoryPanel: NSView {
    private let graph = PressureGraph(frame: NSRect(x: 16, y: 40, width: 270, height: 100))
    private var values: [NSTextField] = []
    private let state = NSTextField(labelWithString: "메모리 압력")
    private let freshness = NSTextField(labelWithString: "측정 대기 중")

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 620 * 2 / 3, height: 196 * 2 / 3))
        bounds = NSRect(x: 0, y: 0, width: 620, height: 196)
        state.frame = NSRect(x: 16, y: 154, width: 270, height: 24)
        state.alignment = .center
        state.font = .systemFont(ofSize: 14, weight: .semibold)
        addSubview(state)
        addSubview(graph)
        let labels = ["물리적 메모리:", "사용된 메모리:", "캐시된 파일:", "사용된 스왑 공간:"]
        for (index, title) in labels.enumerated() {
            let y = 151 - CGFloat(index) * 35
            let label = NSTextField(labelWithString: title)
            label.frame = NSRect(x: 316, y: y, width: 170, height: 22)
            label.font = .systemFont(ofSize: 15)
            addSubview(label)
            let value = NSTextField(labelWithString: "—")
            value.frame = NSRect(x: 481, y: y, width: 121, height: 22)
            value.font = .monospacedDigitSystemFont(ofSize: 15, weight: .regular)
            value.alignment = .right
            value.setAccessibilityLabel(title)
            values.append(value)
            addSubview(value)
        }
        freshness.frame = NSRect(x: 316, y: 17, width: 286, height: 18)
        freshness.font = .systemFont(ofSize: 10)
        freshness.textColor = .secondaryLabelColor
        addSubview(freshness)
        toolTip = "2초마다 갱신 · 그래프는 OS 압력 단계 이력입니다. 용량은 1024 기반이며 사용량·캐시는 VM 통계 추정값입니다."
    }

    required init?(coder: NSCoder) { nil }

    func update(snapshot: MemorySnapshot, history: PressureHistory, pressure: Pressure?) {
        let bytes = [Optional(snapshot.physical), snapshot.used, snapshot.cached, snapshot.swap]
        for (index, value) in values.enumerated() {
            value.stringValue = MemorySnapshot.format(bytes[index], smallUnits: index == 3)
        }
        state.stringValue = "메모리 압력 · \(pressure?.label ?? "확인 불가")"
        freshness.stringValue = "\(Date().formatted(date: .omitted, time: .standard)) 갱신 · 사용량·캐시 추정"
        graph.samples = history.samples
        graph.now = ProcessInfo.processInfo.systemUptime
        graph.setAccessibilityElement(true)
        graph.setAccessibilityLabel("최근 2분 메모리 압력 단계 이력. 현재 \(pressure?.label ?? "확인 불가")")
        graph.needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlBackgroundColor.setFill()
        bounds.fill()
        NSColor.separatorColor.setStroke()
        let lines = NSBezierPath()
        lines.move(to: NSPoint(x: 301, y: 15))
        lines.line(to: NSPoint(x: 301, y: 180))
        for y in [143, 108, 73] {
            lines.move(to: NSPoint(x: 316, y: y))
            lines.line(to: NSPoint(x: 602, y: y))
        }
        lines.lineWidth = 0.5
        lines.stroke()
    }
}
