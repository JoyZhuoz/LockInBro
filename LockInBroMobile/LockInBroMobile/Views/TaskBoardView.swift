// TaskBoardView.swift — LockInBro
// Priority-sorted task list with step progress indicators

import SwiftUI

struct TaskBoardView: View {
    @Environment(AppState.self) private var appState
    @State private var filterStatus = "active"
    @State private var searchText = ""
    @State private var showingCreate = false
    @State private var navigationPath = NavigationPath()

    private let filters: [(id: String, label: String)] = [
        ("active", "Active"),
        ("pending", "Pending"),
        ("in_progress", "In Progress"),
        ("done", "Done"),
        ("all", "All")
    ]

    private var filteredTasks: [TaskOut] {
        var list = appState.tasks

        switch filterStatus {
        case "active":
            list = list.filter { $0.status != "done" && $0.status != "deferred" }
        case "all":
            break
        default:
            list = list.filter { $0.status == filterStatus }
        }

        if !searchText.isEmpty {
            list = list.filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                ($0.description?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }

        return list.sorted {
            // Overdue first, then by priority desc, then deadline asc
            if $0.isOverdue != $1.isOverdue { return $0.isOverdue }
            if $0.priority != $1.priority { return $0.priority > $1.priority }
            switch ($0.deadlineDate, $1.deadlineDate) {
            case (let a?, let b?): return a < b
            case (nil, _?): return false
            case (_?, nil): return true
            default: return false
            }
        }
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            VStack(spacing: 0) {
                filterBar
                Divider()
                content
            }
            .navigationTitle("Tasks")
            .navigationDestination(for: String.self) { taskId in
                TaskDetailView(taskId: taskId)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingCreate = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search tasks")
            .sheet(isPresented: $showingCreate) {
                CreateTaskView()
            }
            .onChange(of: appState.pendingOpenTaskId) { _, taskId in
                guard let taskId else { return }
                navigationPath.append(taskId)
                appState.pendingOpenTaskId = nil
            }
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(filters, id: \.id) { f in
                    FilterChip(label: f.label, isSelected: filterStatus == f.id) {
                        filterStatus = f.id
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if appState.isLoadingTasks && appState.tasks.isEmpty {
            ProgressView("Loading tasks…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if filteredTasks.isEmpty {
            ContentUnavailableView {
                Label("No Tasks", systemImage: "checklist")
            } description: {
                Text(searchText.isEmpty
                     ? "Use Brain Dump to capture what's on your mind."
                     : "No tasks match \"\(searchText)\".")
            } actions: {
                if searchText.isEmpty {
                    Button("New Task") { showingCreate = true }
                        .buttonStyle(.borderedProminent)
                }
            }
        } else {
            List {
                ForEach(filteredTasks) { task in
                    NavigationLink(value: task.id) {
                        TaskRowView(task: task)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            Task { await appState.deleteTask(task) }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        if task.status != "done" {
                            Button {
                                Task { await appState.markTaskDone(task) }
                            } label: {
                                Label("Done", systemImage: "checkmark")
                            }
                            .tint(.green)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .refreshable { await appState.loadTasks() }
        }
    }
}

// MARK: - Task Row

struct TaskRowView: View {
    let task: TaskOut
    @State private var steps: [StepOut] = []
    @State private var loaded = false

    private var completedCount: Int { steps.filter { $0.isDone }.count }
    private var progress: Double { steps.isEmpty ? 0 : Double(completedCount) / Double(steps.count) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Title row
            HStack(alignment: .top) {
                Text(task.title)
                    .font(.subheadline.bold())
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                StatusBadge(status: task.status)
            }

            // Meta row
            HStack(spacing: 10) {
                PriorityBadge(priority: task.priority)
                DeadlineLabel(task: task)
                if let mins = task.estimatedMinutes {
                    Label("\(mins)m", systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            // Step progress
            if loaded && !steps.isEmpty {
                VStack(spacing: 3) {
                    ProgressView(value: progress)
                        .tint(progress >= 1 ? .green : .blue)
                    Text("\(completedCount) / \(steps.count) steps")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
        .task {
            guard !loaded else { return }
            if let s = try? await APIClient.shared.getSteps(taskId: task.id) {
                steps = s
                loaded = true
            }
        }
    }
}

#Preview {
    TaskBoardView()
        .environment(AppState())
}
