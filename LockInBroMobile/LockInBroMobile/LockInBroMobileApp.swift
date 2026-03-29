//
//  LockInBroMobileApp.swift
//  LockInBroMobile
//
//  Created by Aditya Pulipaka on 3/28/26.
//

import SwiftUI
import UIKit
import UserNotifications

// MARK: - AppDelegate
// Needed for APNs token callbacks, which have no SwiftUI equivalent

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        NotificationService.shared.configure()
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        NotificationService.shared.didRegisterWithToken(deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        NotificationService.shared.didFailToRegister(with: error)
    }
}

// MARK: - App Entry Point

@main
struct LockInBroMobileApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .onOpenURL { url in
                    handleDeepLink(url)
                }
                .onAppear {
                    // Wire notification taps → same deep link handler
                    NotificationService.shared.onDeepLink = { url in
                        handleDeepLink(url)
                    }
                    if appState.isAuthenticated {
                        Task { await NotificationService.shared.registerForPushNotifications() }
                        NotificationService.shared.scheduleMorningBrief(hour: 9)
                        wireActivityManager()
                        ActivityManager.shared.configure()
                        ScreenTimeManager.shared.requestAuthorization()
                    }
                }
                .onChange(of: appState.isAuthenticated) { _, isAuthed in
                    if isAuthed {
                        Task { await NotificationService.shared.registerForPushNotifications() }
                        NotificationService.shared.scheduleMorningBrief(hour: 9)
                        wireActivityManager()
                        ActivityManager.shared.configure()
                        ScreenTimeManager.shared.requestAuthorization()
                    }
                }
                .onChange(of: appState.tasks) { _, tasks in
                    // Re-schedule deadline reminders whenever the task list changes
                    if appState.isAuthenticated {
                        NotificationService.shared.scheduleDeadlineReminders(for: tasks)
                    }
                }
        }
    }

    // MARK: - Live Activity → AppState Bridge

    private func wireActivityManager() {
        ActivityManager.shared.onSessionStarted = {
            await appState.loadActiveSession()
        }
        ActivityManager.shared.onSessionEnded = {
            appState.activeSession = nil
        }
    }

    // MARK: - Deep Link / Notification Tap Router
    // Handles lockinbro:// URLs from both onOpenURL and notification taps

    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "lockinbro" else { return }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)

        switch url.host {

        case "join-session":
            // lockinbro://join-session?id=<session_id>&open=<url_encoded_app_scheme>
            // Used by Live Activity tap and cross-device handoff push notification
            let sessionId = components?.queryItems?.first(where: { $0.name == "id" })?.value
            let encodedScheme = components?.queryItems?.first(where: { $0.name == "open" })?.value

            // Chain-open the target work app immediately — user sees Notes/Pages open, not LockInBro
            if let encodedScheme,
               let decoded = encodedScheme.removingPercentEncoding,
               let targetURL = URL(string: decoded) {
                UIApplication.shared.open(targetURL)
            }

            if let sessionId {
                let platform = UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone"
                Task {
                    _ = try? await APIClient.shared.joinSession(sessionId: sessionId, platform: platform)
                }
            }

        case "resume-session":
            // lockinbro://resume-session?id=<session_id>
            // Notification tap → user wants to see the resume card
            // AppState publishes the session ID so TaskDetailView can react
            if let sessionId = components?.queryItems?.first(where: { $0.name == "id" })?.value {
                appState.pendingResumeSessionId = sessionId
            }

        case "task":
            // lockinbro://task?id=<task_id>
            // Deadline / morning brief notification tap → navigate to task
            if let taskId = components?.queryItems?.first(where: { $0.name == "id" })?.value {
                appState.pendingOpenTaskId = taskId
            }

        default:
            break
        }
    }
}
