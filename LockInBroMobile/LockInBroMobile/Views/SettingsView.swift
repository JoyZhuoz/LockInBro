// SettingsView.swift — LockInBro
// App settings: notifications, focus preferences, account management

import SwiftUI
import UserNotifications
import FamilyControls

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var showLogoutConfirmation = false
    @State private var notificationsGranted = false
    @State private var checkInIntervalMinutes = 10
    @State private var distractionThresholdMinutes = SharedDefaults.distractionThresholdMinutes

    private let checkInOptions = [5, 10, 15, 20]
    private let thresholdOptions = [1, 2, 5]

    var body: some View {
        NavigationStack {
            Form {
                accountSection
                notificationsSection
                focusSection
                appInfoSection
                logoutSection
            }
            .navigationTitle("Settings")
            .confirmationDialog("Log out of LockInBro?", isPresented: $showLogoutConfirmation, titleVisibility: .visible) {
                Button("Log Out", role: .destructive) { appState.logout() }
                Button("Cancel", role: .cancel) {}
            }
            .task { await checkNotificationStatus() }
            .onChange(of: distractionThresholdMinutes) { _, newValue in
                SharedDefaults.distractionThresholdMinutes = newValue
            }
        }
    }

    // MARK: - Account Section

    private var accountSection: some View {
        Section("Account") {
            if let user = appState.currentUser {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(Color.blue.opacity(0.15))
                            .frame(width: 48, height: 48)
                        Text(String(user.displayName?.prefix(1) ?? "U"))
                            .font(.title2.bold())
                            .foregroundStyle(.blue)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(user.displayName ?? "User")
                            .font(.headline)
                        if let email = user.email {
                            Text(email)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)

                if let tz = user.timezone {
                    LabeledContent("Timezone", value: tz)
                }
            }
        }
    }

    // MARK: - Notifications Section

    private var notificationsSection: some View {
        Section {
            HStack {
                Label("Notifications", systemImage: notificationsGranted ? "bell.fill" : "bell.slash.fill")
                Spacer()
                if notificationsGranted {
                    Text("Enabled")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    Button("Enable") { requestNotifications() }
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
            }

            if notificationsGranted {
                Label("Deadline alerts", systemImage: "calendar.badge.exclamationmark")
                    .foregroundStyle(.primary)
                Label("Morning brief", systemImage: "sun.max")
                    .foregroundStyle(.primary)
                Label("Focus streak rewards", systemImage: "flame")
                    .foregroundStyle(.primary)
                Label("Gentle nudges (4+ hour idle)", systemImage: "hand.wave")
                    .foregroundStyle(.primary)
            }
        } header: {
            Text("Notifications")
        } footer: {
            if !notificationsGranted {
                Text("Enable notifications to receive deadline reminders, morning briefs, and focus nudges.")
            }
        }
    }

    @StateObject private var screenTimeManager = ScreenTimeManager.shared
    @State private var isPresentingActivityPicker = false

    // MARK: - Focus Section

    private var focusSection: some View {
        Section("Focus Session") {
            Picker("Check-in interval", selection: $checkInIntervalMinutes) {
                ForEach(checkInOptions, id: \.self) { mins in
                    Text("Every \(mins) minutes").tag(mins)
                }
            }

            Picker("Distraction threshold", selection: $distractionThresholdMinutes) {
                ForEach(thresholdOptions, id: \.self) { mins in
                    Text("\(mins) min off-task").tag(mins)
                }
            }
            
            if screenTimeManager.isAuthorized {
                Button(action: { isPresentingActivityPicker = true }) {
                    Label("Select Distraction Apps", systemImage: "app.badge")
                }
                .familyActivityPicker(
                    isPresented: $isPresentingActivityPicker,
                    selection: $screenTimeManager.selection
                )
            } else {
                Button(action: { screenTimeManager.requestAuthorization() }) {
                    Label("Enable Screen Time", systemImage: "hourglass")
                        .foregroundStyle(.blue)
                }
            }

            Label("Screenshot analysis: macOS only", systemImage: "camera.on.rectangle")
                .font(.caption)
                .foregroundStyle(.secondary)

            Label("App monitoring: DeviceActivityMonitor", systemImage: "app.badge.checkmark")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - App Info

    private var appInfoSection: some View {
        Section("About") {
            LabeledContent("Backend", value: "wahwa.com")
            LabeledContent("Platform") {
                Text(UIDevice.current.userInterfaceIdiom == .pad ? "iPadOS" : "iOS")
                    .foregroundStyle(.secondary)
            }
            LabeledContent("Version", value: "1.0 — YHack 2026")
            LabeledContent("AI", value: "Claude (Anthropic)")
            LabeledContent("Analytics", value: "Hex")
        }
    }

    // MARK: - Logout

    private var logoutSection: some View {
        Section {
            Button(role: .destructive) {
                showLogoutConfirmation = true
            } label: {
                HStack {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                    Text("Log Out")
                }
            }
        }
    }

    // MARK: - Notification Helpers

    private func checkNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        await MainActor.run {
            notificationsGranted = settings.authorizationStatus == .authorized
        }
    }

    private func requestNotifications() {
        Task {
            do {
                let granted = try await UNUserNotificationCenter.current()
                    .requestAuthorization(options: [.alert, .badge, .sound])
                await MainActor.run { notificationsGranted = granted }
            } catch {
                // User denied
            }
        }
    }
}

#Preview {
    SettingsView()
        .environment(AppState())
}
