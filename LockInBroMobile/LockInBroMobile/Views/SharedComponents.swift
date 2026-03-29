// SharedComponents.swift — LockInBro
// Reusable view components used across multiple screens

import SwiftUI

// MARK: - Priority Badge

struct PriorityBadge: View {
    let priority: Int

    private var label: String {
        switch priority {
        case 1: return "Low"
        case 2: return "Med"
        case 3: return "High"
        case 4: return "Urgent"
        default: return "—"
        }
    }

    private var color: Color {
        switch priority {
        case 1: return .gray
        case 2: return .blue
        case 3: return .orange
        case 4: return .red
        default: return .secondary
        }
    }

    var body: some View {
        Text(label)
            .font(.caption.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

// MARK: - Status Badge

struct StatusBadge: View {
    let status: String

    private var color: Color {
        switch status {
        case "done": return .green
        case "in_progress": return .blue
        case "ready": return .purple
        case "planning": return .teal
        case "deferred": return .gray
        default: return .secondary
        }
    }

    var body: some View {
        Text(status.replacingOccurrences(of: "_", with: " ").capitalized)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

// MARK: - Filter Chip

struct FilterChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(isSelected ? Color.blue : Color.gray.opacity(0.15))
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Info Card

struct InfoCard: View {
    let icon: String
    let title: String
    let content: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.subheadline.bold())
                .foregroundStyle(color)
            Text(content)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Stat Card

struct StatCard: View {
    let value: String
    let label: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.title3)
            Text(value)
                .font(.title.bold())
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Tag Pill

struct TagPill: View {
    let tag: String

    var body: some View {
        Text(tag)
            .font(.caption2)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color.blue.opacity(0.12))
            .foregroundStyle(.blue)
            .clipShape(Capsule())
    }
}

// MARK: - Deadline Label

struct DeadlineLabel: View {
    let task: TaskOut

    var body: some View {
        if let date = task.deadlineDate {
            HStack(spacing: 4) {
                Image(systemName: "calendar")
                Text(date, style: .date)
            }
            .font(.caption)
            .foregroundStyle(task.isOverdue ? .red : .secondary)
        }
    }
}
