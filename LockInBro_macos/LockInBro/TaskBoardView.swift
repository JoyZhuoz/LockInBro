// TaskBoardView.swift — Task list with priority sorting and step progress

import SwiftUI

struct TaskBoardView: View {
    @Environment(SessionManager.self) private var session

    @State private var tasks: [AppTask] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedFilter: String? = nil
    @State private var expandedTaskId: String?
    @State private var taskSteps: [String: [Step]] = [:]
    @State private var loadingStepsFor: String?
    @State private var editingTask: AppTask?

    // (statusValue, displayLabel) — nil statusValue means "all tasks"
    private let filters: [(String?, String)] = [
        (nil, "All"),
        ("in_progress", "In Progress"),
        ("pending", "Pending"),
        ("done", "Done")
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Filter tabs
            HStack(spacing: 4) {
                ForEach(filters, id: \.1) { filter in
                    Button(filter.1) {
                        selectedFilter = filter.0
                        Task { await loadTasks() }
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(selectedFilter == filter.0 ? Color.accentColor : Color.clear)
                    .foregroundStyle(selectedFilter == filter.0 ? .white : .primary)
                    .clipShape(.capsule)
                    .fontWeight(selectedFilter == filter.0 ? .semibold : .regular)
                }
                Spacer()
                Button {
                    Task { await loadTasks() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("Refresh")
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            if isLoading {
                ProgressView("Loading tasks…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if tasks.isEmpty {
                ContentUnavailableView(
                    "No tasks",
                    systemImage: "checklist",
                    description: Text("Use Brain Dump to capture your tasks")
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(sortedTasks) { task in
                            TaskRow(
                                task: task,
                                isExpanded: expandedTaskId == task.id,
                                steps: taskSteps[task.id] ?? [],
                                isLoadingSteps: loadingStepsFor == task.id,
                                onToggle: { toggleExpanded(task) },
                                onStartFocus: { startFocus(task) },
                                onEdit: { editingTask = task },
                                onDelete: { Task { await deleteTask(task) } },
                                onCompleteStep: { step in
                                    Task { await completeStep(step, taskId: task.id) }
                                }
                            )
                        }
                    }
                    .padding()
                }
            }

            if let err = errorMessage ?? session.errorMessage {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }
            if session.isLoading {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Starting session…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
        }
        .task { await loadTasks() }
        .sheet(item: $editingTask) { task in
            EditTaskSheet(task: task) { updated in
                if let idx = tasks.firstIndex(where: { $0.id == updated.id }) {
                    tasks[idx] = updated
                }
                editingTask = nil
            } onDismiss: {
                editingTask = nil
            }
        }
    }

    private var sortedTasks: [AppTask] {
        tasks.sorted { a, b in
            if a.priority != b.priority { return a.priority > b.priority }
            return a.createdAt > b.createdAt
        }
    }

    private func loadTasks() async {
        isLoading = true
        errorMessage = nil
        do {
            var all = try await APIClient.shared.getTasks(status: selectedFilter)
            // Soft-deleted tasks have status='deferred' — hide them from the All view
            if selectedFilter == nil {
                all = all.filter { $0.status != "deferred" }
            }
            tasks = all
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func toggleExpanded(_ task: AppTask) {
        if expandedTaskId == task.id {
            expandedTaskId = nil
        } else {
            expandedTaskId = task.id
            if taskSteps[task.id] == nil {
                Task { await loadSteps(taskId: task.id) }
            }
        }
    }

    private func loadSteps(taskId: String) async {
        loadingStepsFor = taskId
        do {
            taskSteps[taskId] = try await APIClient.shared.getSteps(taskId: taskId)
        } catch {
            // Silently fail for step loading
        }
        loadingStepsFor = nil
    }

    private func startFocus(_ task: AppTask) {
        session.errorMessage = nil
        Task { await session.startSession(task: task) }
    }

    private func deleteTask(_ task: AppTask) async {
        // Optimistically remove from UI immediately
        tasks.removeAll { $0.id == task.id }
        do {
            try await APIClient.shared.deleteTask(taskId: task.id)
        } catch {
            // Restore on failure
            tasks.append(task)
            errorMessage = error.localizedDescription
        }
    }

    private func completeStep(_ step: Step, taskId: String) async {
        do {
            let updated = try await APIClient.shared.completeStep(stepId: step.id)
            if var steps = taskSteps[taskId] {
                if let idx = steps.firstIndex(where: { $0.id == updated.id }) {
                    steps[idx] = updated
                    taskSteps[taskId] = steps
                }
            }
        } catch {}
    }
}

// MARK: - Task Row

private struct TaskRow: View {
    let task: AppTask
    let isExpanded: Bool
    let steps: [Step]
    let isLoadingSteps: Bool
    let onToggle: () -> Void
    let onStartFocus: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onCompleteStep: (Step) -> Void

    private var completedSteps: Int { steps.filter(\.isDone).count }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            HStack(spacing: 10) {
                // Priority badge
                PriorityBadge(priority: task.priority)

                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title)
                        .font(.headline)
                        .lineLimit(2)

                    HStack(spacing: 8) {
                        if let deadline = task.deadline {
                            Label(formatDeadline(deadline), systemImage: "calendar")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if !steps.isEmpty {
                            Label("\(completedSteps)/\(steps.count) steps", systemImage: "checklist")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let mins = task.estimatedMinutes {
                            Label("~\(mins)m", systemImage: "clock")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()

                // Actions
                HStack(spacing: 6) {
                    Button {
                        onStartFocus()
                    } label: {
                        Image(systemName: "play.circle.fill")
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                    .help("Start focus session")

                    Button {
                        onEdit()
                    } label: {
                        Image(systemName: "pencil.circle")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Edit task")

                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.red.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    .help("Delete task")

                    Button {
                        onToggle()
                    } label: {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()

            // Step progress bar
            if !steps.isEmpty {
                ProgressView(value: Double(completedSteps), total: Double(steps.count))
                    .progressViewStyle(.linear)
                    .padding(.horizontal)
                    .padding(.bottom, isExpanded ? 0 : 8)
            }

            // Expanded steps list
            if isExpanded {
                Divider().padding(.horizontal)

                if isLoadingSteps {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding()
                } else if steps.isEmpty {
                    Text("No steps yet — generate a plan to get started")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding()
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(steps.sorted { $0.sortOrder < $1.sortOrder }) { step in
                            StepRow(step: step, onComplete: { onCompleteStep(step) })
                        }
                    }
                    .padding()
                }
            }
        }
        .background(.background)
        .clipShape(.rect(cornerRadius: 10))
        .shadow(color: .black.opacity(0.07), radius: 4, x: 0, y: 2)
    }

    private func formatDeadline(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: iso) else {
            formatter.formatOptions = [.withInternetDateTime]
            guard let date2 = formatter.date(from: iso) else { return iso }
            return RelativeDateTimeFormatter().localizedString(for: date2, relativeTo: .now)
        }
        return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: .now)
    }
}

// MARK: - Step Row

private struct StepRow: View {
    let step: Step
    let onComplete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button {
                if !step.isDone { onComplete() }
            } label: {
                Image(systemName: step.isDone ? "checkmark.circle.fill" : (step.isActive ? "circle.fill" : "circle"))
                    .foregroundStyle(step.isDone ? .green : (step.isActive ? .blue : .secondary))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(step.title)
                    .font(.subheadline)
                    .strikethrough(step.isDone)
                    .foregroundStyle(step.isDone ? .secondary : .primary)

                if let note = step.checkpointNote {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.blue)
                        .italic()
                }
            }

            Spacer()

            if let mins = step.estimatedMinutes {
                Text("~\(mins)m")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Edit Task Sheet

private struct EditTaskSheet: View {
    let task: AppTask
    let onSave: (AppTask) -> Void
    let onDismiss: () -> Void

    @State private var title: String
    @State private var description: String
    @State private var priority: Int
    @State private var isSaving = false
    @State private var error: String?

    init(task: AppTask, onSave: @escaping (AppTask) -> Void, onDismiss: @escaping () -> Void) {
        self.task = task
        self.onSave = onSave
        self.onDismiss = onDismiss
        _title = State(initialValue: task.title)
        _description = State(initialValue: task.description ?? "")
        _priority = State(initialValue: task.priority)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Edit Task").font(.headline)
                Spacer()
                Button("Cancel") { onDismiss() }.buttonStyle(.bordered)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Title").font(.caption).foregroundStyle(.secondary)
                TextField("Title", text: $title)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Description").font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $description)
                    .font(.body)
                    .frame(height: 80)
                    .padding(4)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Priority").font(.caption).foregroundStyle(.secondary)
                Picker("Priority", selection: $priority) {
                    Text("Low").tag(1)
                    Text("Medium").tag(2)
                    Text("High").tag(3)
                    Text("Urgent").tag(4)
                }
                .pickerStyle(.segmented)
            }

            if let err = error {
                Text(err).font(.caption).foregroundStyle(.red)
            }

            Button {
                Task { await save() }
            } label: {
                Group {
                    if isSaving { ProgressView() }
                    else { Text("Save Changes") }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 32)
            }
            .buttonStyle(.borderedProminent)
            .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
        }
        .padding(24)
        .frame(width: 380)
    }

    private func save() async {
        isSaving = true
        error = nil
        do {
            let updated = try await APIClient.shared.updateTask(
                taskId: task.id,
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                description: description.isEmpty ? nil : description,
                priority: priority
            )
            onSave(updated)
        } catch {
            self.error = error.localizedDescription
        }
        isSaving = false
    }
}

// MARK: - Priority Badge

private struct PriorityBadge: View {
    let priority: Int

    private var color: Color {
        switch priority {
        case 4: return .red
        case 3: return .orange
        case 2: return .yellow
        case 1: return .green
        default: return .gray
        }
    }

    private var label: String {
        switch priority {
        case 4: return "URGENT"
        case 3: return "HIGH"
        case 2: return "MED"
        case 1: return "LOW"
        default: return "—"
        }
    }

    var body: some View {
        Text(label)
            .font(.system(size: 9, weight: .bold))
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .background(color.opacity(0.2))
            .foregroundStyle(color)
            .clipShape(.capsule)
    }
}
