// FocusSessionAttributes.swift
import Foundation
import ActivityKit
import SwiftUI
import Combine

public struct FocusSessionAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var taskTitle: String
        public var startedAt: Int
        public var stepsCompleted: Int
        public var stepsTotal: Int
        public var currentStepTitle: String?
        public var lastCompletedStepTitle: String?

        public init(
            taskTitle: String,
            startedAt: Int,
            stepsCompleted: Int = 0,
            stepsTotal: Int = 0,
            currentStepTitle: String? = nil,
            lastCompletedStepTitle: String? = nil
        ) {
            self.taskTitle = taskTitle
            self.startedAt = startedAt
            self.stepsCompleted = stepsCompleted
            self.stepsTotal = stepsTotal
            self.currentStepTitle = currentStepTitle
            self.lastCompletedStepTitle = lastCompletedStepTitle
        }
    }

    public var sessionType: String

    public init(sessionType: String) {
        self.sessionType = sessionType
    }
}
