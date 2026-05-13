import Foundation
import UIKit
import UserNotifications

final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()

    private override init() {}

    func configure() {
        UNUserNotificationCenter.current().delegate = self
        requestAuthorization()
    }

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            if let error {
                print("Notification authorization failed: \(error.localizedDescription)")
                return
            }

            guard granted else {
                print("Notification authorization was not granted")
                return
            }

            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    func handleRegisteredDeviceToken(_ deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(token, forKey: "apns_device_token")
        print("APNs device token: \(token)")
    }

    func handleRegistrationError(_ error: Error) {
        print("APNs registration failed: \(error.localizedDescription)")
    }

    func notifyIncomingSmartiecoin(amount: String) {
        let content = UNMutableNotificationContent()
        content.title = "Smartiecoin received"
        content.body = "Incoming balance detected: \(amount) SMT"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "incoming-smartiecoin-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }
}
