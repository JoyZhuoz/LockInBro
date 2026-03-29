// FloatingHUDView.swift — Content for the always-on-top focus HUD panel

import SwiftUI

struct FloatingHUDView: View {
    @Environment(SessionManager.self) private var session

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
        }
        .background(.ultraThinMaterial)
        .clipShape(.rect(cornerRadius: 12))
        .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: 4)
        .frame(width: 320)
        .animation(.spring(duration: 0.3), value: session.proactiveCard?.id)
        .animation(.spring(duration: 0.3), value: session.isExecuting)
        .animation(.spring(duration: 0.3), value: session.executorOutput?.title)
        .animation(.spring(duration: 0.3), value: session.monitoringError)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "eye.fill")
                .foregroundStyle(.blue)
                .font(.caption)

            Text(session.activeTask?.title ?? "Focus Session")
                .font(.caption.bold())
                .lineLimit(1)

            Spacer()

            // Pulse dot — green when capturing, orange when executing
            if session.isExecuting {
                Image(systemName: "bolt.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            } else {
                Circle()
                    .fill(session.isCapturing ? Color.green : Color.secondary.opacity(0.4))
                    .frame(width: 7, height: 7)
                    .overlay(
                        Circle()
                            .fill(session.isCapturing ? Color.green.opacity(0.3) : .clear)
                            .frame(width: 14, height: 14)
                    )
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        // Error / warning banner — shown above all other content when monitoring has a problem
        if let error = session.monitoringError {
            MonitoringErrorBanner(message: error)
                .transition(.move(edge: .top).combined(with: .opacity))
        }

        // Executor output sticky card (highest priority — persists until dismissed)
        if let output = session.executorOutput {
            ExecutorOutputCard(title: output.title, content: output.content) {
                session.executorOutput = nil
            }
            .transition(.move(edge: .top).combined(with: .opacity))
        }
        // Executing spinner
        else if session.isExecuting {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text("Executing action…")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            .padding(14)
            .transition(.opacity)
        }
        // Proactive friction card
        else if let card = session.proactiveCard {
            HUDCardView(card: card)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
        // Latest VLM summary (idle state)
        else if session.monitoringError == nil {
            Text(session.latestVlmSummary ?? "Monitoring your screen…")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(14)
                .transition(.opacity)
        }
    }
}

// MARK: - HUD Card (friction + proposed actions)

private struct HUDCardView: View {
    let card: ProactiveCard
    @Environment(SessionManager.self) private var session

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Title row
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: card.icon)
                    .foregroundStyle(.purple)

                VStack(alignment: .leading, spacing: 3) {
                    Text(card.title)
                        .font(.caption.bold())
                        .foregroundStyle(.purple)
                    Text(bodyText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(3)
                }

                Spacer()

                Button { session.dismissProactiveCard() } label: {
                    Image(systemName: "xmark")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            // Action buttons
            actionButtons
        }
        .padding(14)
        .background(Color.purple.opacity(0.07))
    }

    @ViewBuilder
    private var actionButtons: some View {
        switch card.source {
        case .vlmFriction(_, _, let actions) where !actions.isEmpty:
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(actions.prefix(2).enumerated()), id: \.offset) { index, action in
                    Button {
                        session.approveProactiveCard(actionIndex: index)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(action.label)
                                .font(.caption.bold())
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            if let details = action.details, !details.isEmpty {
                                Text(details)
                                    .font(.caption2)
                                    .foregroundStyle(.purple.opacity(0.7))
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.purple.opacity(0.12))
                        .clipShape(.rect(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.purple)
                }
                notNowButton
            }

        case .sessionAction(let type, _, _, _, _):
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    session.approveProactiveCard(actionIndex: 0)
                } label: {
                    Text(sessionActionButtonLabel(type))
                        .font(.caption.bold())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.purple.opacity(0.12))
                        .clipShape(.rect(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.purple)
                notNowButton
            }

        default:
            EmptyView()
        }
    }

    private var notNowButton: some View {
        Button("Not now — I'm good") { session.dismissProactiveCard() }
            .font(.caption)
            .foregroundStyle(.secondary)
            .buttonStyle(.plain)
            .padding(.top, 2)
    }

    private func sessionActionButtonLabel(_ type: String) -> String {
        switch type {
        case "resume":    return "Resume session"
        case "switch":    return "Switch to this task"
        case "complete":  return "Mark complete"
        case "start_new": return "Start focus session"
        default:          return "OK"
        }
    }

    private var bodyText: String {
        switch card.source {
        case .vlmFriction(_, let description, _):
            return description ?? "I noticed something that might be slowing you down."
        case .appSwitchLoop(let apps, let count):
            return "You've switched between \(apps.joined(separator: " ↔ ")) \(count)× — are you stuck?"
        case .sessionAction(_, _, let checkpoint, let reason, _):
            if !checkpoint.isEmpty { return "Left off: \(checkpoint)" }
            return reason.isEmpty ? "Argus noticed a session change." : reason
        }
    }
}

// MARK: - Monitoring Error Banner

private struct MonitoringErrorBanner: View {
    let message: String
    @Environment(SessionManager.self) private var session

    private var isRestarting: Bool { message.contains("restarting") }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: isRestarting ? "arrow.clockwise" : "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(isRestarting ? .orange : .red)
                    .symbolEffect(.pulse, isActive: isRestarting)

                Text(message)
                    .font(.caption)
                    .foregroundStyle(isRestarting ? .orange : .red)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }

            if !isRestarting {
                Button("Retry") { session.retryMonitoring() }
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Color.red.opacity(0.8))
                    .clipShape(.rect(cornerRadius: 6))
                    .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(isRestarting ? Color.orange.opacity(0.08) : Color.red.opacity(0.08))
        .overlay(
            Rectangle()
                .frame(width: 3)
                .foregroundStyle(isRestarting ? Color.orange : Color.red),
            alignment: .leading
        )
    }
}

// MARK: - Executor Output Sticky Card

private struct ExecutorOutputCard: View {
    let title: String
    let content: String
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
                Text(title)
                    .font(.caption.bold())
                    .foregroundStyle(.green)
                    .lineLimit(1)
                Spacer()
                Button { onDismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            ScrollView {
                Text(content)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 120)

            Button("Dismiss") { onDismiss() }
                .font(.caption)
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(14)
        .background(Color.green.opacity(0.07))
    }
}
