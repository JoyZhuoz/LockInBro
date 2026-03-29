//
//  ShieldConfigurationExtension.swift
//  LockInBroShield
//
//  Customizes the shield overlay that appears on distraction apps
//  during a focus session. Shows the user's current task, step progress,
//  and two action buttons: "Back to Focus" and "Allow X more min".
//

import ManagedSettings
import ManagedSettingsUI
import UIKit

class ShieldConfigurationExtension: ShieldConfigurationDataSource {

    private let defaults = UserDefaults(suiteName: "group.com.adipu.LockInBroMobile")

    override func configuration(shielding application: Application) -> ShieldConfiguration {
        return buildShieldConfig(appName: application.localizedDisplayName)
    }

    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        return buildShieldConfig(appName: application.localizedDisplayName)
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        return buildShieldConfig(appName: webDomain.domain)
    }

    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
        return buildShieldConfig(appName: webDomain.domain)
    }

    // MARK: - Build Shield

    private func buildShieldConfig(appName: String?) -> ShieldConfiguration {
        let taskTitle = defaults?.string(forKey: "currentTaskTitle") ?? "your task"
        let completed = defaults?.integer(forKey: "currentStepsCompleted") ?? 0
        let total = defaults?.integer(forKey: "currentStepsTotal") ?? 0
        let currentStep = defaults?.string(forKey: "currentStepTitle")
        let lastCompletedStep = defaults?.string(forKey: "lastCompletedStepTitle")
        let threshold = defaults?.object(forKey: "distractionThresholdMinutes") as? Int ?? 2

        // Build subtitle with task context
        var subtitle: String
        if total > 0 {
            var secondLine = ""
            if let last = lastCompletedStep, let next = currentStep {
                secondLine = "You've just finished: \(last), next up is \(next)"
            } else if let next = currentStep {
                secondLine = "Next up is \(next)"
            } else if let last = lastCompletedStep {
                secondLine = "You've just finished: \(last)"
            }
            
            if secondLine.isEmpty {
                subtitle = "You're working on \"\(taskTitle)\" — \(completed)/\(total) steps done."
            } else {
                subtitle = "You're working on \"\(taskTitle)\" — \(completed)/\(total) steps done.\n\(secondLine)"
            }
        } else {
            subtitle = "You're supposed to be working on \"\(taskTitle)\"."
        }

        return ShieldConfiguration(
            backgroundBlurStyle: .systemThickMaterial,
            backgroundColor: UIColor.black.withAlphaComponent(0.85),
            icon: UIImage(systemName: "brain.head.profile"),
            title: ShieldConfiguration.Label(
                text: "Time to lock back in!",
                color: .white
            ),
            subtitle: ShieldConfiguration.Label(
                text: subtitle,
                color: UIColor.white.withAlphaComponent(0.8)
            ),
            primaryButtonLabel: ShieldConfiguration.Label(
                text: "Back to Focus",
                color: .white
            ),
            primaryButtonBackgroundColor: UIColor.systemBlue,
            secondaryButtonLabel: ShieldConfiguration.Label(
                text: "\(threshold) more min",
                color: UIColor.systemBlue
            )
        )
    }
}
