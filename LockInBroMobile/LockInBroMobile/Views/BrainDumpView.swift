// BrainDumpView.swift — LockInBro
// Voice/text brain dump → Local WhisperKit Transcription → Claude Task Extraction

import SwiftUI
import AVFoundation
import NaturalLanguage

struct BrainDumpView: View {
    @Environment(AppState.self) private var appState
    @StateObject private var speech = SpeechService.shared

    @State private var dumpText = ""
    @State private var isParsing = false
    @State private var parsedResult: BrainDumpResponse?
    @State private var selectedIndices: Set<Int> = []
    @State private var acceptedSuggestions: Set<UUID> = []
    @State private var isSaving = false
    @State private var error: String?
    @State private var showConfirmation = false
    @State private var floatingKeywords: [FloatingKeyword] = []

    // Derived state for the loading screen
    private var isProcessing: Bool {
        speech.isTranscribing || isParsing
    }

    var body: some View {
        NavigationStack {
            Group {
                if parsedResult != nil {
                    resultsView
                } else if isProcessing {
                    processingView
                } else if speech.isRecording {
                    recordingView
                } else {
                    idleInputView
                }
            }
            .navigationTitle(speech.isRecording ? "" : "Brain Dump")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if parsedResult != nil || !dumpText.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Clear") { resetState() }
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .alert("Tasks Saved!", isPresented: $showConfirmation) {
                Button("OK") { resetState() }
            } message: {
                Text("Your tasks have been added to your task board.")
            }
            // Smoothly animate between the different UI states
            .animation(.default, value: speech.isRecording)
            .animation(.default, value: isProcessing)
            .animation(.default, value: parsedResult != nil)
        }
    }

    // MARK: - 1. Idle / Text Input View

    private var idleInputView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Label("What's on your mind?", systemImage: "lightbulb.fill")
                        .font(.headline)
                    Text("Hit the mic and just start talking. We'll extract your tasks, deadlines, and priorities automatically.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Big Audio Button Prominence
                VStack(spacing: 8) {
                    Button(action: startRecording) {
                        HStack(spacing: 12) {
                            if speech.modelLoadingState != "Ready" {
                                ProgressView().tint(.white)
                            } else {
                                Image(systemName: "mic.fill")
                                    .font(.title2)
                            }
                            Text(speech.modelLoadingState == "Ready" ? "Start Brain Dump" : "Loading AI Model...")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(speech.modelLoadingState == "Ready" ? Color.blue : Color.gray)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(color: speech.modelLoadingState == "Ready" ? .blue.opacity(0.3) : .clear, radius: 8, x: 0, y: 4)
                    }
                    .disabled(speech.modelLoadingState != "Ready")
                    
                    if speech.modelLoadingState != "Ready" {
                        Text(speech.modelLoadingState)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 8)

                Divider()

                // Fallback Text Area
                Text("Or type it out:")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)

                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color(.secondarySystemBackground))
                        .frame(minHeight: 150)

                    if dumpText.isEmpty {
                        Text("e.g. I need to email Sarah about the project, dentist appointment Thursday...")
                            .foregroundStyle(.secondary.opacity(0.6))
                            .font(.subheadline)
                            .padding(14)
                    }

                    TextEditor(text: $dumpText)
                        .scrollContentBackground(.hidden)
                        .padding(10)
                        .font(.subheadline)
                        .toolbar {
                            ToolbarItemGroup(placement: .keyboard) {
                                Spacer()
                                Button("Done") {
                                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                                }
                            }
                        }
                }
                .frame(minHeight: 150)

                if let error {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                }

                if !dumpText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button(action: {
                        Task { await parseDump(text: dumpText, source: "manual") }
                    }) {
                        Text("Parse Typed Text")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.gray.opacity(0.2))
                            .foregroundStyle(.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }
            }
            .padding()
        }
    }

    // MARK: - 2. Active Recording View

    private var recordingView: some View {
        VStack(spacing: 40) {
            Spacer()

            // The Audio Visualizer & Bubble Canvas
            ZStack {
                // Background Pulses
                Circle()
                    .fill(Color.blue.opacity(0.15))
                    .frame(width: 240, height: 240)
                    .scaleEffect(speech.isRecording ? 1.15 : 1.0)
                    .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: speech.isRecording)

                Circle()
                    .fill(Color.blue.opacity(0.25))
                    .frame(width: 180, height: 180)
                    .scaleEffect(speech.isRecording ? 1.05 : 1.0)
                    .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: speech.isRecording)

                Image(systemName: "waveform")
                    .font(.system(size: 80, weight: .light))
                    .foregroundStyle(.blue)
                    .symbolEffect(.variableColor.iterative, isActive: speech.isRecording)
                
                // Floating Keywords Layer
                ForEach(floatingKeywords) { keyword in
                    GlassBubbleView(keyword: keyword)
                }
            }
            .frame(height: 300) // Give the bubbles room to float

            VStack(spacing: 12) {
                Text("Listening...")
                    .font(.title.bold())
                Text("Speak freely. Pauses are fine.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: stopAndProcess) {
                HStack(spacing: 12) {
                    Image(systemName: "stop.fill")
                    Text("Done Talking")
                }
                .font(.title3.bold())
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .padding(.vertical, 8)
                .background(Color.red)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .shadow(color: .red.opacity(0.3), radius: 10, y: 5)
            }
            .padding(.horizontal, 30)
            .padding(.bottom, 40)
        }
        .onChange(of: speech.latestKeyword) { _, newWord in
            if let newWord = newWord {
                spawnKeywordBubble(word: newWord)
            }
        }
    }

    // MARK: - 3. Processing View

    private var processingView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            ProgressView()
                .scaleEffect(1.5)
                .tint(.blue)
            
            VStack(spacing: 8) {
                Text(speech.isTranscribing ? "Transcribing audio locally..." : "Extracting tasks...")
                    .font(.headline)
                
                Text(speech.isTranscribing ? "Running Whisper on Neural Engine" : "Claude is analyzing your dump")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            if let error {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .padding()
            }
            
            Spacer()
        }
    }

    // MARK: - 4. Results View

    private var resultsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Found \(parsedResult?.parsedTasks.count ?? 0) tasks")
                            .font(.headline)
                        Text("Select the ones you want to save")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(selectedIndices.count == (parsedResult?.parsedTasks.count ?? 0) ? "Deselect All" : "Select All") {
                        toggleSelectAll()
                    }
                    .font(.subheadline)
                }

                ForEach(Array((parsedResult?.parsedTasks ?? []).enumerated()), id: \.offset) { idx, task in
                    ParsedTaskCard(
                        task: task,
                        isSelected: selectedIndices.contains(idx),
                        acceptedSuggestions: $acceptedSuggestions
                    ) {
                        if selectedIndices.contains(idx) { selectedIndices.remove(idx) }
                        else { selectedIndices.insert(idx) }
                    }
                }

                if let frags = parsedResult?.unparseableFragments, !frags.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Couldn't parse these:", systemImage: "questionmark.circle")
                            .font(.caption.bold())
                            .foregroundStyle(.orange)
                        ForEach(frags, id: \.self) { frag in
                            Text("• \(frag)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding()
                    .background(Color.orange.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                if let error {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                }

                Button(action: saveTasks) {
                    HStack(spacing: 8) {
                        if isSaving { ProgressView().tint(.white) }
                        Text(isSaving ? "Saving…" : "Save \(selectedIndices.count) Task\(selectedIndices.count == 1 ? "" : "s")")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(selectedIndices.isEmpty ? Color.gray : Color.green)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(selectedIndices.isEmpty || isSaving)
            }
            .padding()
        }
    }

    // MARK: - Core Actions

    private func startRecording() {
        error = nil
        Task {
            if speech.authStatus != .granted {
                await speech.requestAuthorization()
            }
            
            if speech.authStatus == .granted {
                do {
                    try speech.startRecording()
                } catch {
                    self.error = "Mic error: \(error.localizedDescription)"
                }
            } else {
                self.error = "Microphone access denied. Please enable in Settings."
            }
        }
    }

    private func stopAndProcess() {
        Task {
            do {
                error = nil
                let transcript = try await speech.stopRecordingAndTranscribe()
                
                guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    self.error = "Couldn't hear anything. Tap clear and try again."
                    return
                }
                
                dumpText = transcript
                await parseDump(text: transcript, source: "voice")
                
            } catch {
                self.error = "Transcription failed: \(error.localizedDescription)"
            }
        }
    }

    private func parseDump(text: String, source: String) async {
        isParsing = true
        do {
            let result = try await APIClient.shared.brainDump(text: text, source: source)
            await MainActor.run {
                self.parsedResult = result
                self.selectedIndices = Set(0..<result.parsedTasks.count)
                self.isParsing = false
            }
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
                self.isParsing = false
            }
        }
    }

    private func saveTasks() {
        guard let result = parsedResult else { return }
        isSaving = true
        error = nil

        Task {
            let allTasks = result.parsedTasks

            // Delete tasks the user deselected (they were already saved by the backend)
            for (idx, task) in allTasks.enumerated() {
                guard let taskId = task.taskId else { continue }
                if !selectedIndices.contains(idx) {
                    try? await APIClient.shared.deleteTask(taskId: taskId)
                }
            }

            // Add accepted suggested steps to kept tasks
            for idx in selectedIndices.sorted() {
                let task = allTasks[idx]
                guard let taskId = task.taskId else { continue }
                for sub in task.subtasks where sub.suggested && acceptedSuggestions.contains(sub.id) {
                    do {
                        _ = try await APIClient.shared.addStep(
                            taskId: taskId,
                            title: sub.title,
                            description: sub.description,
                            estimatedMinutes: sub.estimatedMinutes
                        )
                    } catch {
                        await MainActor.run { self.error = error.localizedDescription }
                    }
                }
            }

            await appState.loadTasks()
            await MainActor.run {
                isSaving = false
                showConfirmation = true
            }
        }
    }

    private func toggleSelectAll() {
        let total = parsedResult?.parsedTasks.count ?? 0
        if selectedIndices.count == total {
            selectedIndices = []
        } else {
            selectedIndices = Set(0..<total)
        }
    }

    private func resetState() {
        parsedResult = nil
        dumpText = ""
        selectedIndices = []
        acceptedSuggestions = []
        error = nil
        floatingKeywords.removeAll()
        speech.reset()
    }

    // MARK: - Keyword Bubble Animation Logic
    
    // Moved safely INSIDE the BrainDumpView struct
    private func spawnKeywordBubble(word: String) {
        let startX = CGFloat.random(in: -100...100)
        let startY = CGFloat.random(in: 20...80)
        
        let newKeyword = FloatingKeyword(
            text: word,
            xOffset: startX,
            yOffset: startY
        )
        
        floatingKeywords.append(newKeyword)
        let index = floatingKeywords.count - 1
        
        // 1. Pop In
        withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
            floatingKeywords[index].opacity = 1.0
            floatingKeywords[index].scale = 1.0
        }
        
        // 2. Float Upwards slowly
        withAnimation(.easeOut(duration: 3.0)) {
            floatingKeywords[index].yOffset -= 150
        }
        
        // 3. Fade Out and Remove
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            guard let matchIndex = floatingKeywords.firstIndex(where: { $0.id == newKeyword.id }) else { return }
            
            withAnimation(.easeOut(duration: 1.0)) {
                floatingKeywords[matchIndex].opacity = 0.0
                floatingKeywords[matchIndex].scale = 0.8
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                floatingKeywords.removeAll(where: { $0.id == newKeyword.id })
            }
        }
    }
} // <--- End of BrainDumpView Struct

// MARK: - Parsed Task Card

struct ParsedTaskCard: View {
    let task: ParsedTask
    let isSelected: Bool
    @Binding var acceptedSuggestions: Set<UUID>
    let onTap: () -> Void

    private var coreSteps: [ParsedSubtask] { task.subtasks.filter { !$0.suggested } }
    private var suggestedSteps: [ParsedSubtask] { task.subtasks.filter { $0.suggested } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? .green : .secondary)

                VStack(alignment: .leading, spacing: 7) {
                    Text(task.title)
                        .font(.subheadline.bold())
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 10) {
                        if task.priority > 0 {
                            Text("Priority \(task.priority)")
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.2))
                                .clipShape(Capsule())
                        }

                        if let dl = task.deadline, let date = ISO8601DateFormatter().date(from: dl) {
                            Label(date.formatted(.dateTime.month().day()), systemImage: "calendar")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if let mins = task.estimatedMinutes {
                            Label("\(mins)m", systemImage: "clock")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if !task.tags.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(task.tags, id: \.self) { tag in
                                Text(tag)
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.blue.opacity(0.1))
                                    .clipShape(Capsule())
                            }
                        }
                    }

                    if let desc = task.description {
                        Text(desc)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    // Core steps (from the brain dump text)
                    if !coreSteps.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(coreSteps) { sub in
                                HStack(spacing: 6) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.green.opacity(0.6))
                                    Text(sub.title)
                                        .font(.caption)
                                    if let mins = sub.estimatedMinutes {
                                        Text("(\(mins)m)")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .padding(.top, 2)
                    }
                }

                Spacer()
            }
            .padding()
            .background(isSelected ? Color.green.opacity(0.06) : Color(.secondarySystemBackground))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? Color.green.opacity(0.5) : Color.clear, lineWidth: 1.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)

            // Suggested steps (toggleable, outside the main button)
            if isSelected && !suggestedSteps.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Suggested steps")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                        .padding(.leading, 4)

                    ForEach(suggestedSteps) { sub in
                        Button {
                            if acceptedSuggestions.contains(sub.id) {
                                acceptedSuggestions.remove(sub.id)
                            } else {
                                acceptedSuggestions.insert(sub.id)
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: acceptedSuggestions.contains(sub.id) ? "plus.circle.fill" : "plus.circle")
                                    .foregroundStyle(acceptedSuggestions.contains(sub.id) ? .blue : .secondary)
                                Text(sub.title)
                                    .font(.caption)
                                    .foregroundStyle(.primary)
                                if let mins = sub.estimatedMinutes {
                                    Text("(\(mins)m)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(acceptedSuggestions.contains(sub.id) ? Color.blue.opacity(0.08) : Color(.tertiarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.top, -4)
            }
        } // end outer VStack
    }
}


// MARK: - Floating Keyword Data Model

struct FloatingKeyword: Identifiable, Equatable {
    let id = UUID()
    let text: String
    var xOffset: CGFloat
    var yOffset: CGFloat
    var opacity: Double = 0.0
    var scale: CGFloat = 0.5
}

// MARK: - The Liquid Glass Bubble

struct GlassBubbleView: View {
    let keyword: FloatingKeyword
    
    var body: some View {
        Text(keyword.text)
            .font(.system(.callout, design: .rounded).weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
            .background(
                LinearGradient(
                    colors: [.orange.opacity(0.3), .pink.opacity(0.2), .yellow.opacity(0.2)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.4), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 5)
            .scaleEffect(keyword.scale)
            .opacity(keyword.opacity)
            .offset(x: keyword.xOffset, y: keyword.yOffset)
    }
}
