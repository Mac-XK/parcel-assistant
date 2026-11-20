import Foundation
import UserNotifications
import UIKit

/// 本地通知：到站提醒与「该取了」提醒。全部本机投递，不依赖服务器。
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()

    private let center = UNUserNotificationCenter.current()
    private(set) var authorized = false
    private(set) var statusText = "未知"

    override init() {
        super.init()
        // App 在前台时默认不弹通知，必须实现 willPresent 才能看到横幅
        center.delegate = self
    }

    func configure() {
        center.delegate = self
    }

    func requestPermission() async -> Bool {
        do {
            let ok = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            authorized = ok
            await refreshAuthorization()
            return ok
        } catch {
            authorized = false
            statusText = error.localizedDescription
            return false
        }
    }

    func refreshAuthorization() async {
        let s = await center.notificationSettings()
        authorized = s.authorizationStatus == .authorized || s.authorizationStatus == .provisional
        switch s.authorizationStatus {
        case .authorized: statusText = "已允许"
        case .provisional: statusText = "临时允许"
        case .denied: statusText = "已被拒绝"
        case .notDetermined: statusText = "未询问"
        case .ephemeral: statusText = "临时授权"
        @unknown default: statusText = "未知"
        }
    }

    /// 待取包裹按「到站 + 6 小时」排一条提醒
    func refresh(parcels: [Parcel], settings: Settings) {
        center.removeAllPendingNotificationRequests()
        guard settings.reminderEnabled, settings.notifyOnArrive else { return }

        for p in parcels where p.isAwaiting {
            let arrived = p.arrivedAt ?? p.createdAt
            let fire = arrived.addingTimeInterval(6 * 3600)
            if fire < Date() { continue }

            let content = UNMutableNotificationContent()
            content.title = p.code.isEmpty ? "包裹还在等你" : "取件码 \(p.code)"
            content.body = "\(p.station) · \(p.title)"
            content.sound = .default
            content.userInfo = ["id": p.id.uuidString]

            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            center.add(UNNotificationRequest(identifier: "box.pickup.\(p.id.uuidString)",
                                             content: content, trigger: trigger))
        }
    }

    /// 设置页里的「发一条测试通知」
    func test(after seconds: Double = 3, completion: ((Error?) -> Void)? = nil) {
        let content = UNMutableNotificationContent()
        content.title = "取件码 6-5-9955"
        content.body = "菜鸟驿站·万科城店 · 这是一条测试通知"
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        center.add(UNNotificationRequest(identifier: "box.pickup.test", content: content, trigger: trigger)) { error in
            DispatchQueue.main.async { completion?(error) }
        }
    }

    func pendingCount() async -> Int {
        await withCheckedContinuation { cont in
            center.getPendingNotificationRequests { list in
                cont.resume(returning: list.filter { $0.identifier.hasPrefix("box.pickup.") }.count)
            }
        }
    }

    // MARK: 前台展示 + 点击

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let id = response.notification.request.content.userInfo["id"] as? String
        Task { @MainActor in
            if let id, let uuid = UUID(uuidString: id),
               let parcel = Store.shared.parcels.first(where: { $0.id == uuid }) {
                Store.shared.toast = "\(parcel.code.isEmpty ? parcel.title : parcel.code) · \(parcel.station)"
            }
            completionHandler()
        }
    }
}
