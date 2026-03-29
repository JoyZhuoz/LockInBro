// SharedDefaults.swift — LockInBro
// Shared App Group UserDefaults for communication between main app and extensions.
// All Screen Time extensions (Monitor, Shield, ShieldAction) read from this store
// to get the current task context and user preferences.

import Foundation
import FamilyControls

enum SharedDefaults {
    static let suiteName = "group.com.adipu.LockInBroMobile"

    static var store: UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }

    // MARK: - Keys

    private enum Key {
        static let distractionThreshold = "distractionThresholdMinutes"
        static let appSelection = "screenTimeSelection"
        static let taskTitle = "currentTaskTitle"
        static let stepsCompleted = "currentStepsCompleted"
        static let stepsTotal = "currentStepsTotal"
        static let currentStepTitle = "currentStepTitle"
        static let lastCompletedStepTitle = "lastCompletedStepTitle"
        static let sessionActive = "sessionActive"
    }

    // MARK: - Distraction Threshold

    static var distractionThresholdMinutes: Int {
        get { store.object(forKey: Key.distractionThreshold) as? Int ?? 2 }
        set { store.set(newValue, forKey: Key.distractionThreshold) }
    }

    // MARK: - App Selection (encoded FamilyActivitySelection)

    static func saveAppSelection(_ selection: FamilyActivitySelection) {
        if let data = try? JSONEncoder().encode(selection) {
            store.set(data, forKey: Key.appSelection)
        }
    }

    static func loadAppSelection() -> FamilyActivitySelection? {
        guard let data = store.data(forKey: Key.appSelection) else { return nil }
        return try? JSONDecoder().decode(FamilyActivitySelection.self, from: data)
    }

    // MARK: - Current Session Context (written by main app, read by shield extension)

    static var sessionActive: Bool {
        get { store.bool(forKey: Key.sessionActive) }
        set { store.set(newValue, forKey: Key.sessionActive) }
    }

    static var taskTitle: String? {
        get { store.string(forKey: Key.taskTitle) }
        set { store.set(newValue, forKey: Key.taskTitle) }
    }

    static var stepsCompleted: Int {
        get { store.integer(forKey: Key.stepsCompleted) }
        set { store.set(newValue, forKey: Key.stepsCompleted) }
    }

    static var stepsTotal: Int {
        get { store.integer(forKey: Key.stepsTotal) }
        set { store.set(newValue, forKey: Key.stepsTotal) }
    }

    static var currentStepTitle: String? {
        get { store.string(forKey: Key.currentStepTitle) }
        set { store.set(newValue, forKey: Key.currentStepTitle) }
    }

    static var lastCompletedStepTitle: String? {
        get { store.string(forKey: Key.lastCompletedStepTitle) }
        set { store.set(newValue, forKey: Key.lastCompletedStepTitle) }
    }

    /// Write full session context atomically (called when session starts or Live Activity updates).
    static func writeSessionContext(
        taskTitle: String,
        stepsCompleted: Int,
        stepsTotal: Int,
        currentStepTitle: String?,
        lastCompletedStepTitle: String?
    ) {
        self.sessionActive = true
        self.taskTitle = taskTitle
        self.stepsCompleted = stepsCompleted
        self.stepsTotal = stepsTotal
        self.currentStepTitle = currentStepTitle
        self.lastCompletedStepTitle = lastCompletedStepTitle
    }

    /// Clear session context (called when session ends).
    static func clearSessionContext() {
        sessionActive = false
        store.removeObject(forKey: Key.taskTitle)
        store.removeObject(forKey: Key.stepsCompleted)
        store.removeObject(forKey: Key.stepsTotal)
        store.removeObject(forKey: Key.currentStepTitle)
        store.removeObject(forKey: Key.lastCompletedStepTitle)
    }
}
