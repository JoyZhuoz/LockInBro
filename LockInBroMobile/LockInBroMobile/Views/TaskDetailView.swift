// TaskDetailView.swift — LockInBro
// Full task view: metadata, steps, focus session controls, resume card

import SwiftUI
import ActivityKit

struct TaskDetailView: View {
    let taskId: String
    @Environment(AppState.self) private var appState

    @State private var task: TaskOut?
    @State private var steps: [StepOut] = []
    @State private var isLoadingSteps = true
    @State private var isGeneratingPlan = false
    @State private var resumeResponse: ResumeResponse?
    @State private var showResumeCard = false
    @State private var isStartingSession = false
    @State private var isEndingSession = false
    @State private var error: String?

    private var completedCount: Int { steps.filter { $0.isDone }.count }
    private var progress: Double { steps.isEmpty ? 0 : Double(completedCount) / Double(steps.count) }

    var body: some View {
        Group {
            if let task {
                mainContent(task)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(task?.title ?? "Task")
        .task { await load() }
        .sheet(isPresented: $showResumeCard) {
            if let resume = resumeResponse {
                ResumeCardView(resume: resume) { showResumeCard = false }
            }
        }
    }

    // MARK: - Main Content

    private func mainContent(_ task: TaskOut) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                taskHeader(task)
                focusSection(task)
                stepsSection(task)

                if let error {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                        .padding(.horizontal)
                }
            }
            .padding()
        }
    }

    // MARK: - Task Header Card

    private func taskHeader(_ task: TaskOut) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                PriorityBadge(priority: task.priority)
                StatusBadge(status: task.status)
                Spacer()
                if let mins = task.estimatedMinutes {
                    Label("\(mins)m", systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let desc = task.description {
                Text(desc)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            DeadlineLabel(task: task)

            if !task.tags.isEmpty {
                HStack(spacing: 4) {
                    ForEach(task.tags, id: \.self) { TagPill(tag: $0) }
                }
            }

            if !steps.isEmpty {
                VStack(spacing: 5) {
                    ProgressView(value: progress)
                        .tint(progress >= 1 ? .green : .blue)
                    Text("\(completedCount) of \(steps.count) steps completed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Focus Session Section

    private func focusSection(_ task: TaskOut) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Focus Session")
                    .font(.headline)
                Spacer()
                Button("Test Local") {
                    let attributes = FocusSessionAttributes(sessionType: "Test")
                    let state = FocusSessionAttributes.ContentState(taskTitle: "Local Test", startedAt: Int(Date().timeIntervalSince1970), stepsCompleted: 0, stepsTotal: 0)
                    do {
                        _ = try Activity.request(attributes: attributes, content: .init(state: state, staleDate: nil), pushType: .token)
                        print("Success: Started local Activity")
                    } catch {
                        print("Failed to start local Activity: \(error)")
                    }
                }
                .font(.caption)
                .buttonStyle(.bordered)
            }

            if let session = appState.activeSession {
                // Active session card
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        if session.taskId == taskId {
                            Label("Session Active", systemImage: "play.circle.fill")
                                .font(.subheadline.bold())
                                .foregroundStyle(.green)
                            Text("Focusing on this task")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Label("Session Active Elsewhere", systemImage: "exclamationmark.triangle.fill")
                                .font(.subheadline.bold())
                                .foregroundStyle(.orange)
                            Text("You are focusing on another task")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button(action: endSession) {
                        if isEndingSession {
                            ProgressView()
                        } else {
                            Text("End Session")
                                .font(.subheadline)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Color.red.opacity(0.12))
                                .foregroundStyle(.red)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    .disabled(isEndingSession)
                }
                .padding()
                .background(session.taskId == taskId ? Color.green.opacity(0.07) : Color.orange.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            } else {
                // Start session button
                Button(action: startSession) {
                    HStack(spacing: 8) {
                        if isStartingSession { ProgressView().tint(.white) }
                        Image(systemName: "play.circle.fill")
                        Text("Start Focus Session")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(isStartingSession)
            }
        }
    }

    // MARK: - Steps Section

    private func stepsSection(_ task: TaskOut) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Steps")
                    .font(.headline)
                Spacer()
                if steps.isEmpty && task.status != "done" {
                    Button(action: generatePlan) {
                        if isGeneratingPlan {
                            ProgressView()
                        } else {
                            Label("AI Plan", systemImage: "wand.and.stars")
                                .font(.subheadline)
                        }
                    }
                    .disabled(isGeneratingPlan)
                }
            }

            if isLoadingSteps {
                ProgressView().frame(maxWidth: .infinity)
            } else if steps.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "list.number")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No steps yet")
                        .font(.subheadline.bold())
                    Text("Tap \"AI Plan\" to let Claude break this task into 5–15 minute steps.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            } else {
                ForEach(Array(steps.enumerated()), id: \.element.id) { idx, step in
                    StepRowView(step: step) { updated in
                        steps[idx] = updated
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func load() async {
        // Find task in state
        task = appState.tasks.first(where: { $0.id == taskId })
        // Load steps
        isLoadingSteps = true
        do {
            steps = try await APIClient.shared.getSteps(taskId: taskId)
        } catch {
            self.error = error.localizedDescription
        }
        isLoadingSteps = false
        // Refresh task from app state in case it was updated
        if task == nil {
            task = appState.tasks.first(where: { $0.id == taskId })
        }
    }

    private func generatePlan() {
        isGeneratingPlan = true
        error = nil
        Task {
            do {
                let plan = try await APIClient.shared.planTask(taskId: taskId)
                await MainActor.run {
                    steps = plan.steps
                    isGeneratingPlan = false
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    isGeneratingPlan = false
                }
            }
        }
    }

    private func startSession() {
        isStartingSession = true
        error = nil
        let platform = UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone"
        Task {
            do {
                let session = try await APIClient.shared.startSession(taskId: taskId, platform: platform)
                await MainActor.run {
                    appState.activeSession = session
                    isStartingSession = false
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    isStartingSession = false
                }
            }
        }
    }

    private func endSession() {
        guard let session = appState.activeSession else { return }
        isEndingSession = true
        Task {
            do {
                _ = try await APIClient.shared.endSession(sessionId: session.id)
                // End Live Activity locally (belt-and-suspenders alongside the server push)
                ActivityManager.shared.endAllActivities()
                // Fetch resume card
                let resume = try? await APIClient.shared.resumeSession(sessionId: session.id)
                await MainActor.run {
                    appState.activeSession = nil
                    isEndingSession = false
                    if let resume {
                        resumeResponse = resume
                        showResumeCard = true
                    }
                }
                // Reload tasks to pick up updated step statuses
                await appState.loadTasks()
                steps = (try? await APIClient.shared.getSteps(taskId: taskId)) ?? steps
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    isEndingSession = false
                }
            }
        }
    }
}

// MARK: - Step Row

struct StepRowView: View {
    let step: StepOut
    let onUpdate: (StepOut) -> Void
    @State private var isUpdating = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Complete toggle
            Button(action: toggleComplete) {
                ZStack {
                    if isUpdating {
                        ProgressView().frame(width: 28, height: 28)
                    } else {
                        Image(systemName: iconName)
                            .font(.title2)
                            .foregroundStyle(iconColor)
                    }
                }
                .frame(width: 28, height: 28)
            }
            .disabled(isUpdating)

            VStack(alignment: .leading, spacing: 5) {
                Text(step.title)
                    .font(.subheadline)
                    .strikethrough(step.isDone, color: .secondary)
                    .foregroundStyle(step.isDone ? .secondary : .primary)
                    .fixedSize(horizontal: false, vertical: true)

                // Checkpoint note from VLM
                if let note = step.checkpointNote {
                    HStack(alignment: .top, spacing: 5) {
                        Image(systemName: "bookmark.fill")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(7)
                    .background(Color.blue.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                HStack(spacing: 8) {
                    if let mins = step.estimatedMinutes {
                        Text("~\(mins)m")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    StatusBadge(status: step.status)
                }
            }
            Spacer()
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var iconName: String {
        if step.isDone { return "checkmark.circle.fill" }
        if step.isInProgress { return "play.circle.fill" }
        return "circle"
    }

    private var iconColor: Color {
        if step.isDone { return .green }
        if step.isInProgress { return .blue }
        return .secondary
    }

    private func toggleComplete() {
        isUpdating = true
        Task {
            do {
                let updated: StepOut
                if step.isDone {
                    updated = try await APIClient.shared.updateStep(stepId: step.id, fields: ["status": "pending"])
                } else {
                    updated = try await APIClient.shared.completeStep(stepId: step.id)
                }
                await MainActor.run {
                    onUpdate(updated)
                    isUpdating = false
                }
            } catch {
                await MainActor.run { isUpdating = false }
            }
        }
    }
}

// MARK: - Resume Card Modal

struct ResumeCardView: View {
    let resume: ResumeResponse
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Welcome
                    VStack(alignment: .leading, spacing: 4) {
                        Text(resume.resumeCard.welcomeBack)
                            .font(.title2.bold())
                        Text(resume.task.title)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Divider()

                    InfoCard(
                        icon: "arrow.uturn.backward.circle",
                        title: "Where you left off",
                        content: resume.resumeCard.youWereDoing,
                        color: .blue
                    )

                    InfoCard(
                        icon: "arrow.right.circle.fill",
                        title: "Next up",
                        content: resume.resumeCard.nextStep,
                        color: .green
                    )

                    // Progress
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("Progress", systemImage: "chart.bar.fill")
                                .font(.subheadline.bold())
                            Spacer()
                            Text("\(resume.progress.completed) / \(resume.progress.total) steps")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        ProgressView(
                            value: Double(resume.progress.completed),
                            total: Double(max(resume.progress.total, 1))
                        )
                        .tint(.blue)

                        if resume.progress.distractionCount > 0 {
                            Text("↩ \(resume.progress.distractionCount) distraction\(resume.progress.distractionCount == 1 ? "" : "s") this session")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                    // Motivation
                    Text(resume.resumeCard.motivation)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)

                    Button("Let's Go!", action: onDismiss)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .fontWeight(.semibold)
                }
                .padding()
            }
            .navigationTitle("Welcome Back")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done", action: onDismiss)
                }
            }
        }
    }
}
