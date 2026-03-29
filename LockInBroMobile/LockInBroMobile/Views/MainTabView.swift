// MainTabView.swift — LockInBro
// Root tab navigation after login

import SwiftUI

struct MainTabView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        TabView {
            BrainDumpView()
                .tabItem { Label("Brain Dump", systemImage: "brain") }

            TaskBoardView()
                .tabItem { Label("Tasks", systemImage: "checklist") }

            DashboardView()
                .tabItem { Label("Dashboard", systemImage: "chart.bar.xaxis") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gear") }
        }
        .task {
            await appState.loadTasks()
        }
    }
}

#Preview {
    MainTabView()
        .environment(AppState())
}
