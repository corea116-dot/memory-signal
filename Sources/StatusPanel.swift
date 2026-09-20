import AppKit

private enum StatusPanelLayout {
    static let width: CGFloat = 620 * 2 / 3
    static let memoryMinimumHeight: CGFloat = 470 * 2 / 3
    static let footerHeight: CGFloat = 102
    static let minimumHeight = memoryMinimumHeight + footerHeight
    static let rowHeight: CGFloat = 33
}

@MainActor
final class StatusPanelWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
private final class ResizeHandleView: NSView {
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeUpDown)
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        let initialMouse = NSEvent.mouseLocation
        let initialFrame = window.frame
        while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if next.type == .leftMouseUp { break }
            let delta = initialMouse.y - NSEvent.mouseLocation.y
            let proposedHeight = initialFrame.height + delta
            let step = window.resizeIncrements.height
            let steps = ((proposedHeight - window.minSize.height) / step).rounded()
            let snappedHeight = window.minSize.height + steps * step
            let height = min(max(snappedHeight, window.minSize.height), window.maxSize.height)
            let frame = NSRect(x: initialFrame.minX, y: initialFrame.maxY - height,
                width: initialFrame.width, height: height)
            window.setFrame(frame, display: true)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let grip = NSBezierPath()
        for offset in [0.0, 4.0, 8.0] {
            grip.move(to: NSPoint(x: bounds.width - 8 - offset, y: 3))
            grip.line(to: NSPoint(x: bounds.width - 3, y: 8 + offset))
        }
        grip.lineWidth = 1
        NSColor.secondaryLabelColor.withAlphaComponent(0.55).setStroke()
        grip.stroke()
    }
}

@MainActor
final class StatusPanelView: NSView {
    let memoryPanel: MemoryPanel
    let notificationButton = NSButton()
    let loginButton = NSButton()
    let quitButton = NSButton()
    private let quitShortcut = NSTextField(labelWithString: "⌘ Q")
    private let resizeHandle = ResizeHandleView()

    init(memoryPanel: MemoryPanel) {
        self.memoryPanel = memoryPanel
        super.init(frame: NSRect(x: 0, y: 0,
            width: StatusPanelLayout.width, height: StatusPanelLayout.minimumHeight))
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.masksToBounds = true
        for button in [notificationButton, loginButton, quitButton] {
            button.isBordered = false
            button.alignment = .left
            button.font = .systemFont(ofSize: 13)
            button.focusRingType = .none
            addSubview(button)
        }
        quitShortcut.font = .systemFont(ofSize: 13)
        quitShortcut.textColor = .secondaryLabelColor
        quitShortcut.alignment = .right
        addSubview(quitShortcut)
        addSubview(memoryPanel)
        addSubview(resizeHandle)
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        memoryPanel.setDisplayHeight(bounds.height - StatusPanelLayout.footerHeight)
        memoryPanel.setFrameOrigin(NSPoint(x: 0, y: StatusPanelLayout.footerHeight))
        notificationButton.frame = NSRect(x: 10, y: 66, width: bounds.width - 20,
            height: StatusPanelLayout.rowHeight)
        loginButton.frame = NSRect(x: 10, y: 33, width: bounds.width - 20,
            height: StatusPanelLayout.rowHeight)
        quitButton.frame = NSRect(x: 10, y: 0, width: bounds.width - 20,
            height: StatusPanelLayout.rowHeight)
        quitShortcut.frame = NSRect(x: bounds.width - 58, y: 7, width: 42, height: 19)
        resizeHandle.frame = NSRect(x: bounds.width - 20, y: 0, width: 20, height: 20)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlBackgroundColor.setFill()
        bounds.fill()
        NSColor.separatorColor.setStroke()
        let separators = NSBezierPath()
        for y in [33.0, 99.0] {
            separators.move(to: NSPoint(x: 16, y: y))
            separators.line(to: NSPoint(x: bounds.width - 16, y: y))
        }
        separators.lineWidth = 0.5
        separators.stroke()

    }
}

@MainActor
final class StatusPanelController: NSObject, NSWindowDelegate {
    private let services: SystemServices
    private let content: StatusPanelView
    private let window: StatusPanelWindow
    private var localMonitor: Any?
    private var globalMonitor: Any?

    init(memoryPanel: MemoryPanel, services: SystemServices) {
        self.services = services
        content = StatusPanelView(memoryPanel: memoryPanel)
        window = StatusPanelWindow(contentRect: content.frame,
            styleMask: [.borderless, .resizable, .nonactivatingPanel],
            backing: .buffered, defer: false)
        super.init()
        window.delegate = self
        window.contentView = content
        window.level = .statusBar
        window.isFloatingPanel = true
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        window.minSize = NSSize(width: StatusPanelLayout.width,
            height: StatusPanelLayout.minimumHeight)
        window.maxSize = NSSize(width: StatusPanelLayout.width, height: 2_000)
        window.resizeIncrements = NSSize(width: 1, height: 28 * 2 / 3)
        content.notificationButton.target = self
        content.notificationButton.action = #selector(notificationPressed)
        content.loginButton.target = self
        content.loginButton.action = #selector(loginPressed)
        content.quitButton.target = self
        content.quitButton.action = #selector(quitPressed)
        refreshActions()
        installEventMonitors()
    }

    func toggle(relativeTo button: NSStatusBarButton) {
        if window.isVisible {
            window.orderOut(nil)
            return
        }
        let appearanceName: NSAppearance.Name =
            UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark" ? .darkAqua : .aqua
        window.appearance = NSAppearance(named: appearanceName)
        refreshActions()
        guard let buttonWindow = button.window else { return }
        let buttonRect = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = buttonWindow.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? buttonRect
        let availableHeight = max(StatusPanelLayout.minimumHeight,
            buttonRect.minY - visible.minY - 8)
        let step = window.resizeIncrements.height
        let rows = floor((availableHeight - StatusPanelLayout.minimumHeight) / step)
        let maximumHeight = StatusPanelLayout.minimumHeight + rows * step
        window.maxSize = NSSize(width: StatusPanelLayout.width, height: maximumHeight)
        if window.frame.height > maximumHeight {
            window.setContentSize(NSSize(width: StatusPanelLayout.width, height: maximumHeight))
        }
        let x = min(max(buttonRect.midX - window.frame.width / 2, visible.minX + 8),
            visible.maxX - window.frame.width - 8)
        let y = buttonRect.minY - window.frame.height
        window.setFrameOrigin(NSPoint(x: x, y: y))
        window.orderFrontRegardless()
    }

    func refreshActions() {
        content.notificationButton.title = services.notificationLabel
        content.loginButton.title = services.loginLabel
        content.quitButton.title = "메모리 신호 종료"
    }

    private func installEventMonitors() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) {
            [weak self] event in
            guard let self, self.window.isVisible else { return event }
            if event.type == .keyDown, event.keyCode == 53 {
                self.window.orderOut(nil)
                return nil
            }
            if event.window !== self.window,
               !self.window.frame.contains(NSEvent.mouseLocation) {
                self.window.orderOut(nil)
            }
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
            [weak self] _ in
            guard let self, !self.window.frame.contains(NSEvent.mouseLocation) else { return }
            self.window.orderOut(nil)
        }
    }

    @objc private func notificationPressed() {
        window.orderOut(nil)
        services.notificationAction()
    }

    @objc private func loginPressed() {
        window.orderOut(nil)
        services.loginAction()
    }

    @objc private func quitPressed() { NSApp.terminate(nil) }
}
