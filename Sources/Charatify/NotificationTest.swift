import Foundation
import UserNotifications

/// Sends only this app's own local test notification. It does not contact another person.
@MainActor
final class NotificationTest: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published var message: String?

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func send() {
        Task {
            do {
                let center = UNUserNotificationCenter.current()
                guard try await center.requestAuthorization(options: [.alert]) else {
                    message = "このアプリの通知が無効です。システム設定の「通知」で許可してください。"
                    return
                }
                let content = UNMutableNotificationContent()
                content.title = "キャラクター通知のテスト"
                content.body = "macOSの通知を受け取りました。キャラクターの吹き出しにも同じ文が出れば成功です。"
                let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false))
                try await center.add(request)
                message = "3秒後にmacOS通知を送ります。キャラクターの吹き出しも表示されるか確認してください。"
            } catch { message = "テスト通知を送れません: \(error.localizedDescription)" }
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner])
    }
}
