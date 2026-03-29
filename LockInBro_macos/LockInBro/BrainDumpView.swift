// BrainDumpView.swift — Brain-dump text → Claude parses + saves tasks → generate step plans

import SwiftUI

struct BrainDumpView: View {
    /// Called when user wants to navigate to the task board
    var onGoToTasks: (() -> Void)?

    @State private var rawText = ""
    @State private var recorder = VoiceDumpRecorder()
    @State private var parsedTasks: [ParsedTask] = []
    @State private var unparseableFragments: [String] = []
    @State private var isParsing = false
    @State private var errorMessage: String?
    @State private var isDone = false

    // After dump, fetch actual tasks (with IDs) for step generation
    @State private var savedTasks: [AppTask] = []
    @State private var isFetchingTasks = false
    @State private var planningTaskId: String?
    @State private var planError: String?
    @State private var generatedSteps: [String: [Step]] = [:]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if isDone {
                    donePhase
                } else {
                    inputPhase
                }
            }
            .padding()
        }
        .onAppear { recorder.warmUp() }
    }

    // MARK: - Input Phase

    private var inputPhase: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Brain Dump")
                    .font(.title2.bold())
                Text("Just type everything on your mind. Claude will organize it into tasks for you.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            TextEditor(text: $rawText)
                .font(.body)
                .frame(minHeight: 200)
                .padding(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
                .overlay(alignment: .topLeading) {
                    if rawText.isEmpty {
                        Text("e.g. I need to email Sarah about the project, dentist Thursday, presentation due Friday, buy groceries…")
                            .foregroundStyle(.secondary.opacity(0.5))
                            .font(.body)
                            .padding(12)
                            .allowsHitTesting(false)
                    }
                }

            // Voice dump bar
            voiceDumpBar

            if let err = errorMessage {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button {
                Task { await parseDump() }
            } label: {
                Group {
                    if isParsing {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Claude is parsing your tasks…")
                        }
                    } else {
                        Label("Parse & Save Tasks", systemImage: "wand.and.stars")
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 36)
            }
            .buttonStyle(.borderedProminent)
            .disabled(rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isParsing)
        }
    }

    // MARK: - Done Phase

    private var donePhase: some View {
        VStack(spacing: 20) {
            // Success header
            VStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(.green)
                Text("\(parsedTasks.count) task\(parsedTasks.count == 1 ? "" : "s") saved!")
                    .font(.title2.bold())
                Text("Tasks are in your board. Generate steps to break them into 5–15 min chunks.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)

            // Parsed task previews — 2-column grid
            if !parsedTasks.isEmpty {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(parsedTasks) { task in
                        ParsedTaskPreviewRow(task: task)
                    }
                }
            }

            // Unparseable fragments
            if !unparseableFragments.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Couldn't parse:")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    ForEach(unparseableFragments, id: \.self) { fragment in
                        Text("• \(fragment)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .italic()
                    }
                }
                .padding()
                .background(Color.secondary.opacity(0.08))
                .clipShape(.rect(cornerRadius: 8))
            }

            Divider()

            // Step generation section
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Generate Steps")
                        .font(.headline)
                    if isFetchingTasks {
                        ProgressView().scaleEffect(0.8)
                    }
                    Spacer()
                }

                if let err = planError {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                if savedTasks.isEmpty || isFetchingTasks {
                    HStack(spacing: 8) {
                        ProgressView().scaleEffect(0.8)
                        Text("Generating steps…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(savedTasks.prefix(parsedTasks.count)) { task in
                        VStack(alignment: .leading, spacing: 6) {
                            // Task header
                            HStack {
                                Text(task.title)
                                    .font(.subheadline.bold())
                                    .lineLimit(1)
                                Spacer()
                                if task.planType == nil {
                                    HStack(spacing: 4) {
                                        ProgressView().scaleEffect(0.7)
                                        Text("Generating…")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }

                            // Steps list
                            if let steps = generatedSteps[task.id], !steps.isEmpty {
                                VStack(alignment: .leading, spacing: 3) {
                                    ForEach(Array(steps.enumerated()), id: \.element.id) { i, step in
                                        HStack(alignment: .top, spacing: 6) {
                                            Text("\(i + 1).")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                                .frame(width: 16, alignment: .trailing)
                                            Text(step.title)
                                                .font(.caption)
                                                .foregroundStyle(.primary)
                                            if let mins = step.estimatedMinutes {
                                                Spacer()
                                                Text("~\(mins)m")
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                }
                                .padding(.leading, 4)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color.secondary.opacity(0.06))
                        .clipShape(.rect(cornerRadius: 8))
                    }
                }
            }

            Divider()

            // Bottom actions
            HStack(spacing: 12) {
                Button {
                    onGoToTasks?()
                } label: {
                    Label("Go to Task Board", systemImage: "checklist")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button("Dump more") {
                    reset()
                }
                .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - Voice Dump Bar

    private var voiceDumpBar: some View {
        HStack(spacing: 10) {
            Button {
                if recorder.isRecording {
                    Task { await recorder.stopRecording() }
                } else {
                    Task { await startVoiceRecording() }
                }
            } label: {
                Label(
                    recorder.isRecording ? "Stop" : (recorder.isTranscribing ? "Transcribing…" : "Voice Dump"),
                    systemImage: recorder.isRecording ? "stop.circle.fill" : "mic.fill"
                )
                .foregroundStyle(recorder.isRecording ? .red : .accentColor)
                .symbolEffect(.pulse, isActive: recorder.isRecording || recorder.isTranscribing)
            }
            .buttonStyle(.bordered)
            .disabled(recorder.isTranscribing)

            if recorder.isRecording {
                Text("Listening…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if recorder.isTranscribing {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.7)
                    Text("Whisper is transcribing…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if recorder.permissionDenied {
                Text("Microphone access denied in System Settings.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .onChange(of: recorder.isTranscribing) { _, isNowTranscribing in
            // Append transcript into rawText once Whisper finishes
            if !isNowTranscribing && !recorder.liveTranscript.isEmpty {
                if !rawText.isEmpty { rawText += "\n" }
                rawText += recorder.liveTranscript
                recorder.liveTranscript = ""
            }
        }
    }

    private func startVoiceRecording() async {
        await recorder.requestPermissions()
        guard !recorder.permissionDenied else { return }
        recorder.startRecording()
    }

    // MARK: - Actions

    private func parseDump() async {
        isParsing = true
        errorMessage = nil
        do {
            // Backend parses AND saves tasks in one call — we just display the result
            let response = try await APIClient.shared.brainDump(rawText: rawText)
            parsedTasks = response.parsedTasks
            unparseableFragments = response.unparseableFragments
            isDone = true
            // Fetch actual tasks (with IDs) so user can generate steps
            await fetchLatestTasks()
        } catch {
            errorMessage = error.localizedDescription
        }
        isParsing = false
    }

    /// Fetch the most recently created tasks, then auto-generate steps for all of them
    private func fetchLatestTasks() async {
        isFetchingTasks = true
        do {
            let all = try await APIClient.shared.getTasks()
            let parsedTitles = Set(parsedTasks.map(\.title))
            savedTasks = all.filter { parsedTitles.contains($0.title) }
            if savedTasks.isEmpty {
                savedTasks = Array(all.prefix(parsedTasks.count))
            }
        } catch {}
        isFetchingTasks = false

        // Auto-generate steps for any task that doesn't have a plan yet
        let tasksNeedingPlan = savedTasks.filter { $0.planType == nil }
        await withTaskGroup(of: Void.self) { group in
            for task in tasksNeedingPlan {
                group.addTask { await generatePlan(task) }
            }
        }
    }

    private func generatePlan(_ task: AppTask) async {
        planningTaskId = task.id
        planError = nil
        do {
            let response = try await APIClient.shared.planTask(taskId: task.id)
            generatedSteps[task.id] = response.steps.sorted { $0.sortOrder < $1.sortOrder }
            // Mark the task as planned locally
            if let idx = savedTasks.firstIndex(where: { $0.id == task.id }) {
                savedTasks[idx].planType = response.planType
            }
        } catch {
            planError = error.localizedDescription
        }
        planningTaskId = nil
    }

    private func reset() {
        rawText = ""
        parsedTasks = []
        unparseableFragments = []
        savedTasks = []
        generatedSteps = [:]
        errorMessage = nil
        planningTaskId = nil
        planError = nil
        isDone = false
    }
}

// MARK: - Parsed Task Preview Row

private struct ParsedTaskPreviewRow: View {
    let task: ParsedTask

    private var priorityColor: Color {
        switch task.priority {
        case 4: return .red
        case 3: return .orange
        case 2: return .yellow
        default: return .green
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(priorityColor)
                .frame(width: 7, height: 7)
                .padding(.top, 7)

            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .font(.subheadline.bold())

                HStack(spacing: 8) {
                    if let mins = task.estimatedMinutes {
                        Label("~\(mins)m", systemImage: "clock")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if let dl = task.deadline {
                        Label(shortDate(dl), systemImage: "calendar")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(task.tags, id: \.self) { tag in
                        Text(tag)
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.1))
                            .clipShape(.capsule)
                    }
                }
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.06))
        .clipShape(.rect(cornerRadius: 10))
    }

    private func shortDate(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: iso) {
            return d.formatted(.dateTime.month(.abbreviated).day())
        }
        f.formatOptions = [.withInternetDateTime]
        if let d = f.date(from: iso) {
            return d.formatted(.dateTime.month(.abbreviated).day())
        }
        return iso
    }
}
