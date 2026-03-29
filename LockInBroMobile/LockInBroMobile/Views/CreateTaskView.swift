// CreateTaskView.swift — LockInBro
// Manual task creation form

import SwiftUI

struct CreateTaskView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var description = ""
    @State private var priority = 0
    @State private var hasDeadline = false
    @State private var deadline = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
    @State private var estimatedMinutesText = ""
    @State private var isCreating = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Task") {
                    TextField("Title", text: $title)
                    TextField("Description (optional)", text: $description, axis: .vertical)
                        .lineLimit(2...5)
                }

                Section("Priority") {
                    Picker("Priority", selection: $priority) {
                        Text("—").tag(0)
                        Text("Low").tag(1)
                        Text("Medium").tag(2)
                        Text("High").tag(3)
                        Text("Urgent").tag(4)
                    }
                    .pickerStyle(.segmented)
                }

                Section("Time") {
                    Toggle("Has deadline", isOn: $hasDeadline)
                    if hasDeadline {
                        DatePicker("Deadline", selection: $deadline, displayedComponents: [.date, .hourAndMinute])
                    }
                    HStack {
                        Text("Estimated time")
                        Spacer()
                        TextField("min", text: $estimatedMinutesText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                        Text("min")
                            .foregroundStyle(.secondary)
                    }
                }

                if let error {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("New Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Create") { createTask() }
                        .fontWeight(.semibold)
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isCreating)
                }
            }
        }
    }

    private func createTask() {
        isCreating = true
        error = nil
        Task {
            do {
                _ = try await APIClient.shared.createTask(
                    title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                    description: description.isEmpty ? nil : description,
                    priority: priority,
                    deadline: hasDeadline ? ISO8601DateFormatter().string(from: deadline) : nil,
                    estimatedMinutes: Int(estimatedMinutesText)
                )
                await appState.loadTasks()
                await MainActor.run { dismiss() }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    isCreating = false
                }
            }
        }
    }
}

#Preview {
    CreateTaskView()
        .environment(AppState())
}
