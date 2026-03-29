// NotificationService.swift — LockInBro
// APNs token registration, local notification scheduling, and notification routing

import Foundation
import UserNotifications
import UIKit

// Published notification type strings (match backend payload "type" field)
enum PushType: String {
    case sessionHandoff    = "session_handoff"
    case sessionEnded      = "session_ended"
    case deadlineApproach  = "deadline_approaching"
    case morningBrief      = "morning_brief"
    case focusNudge        = "focus_nudge"
    case focusStreak       = "focus_streak"
    case resumeSession     = "resume_session"
}

final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()
    private override init() { super.init() }

    // Callback so the app can route taps to the correct screen
    var onDeepLink: ((URL) -> Void)?

    // MARK: - Setup

    func configure() {
        UNUserNotificationCenter.current().delegate = self
    }

    // MARK: - Permission + Registration

    /// Request permission then register for remote (APNs) notifications.
    /// Call this after the user logs in.
    func registerForPushNotifications() async {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .badge, .sound])
            guard granted else { return }
        } catch {
            print("[Notifications] Permission error: \(error)")
            return
        }
        await MainActor.run {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    /// Called by AppDelegate when APNs returns a device token.
    /// Sends the token to the backend for push delivery.
    func didRegisterWithToken(_ tokenData: Data) {
        let token = tokenData.map { String(format: "%02.2hhx", $0) }.joined()
        print("[Notifications] APNs token: \(token)")
        let platform = UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone"
        Task {
            do {
                try await APIClient.shared.registerDeviceToken(platform: platform, token: token)
                print("[Notifications] Successfully registered APNs token.")
            } catch APIError.unauthorized {
                print("[Notifications] Auth expired during APNs token registration.")
            } catch {
                print("[Notifications] Failed to register APNs token: \(error)")
            }
        }
    }

    func didFailToRegister(with error: Error) {
        print("[Notifications] APNs registration failed: \(error)")
    }

    // MARK: - Local Notification Scheduling

    /// Schedule deadline reminders for tasks that have deadlines.
    /// Fires at 24h before and 1h before the deadline.
    func scheduleDeadlineReminders(for tasks: [TaskOut]) {
        let center = UNUserNotificationCenter.current()
        // Remove old deadline identifiers before re-scheduling
        let oldIds = tasks.flatMap { ["\($0.id)-24h", "\($0.id)-1h"] }
        center.removePendingNotificationRequests(withIdentifiers: oldIds)

        let now = Date()
        for task in tasks where task.status != "done" {
            guard let deadline = task.deadlineDate else { continue }

            for (suffix, offset) in [("-24h", -86400.0), ("-1h", -3600.0)] {
                let fireDate = deadline.addingTimeInterval(offset)
                guard fireDate > now else { continue }

                let content = UNMutableNotificationContent()
                content.title = "Deadline approaching"
                let interval = offset == -86400 ? "tomorrow" : "in 1 hour"
                content.body = "'\(task.title)' is due \(interval). \(task.estimatedMinutes.map { "~\($0) min estimated." } ?? "")"
                content.sound = .default
                content.badge = 1
                if let url = URL(string: "lockinbro://task?id=\(task.id)") {
                    content.userInfo = ["deep_link": url.absoluteString, "type": PushType.deadlineApproach.rawValue]
                }

                let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                let request = UNNotificationRequest(identifier: "\(task.id)\(suffix)", content: content, trigger: trigger)
                center.add(request)
            }
        }
    }

    /// Schedule a daily morning brief at the given hour (default 9 AM).
    func scheduleMorningBrief(hour: Int = 9) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["morning-brief"])

        let content = UNMutableNotificationContent()
        content.title = "Good morning! 🌅"
        content.body = "Open LockInBro to see your tasks for today."
        content.sound = .default
        content.userInfo = ["type": PushType.morningBrief.rawValue]

        var components = DateComponents()
        components.hour = hour
        components.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: "morning-brief", content: content, trigger: trigger)
        center.add(request)
    }

    /// Fire a local nudge notification immediately (used by DeviceActivityMonitor extension,
    /// or when the app detects the user has been idle for too long).
    func sendLocalNudge(title: String, body: String, deepLink: String? = nil) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let deepLink { content.userInfo = ["deep_link": deepLink] }

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let id = "nudge-\(UUID().uuidString)"
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Show notifications as banners even when the app is in the foreground.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }

    /// Handle notification taps — extract deep link and route.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }

        let userInfo = response.notification.request.content.userInfo

        // Prefer explicit deep_link field in payload
        if let rawLink = userInfo["deep_link"] as? String,
           let url = URL(string: rawLink) {
            onDeepLink?(url)
            return
        }

        // Fallback: construct deep link from type + ids in payload
        let type = userInfo["type"] as? String ?? ""
        switch type {
        case PushType.sessionHandoff.rawValue, PushType.resumeSession.rawValue:
            if let sessionId = userInfo["session_id"] as? String,
               let url = URL(string: "lockinbro://join-session?id=\(sessionId)") {
                onDeepLink?(url)
            }
        case PushType.deadlineApproach.rawValue, PushType.morningBrief.rawValue, PushType.focusNudge.rawValue:
            if let taskId = userInfo["task_id"] as? String,
               let url = URL(string: "lockinbro://task?id=\(taskId)") {
                onDeepLink?(url)
            }
        default:
            break
        }
    }
}
