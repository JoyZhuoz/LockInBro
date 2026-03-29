// DashboardView.swift — LockInBro
// Analytics dashboard: task stats + Hex-powered distraction/focus trends

import SwiftUI

struct DashboardView: View {
    @Environment(AppState.self) private var appState
    @State private var analyticsJSON: [String: Any] = [:]
    @State private var isLoadingAnalytics = false
    @State private var analyticsError: String?

    // Derived from local task state (no network needed)
    private var totalTasks: Int { appState.tasks.count }
    private var pendingCount: Int { appState.tasks.filter { $0.status == "pending" }.count }
    private var inProgressCount: Int { appState.tasks.filter { $0.status == "in_progress" }.count }
    private var doneCount: Int { appState.tasks.filter { $0.status == "done" }.count }
    private var urgentCount: Int { appState.tasks.filter { $0.priority == 4 && $0.status != "done" }.count }
    private var overdueCount: Int { appState.tasks.filter { $0.isOverdue }.count }

    private var upcomingTasks: [TaskOut] {
        appState.tasks
            .filter { $0.deadlineDate != nil && $0.status != "done" }
            .sorted { ($0.deadlineDate ?? .distantFuture) < ($1.deadlineDate ?? .distantFuture) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    overviewSection
                    statusBreakdownSection
                    upcomingSection
                    hexAnalyticsSection
                }
                .padding()
            }
            .navigationTitle("Dashboard")
            .refreshable {
                await appState.loadTasks()
                await loadAnalytics()
            }
            .task { await loadAnalytics() }
        }
    }

    // MARK: - Overview Grid

    private var overviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Overview")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                StatCard(value: "\(totalTasks)", label: "Total Tasks", icon: "list.bullet.clipboard", color: .blue)
                StatCard(value: "\(inProgressCount)", label: "In Progress", icon: "arrow.triangle.2.circlepath", color: .orange)
                StatCard(value: "\(doneCount)", label: "Completed", icon: "checkmark.seal.fill", color: .green)
                StatCard(value: "\(urgentCount)", label: "Urgent", icon: "exclamationmark.triangle.fill", color: .red)
            }

            if overdueCount > 0 {
                HStack(spacing: 8) {
                    Image(systemName: "alarm.fill")
                        .foregroundStyle(.red)
                    Text("\(overdueCount) overdue task\(overdueCount == 1 ? "" : "s") need attention")
                        .font(.subheadline)
                        .foregroundStyle(.red)
                    Spacer()
                }
                .padding()
                .background(Color.red.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    // MARK: - Status Breakdown

    private var statusBreakdownSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Task Breakdown")
                .font(.headline)

            VStack(spacing: 10) {
                StatusBarRow(label: "Pending", count: pendingCount, total: totalTasks, color: .gray)
                StatusBarRow(label: "In Progress", count: inProgressCount, total: totalTasks, color: .blue)
                StatusBarRow(label: "Done", count: doneCount, total: totalTasks, color: .green)
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    // MARK: - Upcoming Deadlines

    private var upcomingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Upcoming Deadlines")
                .font(.headline)

            if upcomingTasks.isEmpty {
                Text("No upcoming deadlines")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                VStack(spacing: 0) {
                    ForEach(upcomingTasks.prefix(5)) { task in
                        HStack(spacing: 10) {
                            PriorityBadge(priority: task.priority)
                            Text(task.title)
                                .font(.subheadline)
                                .lineLimit(1)
                            Spacer()
                            if let date = task.deadlineDate {
                                Text(date, style: .relative)
                                    .font(.caption)
                                    .foregroundStyle(task.isOverdue ? .red : .secondary)
                                    .multilineTextAlignment(.trailing)
                            }
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal)

                        if task.id != upcomingTasks.prefix(5).last?.id {
                            Divider().padding(.leading)
                        }
                    }
                }
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    // MARK: - Hex Analytics Section

    private var hexAnalyticsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Hex Analytics", systemImage: "chart.xyaxis.line")
                    .font(.headline)
                Spacer()
                if isLoadingAnalytics {
                    ProgressView()
                }
            }

            if let err = analyticsError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(Color.orange.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else if !analyticsJSON.isEmpty {
                // Display raw analytics data
                analyticsContent
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.largeTitle)
                        .foregroundStyle(.purple)
                    Text("Distraction patterns, focus trends, and personalized ADHD insights appear here after your first focus sessions.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.purple.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    @ViewBuilder
    private var analyticsContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let totalSessions = analyticsJSON["total_sessions"] as? Int {
                HStack {
                    Label("Focus Sessions", systemImage: "timer")
                    Spacer()
                    Text("\(totalSessions)")
                        .font(.subheadline.bold())
                }
            }
            if let totalMinutes = analyticsJSON["total_focus_minutes"] as? Double {
                HStack {
                    Label("Focus Time", systemImage: "clock.fill")
                    Spacer()
                    Text("\(Int(totalMinutes))m")
                        .font(.subheadline.bold())
                }
            }
            if let distractionCount = analyticsJSON["total_distractions"] as? Int {
                HStack {
                    Label("Distractions", systemImage: "bell.badge")
                    Spacer()
                    Text("\(distractionCount)")
                        .font(.subheadline.bold())
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Data Loading

    private func loadAnalytics() async {
        isLoadingAnalytics = true
        analyticsError = nil
        do {
            let data = try await APIClient.shared.getAnalyticsSummary()
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                await MainActor.run { analyticsJSON = json }
            }
        } catch {
            await MainActor.run { analyticsError = error.localizedDescription }
        }
        await MainActor.run { isLoadingAnalytics = false }
    }
}

// MARK: - Status Bar Row

struct StatusBarRow: View {
    let label: String
    let count: Int
    let total: Int
    let color: Color

    private var progress: Double { total > 0 ? Double(count) / Double(total) : 0 }

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.subheadline)
                .frame(width: 80, alignment: .leading)
            ProgressView(value: progress)
                .tint(color)
            Text("\(count)")
                .font(.subheadline.bold())
                .foregroundStyle(color)
                .frame(width: 28, alignment: .trailing)
        }
    }
}

#Preview {
    DashboardView()
        .environment(AppState())
}
