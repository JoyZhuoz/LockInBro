import ActivityKit
import UIKit

@MainActor
final class ActivityManager {
    static let shared = ActivityManager()

    /// Called when a Live Activity becomes active on this device (started remotely via push-to-start).
    var onSessionStarted: (() async -> Void)?
    /// Called when a Live Activity ends on this device (ended remotely via push).
    var onSessionEnded: (() -> Void)?
    /// Called when a Live Activity's content state updates (step progress changed).
    var onContentStateUpdated: ((FocusSessionAttributes.ContentState) -> Void)?

    /// Top-level observation tasks — cancelled and replaced on each configure() call.
    private var configurationTasks: [Task<Void, Never>] = []
    /// Per-activity tasks keyed by activity ID — prevents duplicate observers on re-yields.
    private var activityTasks: [String: [Task<Void, Never>]] = [:]

    private init() {}

    func endAllActivities() {
        Task {
            for activity in Activity<FocusSessionAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    func configure() {
        // Cancel all existing tasks before starting fresh (handles logout → login cycles)
        configurationTasks.forEach { $0.cancel() }
        configurationTasks.removeAll()
        activityTasks.values.flatMap { $0 }.forEach { $0.cancel() }
        activityTasks.removeAll()

        configurationTasks.append(Task { await observeActivityUpdateTokens() })
        if #available(iOS 17.2, *) {
            configurationTasks.append(Task { await observePushToStartToken() })
        }
    }

    /// Observes push tokens for all running activity instances (existing + newly started).
    /// These update tokens are required for the server to end/update a specific activity.
    private func observeActivityUpdateTokens() async {
        for await activity in Activity<FocusSessionAttributes>.activityUpdates {
            // activityUpdates can re-yield the same activity on content state changes.
            // Guard against spawning duplicate observers for an activity we already track.
            guard activityTasks[activity.id] == nil else { continue }

            let tokenTask = Task {
                for await tokenData in activity.pushTokenUpdates {
                    let tokenStr = tokenData.map { String(format: "%02.2hhx", $0) }.joined()
                    guard let uuid = UIDevice.current.identifierForVendor?.uuidString else { continue }
                    let platformKey = "liveactivity_update_\(uuid)"
                    do {
                        try await APIClient.shared.registerDeviceToken(platform: platformKey, token: tokenStr)
                        print("[ActivityManager] Registered activity update token for activity \(activity.id).")
                    } catch APIError.unauthorized {
                        print("[ActivityManager] Auth expired, stopping activity token observation.")
                        return
                    } catch {
                        print("[ActivityManager] Failed to register activity update token: \(error)")
                    }
                }
            }

            let stateTask = Task {
                for await state in activity.activityStateUpdates {
                    switch state {
                    case .active:
                        // Write initial context to SharedDefaults for shield extensions
                        let cs = activity.content.state
                        SharedDefaults.writeSessionContext(
                            taskTitle: cs.taskTitle,
                            stepsCompleted: cs.stepsCompleted,
                            stepsTotal: cs.stepsTotal,
                            currentStepTitle: cs.currentStepTitle,
                            lastCompletedStepTitle: cs.lastCompletedStepTitle
                        )
                        ScreenTimeManager.shared.startMonitoring()
                        await onSessionStarted?()
                    case .ended, .dismissed:
                        SharedDefaults.clearSessionContext()
                        ScreenTimeManager.shared.stopMonitoring()
                        onSessionEnded?()
                        activityTasks.removeValue(forKey: activity.id)
                    default:
                        break
                    }
                }
            }

            // Keep SharedDefaults in sync with Live Activity content state updates
            // so the shield always shows the latest step progress
            let contentTask = Task {
                for await content in activity.contentUpdates {
                    let cs = content.state
                    SharedDefaults.writeSessionContext(
                        taskTitle: cs.taskTitle,
                        stepsCompleted: cs.stepsCompleted,
                        stepsTotal: cs.stepsTotal,
                        currentStepTitle: cs.currentStepTitle,
                        lastCompletedStepTitle: cs.lastCompletedStepTitle
                    )
                    onContentStateUpdated?(cs)
                }
            }

            activityTasks[activity.id] = [tokenTask, stateTask, contentTask]
        }
    }

    @available(iOS 17.2, *)
    private func observePushToStartToken() async {
        for await data in Activity<FocusSessionAttributes>.pushToStartTokenUpdates {
            let tokenString = data.map { String(format: "%02.2hhx", $0) }.joined()
            print("Received push-to-start token: \(tokenString)")
            
            guard let uuid = UIDevice.current.identifierForVendor?.uuidString else {
                print("[ActivityManager] No vendor UUID available, skipping token registration")
                continue
            }
            let platformKey = "liveactivity_\(uuid)"
            do {
                try await APIClient.shared.registerDeviceToken(platform: platformKey, token: tokenString)
                print("[ActivityManager] Successfully registered liveactivity token.")
            } catch APIError.unauthorized {
                // Token refresh failed and user was logged out — stop observing
                print("[ActivityManager] Auth expired, stopping token observation.")
                return
            } catch {
                print("[ActivityManager] Failed to register liveactivity token: \(error)")
            }
        }
    }
}
