import Foundation

func check(_ value: @autoclosure () -> Bool, _ message: String) {
    guard value() else { fatalError(message) }
}
var episode = AlertEpisode(notified: false)
let states: [Pressure?] = [.normal, .warning, .warning, .critical, nil, .warning, .normal, .critical]
let actual = states.map { episode.observe($0, canNotify: true) }
check(actual == [false, true, false, false, false, false, false, true], "episode transitions")
var startup = AlertEpisode(notified: false)
check(startup.observe(.critical, canNotify: true), "initial high pressure alerts")
check(!startup.notified, "submission must succeed before episode is consumed")
startup.complete(generation: startup.generation, success: false, now: 100)
check(!startup.observe(.critical, canNotify: true, now: 159), "failed submission has bounded retry")
check(startup.observe(.critical, canNotify: true, now: 160), "failed submission retries after cooldown")
startup.complete(generation: startup.generation, success: true, now: 161)
check(startup.notified, "successful submission consumes episode")
check(!startup.observe(.warning, canNotify: true, now: 500), "success suppresses repeats")
var stale = AlertEpisode(notified: false)
check(stale.observe(.warning, canNotify: true), "begin pending alert")
let oldGeneration = stale.generation
check(!stale.observe(.normal, canNotify: true), "normal invalidates pending episode")
stale.complete(generation: oldGeneration, success: true)
check(stale.observe(.warning, canNotify: true), "stale completion cannot consume new episode")
var restart = AlertEpisode(notified: true)
check(!restart.observe(.warning, canNotify: true), "restart preserves episode")
check(!restart.observe(nil, canNotify: true), "unknown never rearms")
check(!restart.observe(.normal, canNotify: true), "normal rearms silently")
check(restart.observe(.warning, canNotify: true), "rearmed episode alerts")
var denied = AlertEpisode(notified: false)
check(!denied.observe(.warning, canNotify: false), "no permission does not consume alert")
check(denied.observe(.warning, canNotify: true), "permission later granted")
check(Pressure(rawValue: 1) == .normal, "normal mapping")
check(Pressure(rawValue: 2) == .warning, "warning mapping")
check(Pressure(rawValue: 4) == .critical, "critical mapping")
check(Pressure(rawValue: 0) == nil && Pressure(rawValue: 3) == nil, "unknown mapping")
print("PASS: transitions, startup, restart, unknown, permission, raw-value mapping")
check(MemorySnapshot.format(25_769_803_776) == "24.00GB", "physical capacity formatting")
check(MemorySnapshot.format(nil) == "—", "failed measurement is not zero")
check(MemorySnapshot.format(0, smallUnits: true) == "0.0MB", "zero swap is valid")
var history = PressureHistory()
history.append(.normal, at: 0)
history.append(.warning, at: 2)
history.append(nil, at: 4)
history.append(.critical, at: 123)
check(history.samples.count == 2, "history retains only last 120 seconds")
check(history.samples.first?.pressure == nil, "unknown history remains a gap")
print("PASS: memory formatting, missing data, bounded history")
if CommandLine.arguments.contains("--live") {
    guard let current = Pressure.read() else { fatalError("Live pressure unavailable") }
    print("LIVE pressure=\(current.rawValue) \(current.label)")
    let snapshot = MemorySnapshot.read()
    check(snapshot.used != nil && snapshot.cached != nil && snapshot.swap != nil, "live VM and swap values available")
    print("LIVE physical=\(MemorySnapshot.format(snapshot.physical)) used=\(MemorySnapshot.format(snapshot.used)) cached=\(MemorySnapshot.format(snapshot.cached)) swap=\(MemorySnapshot.format(snapshot.swap, smallUnits: true))")
}
