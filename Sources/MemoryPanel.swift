import AppKit

private enum PanelTypography {
    static let menuEquivalentSize: CGFloat = 19.5
}

private enum PanelLayout {
    static let displayScale: CGFloat = 2.0 / 3.0
    static let logicalWidth: CGFloat = 620
    static let minimumLogicalHeight: CGFloat = 470
}

final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

@MainActor
final class ProcessMemoryRow: NSView {
    private let icon = NSImageView()
    private let name = NSTextField(labelWithString: "")
    private let value = NSTextField(labelWithString: "")
    private var shaded = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        icon.frame = NSRect(x: 8, y: 4, width: 20, height: 20)
        icon.imageScaling = .scaleProportionallyUpOrDown
        addSubview(icon)
        name.frame = NSRect(x: 38, y: 2, width: 390, height: 24)
        name.font = .systemFont(ofSize: PanelTypography.menuEquivalentSize)
        name.lineBreakMode = .byTruncatingTail
        addSubview(name)
        value.frame = NSRect(x: 438, y: 2, width: 146, height: 24)
        value.font = .monospacedDigitSystemFont(ofSize: PanelTypography.menuEquivalentSize, weight: .regular)
        value.alignment = .right
        addSubview(value)
    }

    required init?(coder: NSCoder) { nil }

    func update(_ entry: ProcessMemoryEntry, shaded: Bool) {
        self.shaded = shaded
        let app = NSRunningApplication(processIdentifier: entry.pid)
        name.stringValue = app?.localizedName ?? entry.name
        icon.image = app?.icon ?? entry.executablePath.map { NSWorkspace.shared.icon(forFile: $0) }
            ?? NSImage(systemSymbolName: "memorychip", accessibilityDescription: nil)
        value.stringValue = ProcessMemorySnapshot.format(entry.memoryBytes)
        setAccessibilityElement(true)
        setAccessibilityLabel("\(name.stringValue), \(value.stringValue)")
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard shaded else { return }
        NSColor.labelColor.withAlphaComponent(0.06).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 1), xRadius: 6, yRadius: 6).fill()
    }
}

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
    private let graph = PressureGraph()
    private var metricLabels: [NSTextField] = []
    private var values: [NSTextField] = []
    private var processRows: [ProcessMemoryRow] = []
    private let processTitle = NSTextField(labelWithString: "메모리 사용 상위 프로세스 · 스크롤")
    private let processScroll = NSScrollView()
    private let processContent = FlippedView(frame: NSRect(x: 0, y: 0, width: 580, height: 224))
    private let state = NSTextField(labelWithString: "메모리 압력")
    private let freshness = NSTextField(labelWithString: "측정 대기 중")

    init() {
        super.init(frame: NSRect(x: 0, y: 0,
            width: PanelLayout.logicalWidth * PanelLayout.displayScale,
            height: PanelLayout.minimumLogicalHeight * PanelLayout.displayScale))
        bounds = NSRect(x: 0, y: 0,
            width: PanelLayout.logicalWidth, height: PanelLayout.minimumLogicalHeight)
        state.alignment = .center
        state.font = .systemFont(ofSize: PanelTypography.menuEquivalentSize, weight: .semibold)
        addSubview(state)
        addSubview(graph)
        let labels = ["물리적 메모리:", "사용된 메모리:", "캐시된 파일:", "사용된 스왑 공간:"]
        for title in labels {
            let label = NSTextField(labelWithString: title)
            label.font = .systemFont(ofSize: PanelTypography.menuEquivalentSize)
            metricLabels.append(label)
            addSubview(label)
            let value = NSTextField(labelWithString: "—")
            value.font = .monospacedDigitSystemFont(ofSize: PanelTypography.menuEquivalentSize, weight: .regular)
            value.alignment = .right
            value.setAccessibilityLabel(title)
            values.append(value)
            addSubview(value)
        }
        freshness.font = .systemFont(ofSize: 11)
        freshness.textColor = .secondaryLabelColor
        addSubview(freshness)

        processTitle.font = .systemFont(ofSize: PanelTypography.menuEquivalentSize, weight: .semibold)
        addSubview(processTitle)
        processScroll.drawsBackground = false
        processScroll.borderType = .noBorder
        processScroll.hasVerticalScroller = true
        processScroll.scrollerStyle = .legacy
        processScroll.autohidesScrollers = false
        processScroll.documentView = processContent
        addSubview(processScroll)
        toolTip = "2초마다 갱신 · 창 높이에 따라 표시되는 프로세스 수가 바뀝니다."
        layoutContent()
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        layoutContent()
    }

    func setDisplayHeight(_ requestedHeight: CGFloat) {
        let minimum = PanelLayout.minimumLogicalHeight * PanelLayout.displayScale
        let height = max(requestedHeight, minimum)
        guard abs(height - frame.height) >= 0.5 else { return }
        setFrameSize(NSSize(width: PanelLayout.logicalWidth * PanelLayout.displayScale, height: height))
        setBoundsSize(NSSize(width: PanelLayout.logicalWidth,
            height: height / PanelLayout.displayScale))
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    private func layoutContent() {
        let top = bounds.height
        state.frame = NSRect(x: 16, y: top - 44, width: 270, height: 28)
        graph.frame = NSRect(x: 16, y: top - 156, width: 270, height: 100)
        for (index, label) in metricLabels.enumerated() {
            let y = top - 47 - CGFloat(index) * 35
            label.frame = NSRect(x: 316, y: y, width: 170, height: 26)
            values[index].frame = NSRect(x: 481, y: y, width: 121, height: 26)
        }
        freshness.frame = NSRect(x: 316, y: top - 179, width: 286, height: 18)
        processTitle.frame = NSRect(x: 16, y: top - 232, width: 588, height: 26)
        let availableProcessHeight = max(28, processTitle.frame.minY - 14)
        let visibleRows = max(1, floor(availableProcessHeight / 28))
        processScroll.frame = NSRect(x: 10, y: 10, width: 600,
            height: visibleRows * 28)
        updateProcessGeometry()
        needsDisplay = true
    }

    private func updateProcessGeometry() {
        let contentWidth = processScroll.contentSize.width
        processContent.frame = NSRect(x: 0, y: 0, width: contentWidth,
            height: max(processScroll.contentSize.height, CGFloat(processRows.count) * 28))
        for (index, row) in processRows.enumerated() {
            row.frame = NSRect(x: 0, y: CGFloat(index) * 28,
                width: contentWidth, height: 28)
        }
    }

    func update(snapshot: MemorySnapshot, history: PressureHistory, pressure: Pressure?,
                processes: [ProcessMemoryEntry]) {
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
        updateProcesses(processes)
    }

    func updateProcesses(_ processes: [ProcessMemoryEntry]) {
        let wasEmpty = processRows.isEmpty
        let contentWidth = processScroll.contentSize.width
        while processRows.count < processes.count {
            let row = ProcessMemoryRow(frame: NSRect(x: 0,
                y: CGFloat(processRows.count) * 28, width: contentWidth, height: 28))
            processRows.append(row)
            processContent.addSubview(row)
        }
        for (index, row) in processRows.enumerated() {
            guard index < processes.count else {
                row.isHidden = true
                continue
            }
            row.isHidden = false
            row.frame = NSRect(x: 0, y: CGFloat(index) * 28, width: contentWidth, height: 28)
            row.update(processes[index], shaded: index.isMultiple(of: 2) == false)
        }
        updateProcessGeometry()
        if wasEmpty {
            processScroll.contentView.scroll(to: .zero)
            processScroll.reflectScrolledClipView(processScroll.contentView)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let top = bounds.height
        NSColor.controlBackgroundColor.setFill()
        bounds.fill()
        NSColor.separatorColor.setStroke()
        let lines = NSBezierPath()
        lines.move(to: NSPoint(x: 301, y: top - 181))
        lines.line(to: NSPoint(x: 301, y: top - 16))
        for y in [top - 53, top - 88, top - 123] {
            lines.move(to: NSPoint(x: 316, y: y))
            lines.line(to: NSPoint(x: 602, y: y))
        }
        lines.move(to: NSPoint(x: 16, y: top - 196))
        lines.line(to: NSPoint(x: 604, y: top - 196))
        lines.lineWidth = 0.5
        lines.stroke()
    }
}
