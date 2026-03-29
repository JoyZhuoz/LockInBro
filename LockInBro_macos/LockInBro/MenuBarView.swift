// MenuBarView.swift — Menu bar popover content

import SwiftUI

struct MenuBarView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(SessionManager.self) private var session

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Session status
            sessionStatusSection

            Divider()

            // Actions
            actionsSection

            Divider()

            // Bottom
            HStack {
                Text(auth.currentUser?.displayName ?? auth.currentUser?.email ?? "LockInBro")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Sign Out") { auth.logout() }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(width: 280)
    }

    private var sessionStatusSection: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(session.isSessionActive ? Color.green : Color.secondary.opacity(0.4))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.isSessionActive ? "Session Active" : "No Active Session")
                    .font(.subheadline.bold())

                if let task = session.activeTask {
                    Text(task.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if session.isSessionActive {
                    Text("No task selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if session.isSessionActive, session.distractionCount > 0 {
                Label("\(session.distractionCount)", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var actionsSection: some View {
        VStack(spacing: 2) {
            if session.isSessionActive {
                MenuBarButton(
                    icon: "stop.circle",
                    title: "End Session",
                    color: .red
                ) {
                    Task { await session.endSession() }
                }

                if let step = session.currentStep {
                    MenuBarButton(
                        icon: "checkmark.circle",
                        title: "Mark '\(step.title.prefix(25))…' Done",
                        color: .green
                    ) {
                        Task { await session.completeCurrentStep() }
                    }
                }

                MenuBarButton(
                    icon: "arrow.uturn.backward.circle",
                    title: "Show Resume Card",
                    color: .blue
                ) {
                    Task { await session.fetchResumeCard() }
                }
            } else {
                MenuBarButton(
                    icon: "play.circle",
                    title: "Start Focus Session",
                    color: .blue
                ) {
                    // Opens main window — user picks task there
                    NSApp.activate(ignoringOtherApps: true)
                    NSApp.windows.first?.makeKeyAndOrderFront(nil)
                }
            }

            MenuBarButton(
                icon: "macwindow",
                title: "Open LockInBro",
                color: .primary
            ) {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows.first?.makeKeyAndOrderFront(nil)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Menu Bar Button

private struct MenuBarButton: View {
    let icon: String
    let title: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .frame(width: 16)
                Text(title)
                    .font(.subheadline)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .background(Color.clear)
        .hoverEffect()
    }
}

// hoverEffect for macOS (no-op style that adds highlight on hover)
private extension View {
    @ViewBuilder
    func hoverEffect() -> some View {
        self.onHover { _ in }  // triggers redraw; real hover highlight handled below
    }
}
