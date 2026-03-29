//
//  DeviceActivityMonitorExtension.swift
//  LockInBroMonitor
//
//  When a distraction-app usage event exceeds the user's threshold,
//  this extension applies a ManagedSettings shield so the app shows
//  a "get back to work" overlay. Shields are cleared when the focus
//  session schedule ends or the main app calls stopMonitoring().
//

import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings

class DeviceActivityMonitorExtension: DeviceActivityMonitor {

    private let store = ManagedSettingsStore(named: .lockinbro)
    private let defaults = UserDefaults(suiteName: "group.com.adipu.LockInBroMobile")

    // MARK: - Threshold Reached

    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)

        // Load the user's selected distraction apps from the shared App Group
        guard let data = defaults?.data(forKey: "screenTimeSelection"),
              let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) else {
            return
        }

        // Apply shield to all selected apps — once ANY threshold fires, shield them all.
        // This is simpler and gives the user a single nudge rather than per-app shields
        // trickling in one-by-one.
        store.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        store.shield.applicationCategories = selection.categoryTokens.isEmpty
            ? nil
            : ShieldSettings.ActivityCategoryPolicy.specific(selection.categoryTokens)
    }

    // MARK: - Schedule Lifecycle

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        // Ensure shields are clear at the start of each monitoring interval
        store.shield.applications = nil
        store.shield.applicationCategories = nil
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        // Clean up shields when the schedule interval ends
        store.shield.applications = nil
        store.shield.applicationCategories = nil
    }
}

// Mirror the named store constant from the main app
extension ManagedSettingsStore.Name {
    static let lockinbro = ManagedSettingsStore.Name("lockinbro")
}
