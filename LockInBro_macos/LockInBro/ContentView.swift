// ContentView.swift — Auth gate + main tab navigation

import SwiftUI

struct ContentView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(SessionManager.self) private var session

    @State private var selectedTab: AppTab = .tasks
    @State private var showingSettings = false
    @AppStorage("geminiApiKey") private var geminiApiKey = ""

    enum AppTab: String, CaseIterable {
        case tasks = "Tasks"
        case brainDump = "Brain Dump"
        case focusSession = "Focus"

        var systemImage: String {
            switch self {
            case .tasks: return "checklist"
            case .brainDump: return "brain.head.profile"
            case .focusSession: return "target"
            }
        }
    }

    var body: some View {
        if !auth.isLoggedIn {
            LoginView()
        } else {
            mainContent
        }
    }

    private var mainContent: some View {
        NavigationSplitView {
            // Sidebar
            VStack(spacing: 0) {
                List(AppTab.allCases, id: \.self, selection: $selectedTab) { tab in
                    Label(tab.rawValue, systemImage: tab.systemImage)
                        .badge(tab == .focusSession && session.isSessionActive ? "●" : nil)
                }

                Divider()

                HStack {
                    Button {
                        showingSettings = true
                    } label: {
                        Label("Settings", systemImage: "gear")
                            .font(.subheadline)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        auth.logout()
                    } label: {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Sign out")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180)
            .navigationTitle("LockInBro")
            .sheet(isPresented: $showingSettings) {
                SettingsSheet(geminiApiKey: $geminiApiKey)
            }
        } detail: {
            NavigationStack {
                detailView
                    .navigationTitle(selectedTab.rawValue)
            }
        }
        .frame(minWidth: 700, minHeight: 500)
        // Auto-navigate to Focus tab when a session becomes active
        .onChange(of: session.isSessionActive) { _, isActive in
            if isActive { selectedTab = .focusSession }
        }
        // Active session banner at bottom
        .safeAreaInset(edge: .bottom) {
            if session.isSessionActive {
                sessionBanner
            }
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch selectedTab {
        case .tasks:
            TaskBoardView()
        case .brainDump:
            BrainDumpView(onGoToTasks: { selectedTab = .tasks })
        case .focusSession:
            if session.isSessionActive {
                FocusSessionView()
            } else {
                StartSessionPlaceholder {
                    selectedTab = .tasks
                }
            }
        }
    }

    private var sessionBanner: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(.green)
                .frame(width: 8, height: 8)
                .overlay(
                    Circle()
                        .fill(.green.opacity(0.3))
                        .frame(width: 16, height: 16)
                )

            if let task = session.activeTask {
                Text("Focusing on: \(task.title)")
                    .font(.subheadline.bold())
                    .lineLimit(1)
            } else {
                Text("Focus session active")
                    .font(.subheadline.bold())
            }

            if let step = session.currentStep {
                Text("· \(step.title)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button("View Session") {
                selectedTab = .focusSession
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button {
                Task { await session.endSession() }
            } label: {
                Image(systemName: "stop.circle.fill")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .help("End session")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.thinMaterial)
        .overlay(alignment: .top) { Divider() }
    }
}

// MARK: - Settings Sheet

private struct SettingsSheet: View {
    @Binding var geminiApiKey: String
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Settings")
                .font(.title2.bold())

            VStack(alignment: .leading, spacing: 6) {
                Text("Gemini API Key")
                    .font(.subheadline.bold())
                Text("Required for the VLM screen analysis agent.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                SecureField("AIza…", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape)
                Button("Save") {
                    geminiApiKey = draft.trimmingCharacters(in: .whitespaces)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return)
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 420)
        .onAppear { draft = geminiApiKey }
    }
}

// MARK: - Start Session Placeholder

private struct StartSessionPlaceholder: View {
    let onGoToTasks: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "target")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text("No active session")
                .font(.title2.bold())

            Text("Go to your task board and tap the play button to start a focus session on a task.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)

            Button {
                onGoToTasks()
            } label: {
                Label("Go to Tasks", systemImage: "checklist")
                    .frame(width: 160)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
