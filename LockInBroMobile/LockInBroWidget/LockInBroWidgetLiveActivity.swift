//
//  LockInBroWidgetLiveActivity.swift
//  LockInBroWidget
//

import ActivityKit
import WidgetKit
import SwiftUI

struct LockInBroWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FocusSessionAttributes.self) { context in
            // Lock screen/banner UI
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "clock.fill")
                        .foregroundStyle(.blue)
                    Text("Focus Mode")
                        .font(.headline)
                        .fontWeight(.bold)
                    Spacer()
                    Text(Date(timeIntervalSince1970: TimeInterval(context.state.startedAt)), style: .timer)
                        .font(.title3.monospacedDigit())
                        .foregroundStyle(.blue)
                        .multilineTextAlignment(.trailing)
                }
                Text(context.state.taskTitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if context.state.stepsTotal > 0 {
                    HStack(spacing: 6) {
                        ProgressView(value: Double(context.state.stepsCompleted), total: Double(context.state.stepsTotal))
                            .tint(.blue)
                        Text("\(context.state.stepsCompleted)/\(context.state.stepsTotal)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    if let step = context.state.currentStepTitle {
                        Text("Now: \(step)")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1)
                    }
                }
            }
            .padding()
            .activityBackgroundTint(Color.black.opacity(0.8))
            .activitySystemActionForegroundColor(Color.white)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI
                DynamicIslandExpandedRegion(.leading) {
                    Label("Focus", systemImage: "clock.fill")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(Date(timeIntervalSince1970: TimeInterval(context.state.startedAt)), style: .timer)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.blue)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.taskTitle)
                        .font(.subheadline)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if context.state.stepsTotal > 0 {
                        Text("\(context.state.stepsCompleted)/\(context.state.stepsTotal) steps — \(context.state.currentStepTitle ?? "Stay locked in!")")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else {
                        Text("Stay locked in!")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            } compactLeading: {
                Image(systemName: "clock.fill")
                    .foregroundStyle(.blue)
            } compactTrailing: {
                Text(Date(timeIntervalSince1970: TimeInterval(context.state.startedAt)), style: .timer)
                    .font(.caption2.monospacedDigit())
                    .frame(maxWidth: 40)
            } minimal: {
                Image(systemName: "clock.fill")
                    .foregroundStyle(.blue)
            }
            .widgetURL(URL(string: "lockinbro://resume-session"))
            .keylineTint(Color.blue)
        }
    }
}

extension FocusSessionAttributes {
    fileprivate static var preview: FocusSessionAttributes {
        FocusSessionAttributes(sessionType: "Focus")
    }
}

extension FocusSessionAttributes.ContentState {
    fileprivate static var dummy: FocusSessionAttributes.ContentState {
        FocusSessionAttributes.ContentState(
            taskTitle: "Finish Physics Assignment",
            startedAt: Int(Date().addingTimeInterval(-120).timeIntervalSince1970),
            stepsCompleted: 2,
            stepsTotal: 5,
            currentStepTitle: "Solve problem set 3"
        )
     }
}

#Preview("Notification", as: .content, using: FocusSessionAttributes.preview) {
   LockInBroWidgetLiveActivity()
} contentStates: {
    FocusSessionAttributes.ContentState.dummy
}
