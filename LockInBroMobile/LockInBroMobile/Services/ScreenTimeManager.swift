// ScreenTimeManager.swift — LockInBro
// Manages FamilyControls authorization, app selection, and DeviceActivity scheduling.
// When a focus session starts, schedules monitoring with threshold-based events.
// The DeviceActivityMonitor extension applies shields when thresholds are exceeded.

import Foundation
import FamilyControls
import DeviceActivity
import ManagedSettings
import SwiftUI
import Combine

class ScreenTimeManager: ObservableObject {
    static let shared = ScreenTimeManager()

    @Published var isAuthorized: Bool = false
    @Published var selection = FamilyActivitySelection() {
        didSet {
            SharedDefaults.saveAppSelection(selection)
        }
    }

    /// Named store that the Monitor extension also uses — both must reference the same name.
    let store = ManagedSettingsStore(named: .lockinbro)
    private let center = DeviceActivityCenter()

    private init() {
        if let saved = SharedDefaults.loadAppSelection() {
            selection = saved
        }
        isAuthorized = AuthorizationCenter.shared.authorizationStatus == .approved
    }

    // MARK: - Authorization

    func requestAuthorization() {
        Task {
            do {
                try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
                await MainActor.run {
                    self.isAuthorized = AuthorizationCenter.shared.authorizationStatus == .approved
                }
            } catch {
                print("[ScreenTime] Failed to authorize: \(error)")
            }
        }
    }

    // MARK: - Session Lifecycle

    /// Start monitoring distraction apps. Called when a focus session begins.
    func startMonitoring() {
        guard isAuthorized else {
            print("[ScreenTime] Not authorized, skipping monitoring")
            return
        }
        guard !selection.applicationTokens.isEmpty || !selection.categoryTokens.isEmpty else {
            print("[ScreenTime] No apps selected, skipping monitoring")
            return
        }

        // Clear any existing shields and stop previous schedule
        store.shield.applications = nil
        store.shield.applicationCategories = nil
        center.stopMonitoring([.focusSession])

        let threshold = SharedDefaults.distractionThresholdMinutes
        let thresholdInterval = DateComponents(minute: threshold)

        // Build events — one per selected app token with the user's threshold
        var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]
        for token in selection.applicationTokens {
            let eventName = DeviceActivityEvent.Name("distraction_\(token.hashValue)")
            events[eventName] = DeviceActivityEvent(
                applications: [token],
                categories: [],
                webDomains: [],
                threshold: thresholdInterval
            )
        }
        // Also add category-level events
        for token in selection.categoryTokens {
            let eventName = DeviceActivityEvent.Name("distraction_cat_\(token.hashValue)")
            events[eventName] = DeviceActivityEvent(
                applications: [],
                categories: [token],
                webDomains: [],
                threshold: thresholdInterval
            )
        }

        let now = Date()
        var startComp = Calendar.current.dateComponents([.hour, .minute], from: now)
        // Prevent intervalStart == intervalEnd collision
        if startComp.hour == 23 && startComp.minute == 59 {
            startComp.hour = 0
            startComp.minute = 0
        }

        // Schedule covers from exactly "now" to 23:59.
        // Starting at `now` resets the cumulative tracking counter, 
        // ensuring any usage earlier in the day doesn't break our threshold logic.
        let schedule = DeviceActivitySchedule(
            intervalStart: startComp,
            intervalEnd: DateComponents(hour: 23, minute: 59),
            repeats: false
        )

        do {
            try center.startMonitoring(.focusSession, during: schedule, events: events)
            print("[ScreenTime] Started monitoring \(events.count) event(s), threshold=\(threshold)min")
        } catch {
            print("[ScreenTime] Failed to start monitoring: \(error)")
        }
    }

    /// Stop monitoring and clear all shields. Called when a focus session ends.
    func stopMonitoring() {
        center.stopMonitoring([.focusSession, DeviceActivityName("lockinbro_extension_1m")])
        store.shield.applications = nil
        store.shield.applicationCategories = nil
        print("[ScreenTime] Stopped monitoring, shields cleared")
    }
}

// MARK: - Named constants

extension DeviceActivityName {
    static let focusSession = DeviceActivityName("lockinbro_focus_session")
}

extension ManagedSettingsStore.Name {
    static let lockinbro = ManagedSettingsStore.Name("lockinbro")
}
