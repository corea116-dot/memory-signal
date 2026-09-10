import AppKit
import OSLog

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var item: NSStatusItem?
    private var timer: Timer?
    private var source: DispatchSourceMemoryPressure?
    private let services = SystemServices()
    private var episode = AlertEpisode(notified: UserDefaults.standard.bool(forKey: "episodeNotified"))
    private let statusRow = NSMenuItem(title: "상태 확인 중", action: nil, keyEquivalent: "")
    private let notificationRow = NSMenuItem(title: "", action: #selector(SystemServices.notificationAction), keyEquivalent: "")
    private let loginRow = NSMenuItem(title: "", action: #selector(SystemServices.loginAction), keyEquivalent: "")
    private let log = Logger(subsystem: "local.memory-pressure", category: "monitor")
    private var images: [Pressure: NSImage] = [:]
    private var lastPressure: Pressure?
    private var hasSample = false
    private let panel = MemoryPanel()
    private var history = PressureHistory()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        for pressure in Pressure.allCases {
            guard let url = Bundle.main.url(forResource: pressure.asset, withExtension: "png"),
                  let image = NSImage(contentsOf: url) else {
                let alert = NSAlert()
                alert.messageText = "상태 아이콘을 불러올 수 없습니다."
                alert.runModal()
                NSApp.terminate(nil)
                return
            }
            image.size = NSSize(width: 24, height: 24)
            image.isTemplate = false
            images[pressure] = image
        }
        item = NSStatusBar.system.statusItem(withLength: 32)
        let menu = NSMenu()
        menu.delegate = self
        let panelItem = NSMenuItem()
        panelItem.view = panel
        menu.addItem(panelItem)
        menu.addItem(.separator())
        notificationRow.target = services
        loginRow.target = services
        menu.addItem(notificationRow)
        menu.addItem(loginRow)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "메모리 신호 종료", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        item?.menu = menu
        services.onChange = { [weak self] in self?.refreshMenu(); self?.sample() }
        services.start()
        sample()
        timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sample() }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
        if let timer { RunLoop.main.add(timer, forMode: .eventTracking) }
        source = DispatchSource.makeMemoryPressureSource(eventMask: [.normal, .warning, .critical], queue: .main)
        source?.setEventHandler { [weak self] in self?.sample() }
        source?.resume()
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(woke),
            name: NSWorkspace.didWakeNotification, object: nil)
        refreshMenu()
    }

    private func sample() {
        let pressure = Pressure.read()
        history.append(pressure, at: ProcessInfo.processInfo.systemUptime)
        panel.update(snapshot: MemorySnapshot.read(), history: history, pressure: pressure)
        if !hasSample || pressure != lastPressure {
            hasSample = true
            lastPressure = pressure
            log.info("pressure state: \(pressure?.rawValue ?? -1)")
        }
        if let pressure {
            item?.button?.image = images[pressure]
            item?.button?.toolTip = "메모리 압력: \(pressure.label)"
            item?.button?.setAccessibilityLabel("메모리 압력: \(pressure.label)")
            statusRow.title = "메모리 압력: \(pressure.label)"
        } else {
            item?.button?.image = NSImage(systemSymbolName: "questionmark.circle", accessibilityDescription: "상태 확인 불가")
            item?.button?.toolTip = "메모리 압력을 읽을 수 없습니다"
            item?.button?.setAccessibilityLabel("메모리 압력: 확인 불가")
            statusRow.title = "메모리 압력: 확인 불가"
        }
        let shouldNotify = episode.observe(pressure, canNotify: services.authorized)
        persistEpisode()
        if shouldNotify, let pressure {
            let generation = episode.generation
            services.notify(pressure) { [weak self] success in
                self?.episode.complete(generation: generation, success: success)
                self?.persistEpisode()
            }
        }
    }

    private func persistEpisode() {
        if UserDefaults.standard.bool(forKey: "episodeNotified") != episode.notified {
            UserDefaults.standard.set(episode.notified, forKey: "episodeNotified")
        }
    }

    private func refreshMenu() {
        notificationRow.title = services.notificationLabel
        loginRow.title = services.loginLabel
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshMenu()
        services.refreshNotifications()
        sample()
    }

    @objc private func woke() { sample(); services.refreshNotifications() }
    @objc private func quitApp() { NSApp.terminate(nil) }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        source?.cancel()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
