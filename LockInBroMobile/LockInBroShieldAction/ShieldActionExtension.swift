//
//  ShieldActionExtension.swift
//  LockInBroShieldAction
//
//  Handles shield button taps:
//    Primary "Back to Focus" → closes the distraction app
//    Secondary "X more min" → dismisses the shield (user can keep using the app;
//      the shield will reappear on the next monitoring interval reset)
//

import ManagedSettings
import DeviceActivity
import FamilyControls
import Foundation

class ShieldActionExtension: ShieldActionDelegate {

    private let store = ManagedSettingsStore(named: .lockinbro)

    override func handle(
        action: ShieldAction,
        for application: ApplicationToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        switch action {
        case .primaryButtonPressed:
            // "Back to Focus" — close the distraction app
            completionHandler(.close)
        case .secondaryButtonPressed:
            store.shield.applications = nil
            store.shield.applicationCategories = nil
            grantOneMoreMinute()
            completionHandler(.none)
        default:
            completionHandler(.close)
        }
    }

    override func handle(
        action: ShieldAction,
        for webDomain: WebDomainToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        switch action {
        case .primaryButtonPressed:
            completionHandler(.close)
        case .secondaryButtonPressed:
            store.shield.applications = nil
            store.shield.applicationCategories = nil
            grantOneMoreMinute()
            completionHandler(.none)
        default:
            completionHandler(.close)
        }
    }

    override func handle(
        action: ShieldAction,
        for category: ActivityCategoryToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        switch action {
        case .primaryButtonPressed:
            completionHandler(.close)
        case .secondaryButtonPressed:
            store.shield.applications = nil
            store.shield.applicationCategories = nil
            grantOneMoreMinute()
            completionHandler(.none)
        default:
            completionHandler(.close)
        }
    }
    private func grantOneMoreMinute() {
        let defaults = UserDefaults(suiteName: "group.com.adipu.LockInBroMobile")
        guard let data = defaults?.data(forKey: "screenTimeSelection"),
              let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) else {
            return
        }

        let center = DeviceActivityCenter()
        let now = Date()
        var startComp = Calendar.current.dateComponents([.hour, .minute], from: now)
        if startComp.hour == 23 && startComp.minute == 59 {
            startComp.hour = 0
            startComp.minute = 0
        }

        let schedule = DeviceActivitySchedule(
            intervalStart: startComp,
            intervalEnd: DateComponents(hour: 23, minute: 59),
            repeats: false
        )

        var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]
        let threshold = DateComponents(minute: 1)

        for token in selection.applicationTokens {
            let eventName = DeviceActivityEvent.Name("dist_ext_\(token.hashValue)")
            events[eventName] = DeviceActivityEvent(applications: [token], threshold: threshold)
        }
        for token in selection.categoryTokens {
            let eventName = DeviceActivityEvent.Name("dist_cat_ext_\(token.hashValue)")
            events[eventName] = DeviceActivityEvent(categories: [token], threshold: threshold)
        }

        let activityName = DeviceActivityName("lockinbro_extension_1m")
        try? center.startMonitoring(activityName, during: schedule, events: events)
    }
}

extension ManagedSettingsStore.Name {
    static let lockinbro = ManagedSettingsStore.Name("lockinbro")
}
