import AppKit
import ServiceManagement
import UserNotifications
import OSLog

@MainActor
final class SystemServices: NSObject, UNUserNotificationCenterDelegate {
    let log = Logger(subsystem: "local.memory-pressure", category: "services")
    var notificationLabel = "알림 권한 확인 중"
    var authorized = false
    var onChange: (() -> Void)?
    private let center = UNUserNotificationCenter.current()

    func start() {
        center.delegate = self
        refreshNotifications(request: true)
        if !UserDefaults.standard.bool(forKey: "loginRegistrationAttempted") {
            enableLogin()
            UserDefaults.standard.set(true, forKey: "loginRegistrationAttempted")
        }
    }

    func refreshNotifications(request: Bool = false) {
        center.getNotificationSettings { settings in
            let status = settings.authorizationStatus
            Task { @MainActor in
                switch status {
                case .authorized, .provisional, .ephemeral:
                    self.authorized = true
                    self.notificationLabel = "알림: 허용됨"
                case .denied:
                    self.authorized = false
                    self.notificationLabel = "알림: 꺼짐 · 설정에서 허용"
                case .notDetermined:
                    self.authorized = false
                    self.notificationLabel = "알림 허용하기…"
                    if request {
                        do { _ = try await self.center.requestAuthorization(options: [.alert, .sound]) }
                        catch { self.log.error("notification authorization: \(error.localizedDescription)") }
                        self.refreshNotifications()
                    }
                @unknown default:
                    self.authorized = false
                    self.notificationLabel = "알림 권한 확인 필요"
                }
                self.onChange?()
            }
        }
    }

    func notify(_ pressure: Pressure, completion: @escaping @MainActor (Bool) -> Void) {
        let content = UNMutableNotificationContent()
        content.title = "메모리 압력: \(pressure.label)"
        content.body = "Mac의 메모리 압력이 높아졌습니다. 정상으로 돌아오기 전에는 다시 알리지 않습니다."
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        center.add(request) { error in
            Task { @MainActor in completion(error == nil) }
            if let error {
                self.log.error("notification delivery failed: \(error.localizedDescription)")
                Task { @MainActor in
                    self.notificationLabel = "알림 전송 실패 · 설정 확인"
                    self.onChange?()
                }
            } else {
                self.log.info("pressure notification submitted")
            }
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }

    var loginLabel: String {
        switch SMAppService.mainApp.status {
        case .enabled: return "로그인 시 실행: 켜짐"
        case .requiresApproval: return "로그인 시 실행: 시스템 승인 필요…"
        case .notRegistered: return "로그인 시 자동 실행 켜기"
        case .notFound: return "로그인 항목 등록 확인 필요…"
        @unknown default: return "로그인 항목 설정…"
        }
    }

    func enableLogin() {
        do {
            try SMAppService.mainApp.register()
            log.info("login registration status: \(SMAppService.mainApp.status.rawValue)")
        } catch {
            log.error("login registration failed: \(error.localizedDescription)")
        }
    }

    @objc func loginAction() {
        switch SMAppService.mainApp.status {
        case .enabled:
            do { try SMAppService.mainApp.unregister() }
            catch { log.error("login unregister failed: \(error.localizedDescription)") }
        case .notRegistered: enableLogin()
        case .requiresApproval, .notFound: SMAppService.openSystemSettingsLoginItems()
        @unknown default: SMAppService.openSystemSettingsLoginItems()
        }
        onChange?()
    }

    @objc func notificationAction() {
        center.getNotificationSettings { settings in
            let status = settings.authorizationStatus
            Task { @MainActor in
                if status == .notDetermined {
                    self.refreshNotifications(request: true)
                } else if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }
}
