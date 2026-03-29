// FocusSessionView.swift — Active focus session overlay

import SwiftUI
import Combine

struct FocusSessionView: View {
    @Environment(SessionManager.self) private var session

    @State private var elapsed: TimeInterval = 0
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            mainContent

            // Resume card overlay
            if session.showingResumeCard, let card = session.resumeCard {
                ResumeCardOverlay(card: card) {
                    session.showingResumeCard = false
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        .onReceive(timer) { _ in
            elapsed = session.sessionElapsed
        }
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.activeTask?.title ?? "Open Focus Session")
                        .font(.headline)
                        .lineLimit(1)
                    Text(formatElapsed(elapsed))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Spacer()

                HStack(spacing: 12) {
                    // Distraction count
                    if session.distractionCount > 0 {
                        Label("\(session.distractionCount)", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }

                    Button("End Session") {
                        Task { await session.endSession() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .foregroundStyle(.red)
                }
            }
            .padding()
            .background(Color.blue.opacity(0.08))

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {

                    // Current step card
                    if let step = session.currentStep {
                        CurrentStepCard(
                            step: step,
                            onMarkDone: { Task { await session.completeCurrentStep() } }
                        )
                    }

                    // Step progress
                    if !session.activeSteps.isEmpty {
                        StepProgressSection(
                            steps: session.activeSteps,
                            currentIndex: session.currentStepIndex
                        )
                    }

                    // Latest nudge
                    if let nudge = session.lastNudge {
                        NudgeCard(message: nudge)
                    }

                    // No task message
                    if session.activeTask == nil {
                        VStack(spacing: 8) {
                            Image(systemName: "target")
                                .font(.system(size: 32))
                                .foregroundStyle(.secondary)
                            Text("No task selected")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                            Text("You can still track time and detect distractions")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                    }
                }
                .padding()
            }

            // No active session
        }
    }
}

// MARK: - Current Step Card

private struct CurrentStepCard: View {
    let step: Step
    let onMarkDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Now", systemImage: "arrow.right.circle.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.blue)
                Spacer()
                if let mins = step.estimatedMinutes {
                    Text("~\(mins) min")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text(step.title)
                .font(.title3.bold())

            if let desc = step.description {
                Text(desc)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let note = step.checkpointNote {
                HStack(spacing: 6) {
                    Image(systemName: "bookmark.fill")
                        .font(.caption)
                        .foregroundStyle(.blue)
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.blue)
                        .italic()
                }
                .padding(8)
                .background(Color.blue.opacity(0.08))
                .clipShape(.rect(cornerRadius: 6))
            }

            Button {
                onMarkDone()
            } label: {
                Label("Mark Step Done", systemImage: "checkmark")
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(Color.blue.opacity(0.06))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.blue.opacity(0.2), lineWidth: 1)
        )
        .clipShape(.rect(cornerRadius: 12))
    }
}

// MARK: - Step Progress Section

private struct StepProgressSection: View {
    let steps: [Step]
    let currentIndex: Int

    private var completed: Int { steps.filter(\.isDone).count }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Progress")
                    .font(.subheadline.bold())
                Spacer()
                Text("\(completed) / \(steps.count) steps")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: Double(completed), total: Double(steps.count))
                .progressViewStyle(.linear)
                .tint(.blue)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                    HStack(spacing: 8) {
                        // Status icon
                        Group {
                            if step.isDone {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            } else if index == currentIndex {
                                Image(systemName: "circle.fill").foregroundStyle(.blue)
                            } else {
                                Image(systemName: "circle").foregroundStyle(.secondary)
                            }
                        }
                        .font(.system(size: 12))

                        Text(step.title)
                            .font(.caption)
                            .foregroundStyle(step.isDone ? .secondary : .primary)
                            .strikethrough(step.isDone)

                        Spacer()
                    }
                }
            }
        }
    }
}

// MARK: - Nudge Card

private struct NudgeCard: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "hand.wave.fill")
                .foregroundStyle(.orange)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text("Hey!")
                    .font(.caption.bold())
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.subheadline)
            }
        }
        .padding()
        .background(Color.orange.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.orange.opacity(0.2), lineWidth: 1)
        )
        .clipShape(.rect(cornerRadius: 10))
    }
}

// MARK: - Resume Card Overlay

struct ResumeCardOverlay: View {
    let card: ResumeCard
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Image(systemName: "sparkles")
                        .foregroundStyle(.blue)
                    Text("Welcome back!")
                        .font(.headline)
                    Spacer()
                    Button { onDismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    ResumeRow(icon: "clock", color: .blue, text: card.youWereDoing)
                    ResumeRow(icon: "arrow.right.circle", color: .green, text: card.nextStep)
                    ResumeRow(icon: "star.fill", color: .yellow, text: card.motivation)
                }

                Button {
                    onDismiss()
                } label: {
                    Text("Let's go!")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(24)
            .background(.regularMaterial)
            .clipShape(.rect(cornerRadius: 16))
            .shadow(radius: 20)
            .frame(maxWidth: 380)
            .padding()
        }
    }
}

private struct ResumeRow: View {
    let icon: String
    let color: Color
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 20)
            Text(text)
                .font(.subheadline)
        }
    }
}

// MARK: - Proactive Card

private struct ProactiveCardView: View {
    let card: ProactiveCard
    let onDismiss: () -> Void
    let onApprove: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: card.icon)
                    .foregroundStyle(.purple)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 2) {
                    Text(card.title)
                        .font(.subheadline.bold())
                        .foregroundStyle(.purple)
                    Text(bodyText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Button { onDismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            // Action buttons — shown for VLM-detected friction with proposed actions
            if case .vlmFriction(_, _, let actions) = card.source, !actions.isEmpty {
                HStack(spacing: 8) {
                    // Show up to 2 proposed actions
                    ForEach(Array(actions.prefix(2).enumerated()), id: \.offset) { _, action in
                        Button {
                            onApprove(action.label)
                        } label: {
                            Text(action.label)
                                .font(.caption.bold())
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.purple.opacity(0.15))
                                .clipShape(.capsule)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.purple)
                    }
                    Spacer()
                    Button("Not now") { onDismiss() }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .background(Color.purple.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.purple.opacity(0.2), lineWidth: 1)
        )
        .clipShape(.rect(cornerRadius: 10))
    }

    private var bodyText: String {
        switch card.source {
        case .vlmFriction(_, let description, _):
            return description ?? "I noticed something that might be slowing you down."
        case .appSwitchLoop(let apps, let count):
            return "You've switched between \(apps.joined(separator: " ↔ ")) \(count)× in a row — are you stuck?"
        case .sessionAction(_, _, let checkpoint, let reason, _):
            return checkpoint.isEmpty ? reason : "Left off: \(checkpoint)"
        }
    }
}

// MARK: - Helpers

private func formatElapsed(_ elapsed: TimeInterval) -> String {
    let minutes = Int(elapsed) / 60
    let seconds = Int(elapsed) % 60
    return String(format: "%02d:%02d", minutes, seconds)
}
