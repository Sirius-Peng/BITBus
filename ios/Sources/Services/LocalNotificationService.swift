import Foundation
import UserNotifications

struct NotificationClient: Sendable {
    let requestAuthorization: @Sendable () async -> Void
    let send: @Sendable (_ title: String, _ body: String) async -> Void

    static let live = NotificationClient(
        requestAuthorization: {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .sound, .badge]
            )
        },
        send: { title, body in
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil
            )
            try? await UNUserNotificationCenter.current().add(request)
        }
    )
}
