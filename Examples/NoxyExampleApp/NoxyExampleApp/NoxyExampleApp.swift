import SwiftUI
import UserNotifications

/// Delegate to show notifications when the app is in the foreground.
/// Without this, iOS suppresses notification banners when the app is active.
private final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .badge, .sound])
    }
}

@main
struct NoxyExampleApp: App {
    private static let notificationDelegate = NotificationDelegate()

    init() {
        UNUserNotificationCenter.current().delegate = Self.notificationDelegate
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
