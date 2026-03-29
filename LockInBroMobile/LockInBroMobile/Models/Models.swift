// Models.swift — LockInBro iOS/iPadOS
// Codable structs matching the backend API schemas

import Foundation

// MARK: - Auth

struct AuthResponse: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
    let user: UserOut

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case user
    }
}

struct UserOut: Codable, Identifiable {
    let id: String
    var email: String?
    var displayName: String?
    var timezone: String?
    var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, email, timezone
        case displayName = "display_name"
        case createdAt = "created_at"
    }
}

// MARK: - Task

struct TaskOut: Codable, Identifiable, Equatable {
    let id: String
    var userId: String
    var title: String
    var description: String?
    var priority: Int
    var status: String
    var deadline: String?
    var estimatedMinutes: Int?
    var source: String
    var tags: [String]
    var planType: String?
    var brainDumpRaw: String?
    var createdAt: String
    var updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, title, description, priority, status, deadline, source, tags
        case userId = "user_id"
        case estimatedMinutes = "estimated_minutes"
        case planType = "plan_type"
        case brainDumpRaw = "brain_dump_raw"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    // Custom decoder: provide safe defaults for fields the backend may omit or null
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id              = try c.decode(String.self, forKey: .id)
        userId          = try c.decodeIfPresent(String.self, forKey: .userId) ?? ""
        title           = try c.decode(String.self, forKey: .title)
        description     = try c.decodeIfPresent(String.self, forKey: .description)
        priority        = try c.decodeIfPresent(Int.self, forKey: .priority) ?? 0
        status          = try c.decodeIfPresent(String.self, forKey: .status) ?? "pending"
        deadline        = try c.decodeIfPresent(String.self, forKey: .deadline)
        estimatedMinutes = try c.decodeIfPresent(Int.self, forKey: .estimatedMinutes)
        source          = try c.decodeIfPresent(String.self, forKey: .source) ?? "manual"
        tags            = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        planType        = try c.decodeIfPresent(String.self, forKey: .planType)
        brainDumpRaw    = try c.decodeIfPresent(String.self, forKey: .brainDumpRaw)
        createdAt       = try c.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
        updatedAt       = try c.decodeIfPresent(String.self, forKey: .updatedAt) ?? ""
    }

    var priorityLabel: String {
        switch priority {
        case 1: return "Low"
        case 2: return "Med"
        case 3: return "High"
        case 4: return "Urgent"
        default: return "—"
        }
    }

    var deadlineDate: Date? {
        guard let dl = deadline else { return nil }
        return ISO8601DateFormatter().date(from: dl)
    }

    var isOverdue: Bool {
        guard let d = deadlineDate else { return false }
        return d < Date() && status != "done"
    }
}

// MARK: - Step

struct StepOut: Codable, Identifiable {
    let id: String
    var taskId: String
    var sortOrder: Int
    var title: String
    var description: String?
    var estimatedMinutes: Int?
    var status: String
    var checkpointNote: String?
    var lastCheckedAt: String?
    var completedAt: String?
    var createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, title, description, status
        case taskId = "task_id"
        case sortOrder = "sort_order"
        case estimatedMinutes = "estimated_minutes"
        case checkpointNote = "checkpoint_note"
        case lastCheckedAt = "last_checked_at"
        case completedAt = "completed_at"
        case createdAt = "created_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id               = try c.decode(String.self, forKey: .id)
        taskId           = try c.decodeIfPresent(String.self, forKey: .taskId) ?? ""
        sortOrder        = try c.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
        title            = try c.decode(String.self, forKey: .title)
        description      = try c.decodeIfPresent(String.self, forKey: .description)
        estimatedMinutes = try c.decodeIfPresent(Int.self, forKey: .estimatedMinutes)
        status           = try c.decodeIfPresent(String.self, forKey: .status) ?? "pending"
        checkpointNote   = try c.decodeIfPresent(String.self, forKey: .checkpointNote)
        lastCheckedAt    = try c.decodeIfPresent(String.self, forKey: .lastCheckedAt)
        completedAt      = try c.decodeIfPresent(String.self, forKey: .completedAt)
        createdAt        = try c.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
    }

    var isDone: Bool { status == "done" }
    var isInProgress: Bool { status == "in_progress" }
}

// MARK: - Session

struct SessionOut: Codable, Identifiable {
    let id: String
    var userId: String
    var taskId: String?
    var platform: String
    var startedAt: String
    var endedAt: String?
    var status: String
    var createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, platform, status
        case userId = "user_id"
        case taskId = "task_id"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case createdAt = "created_at"
    }
}

// MARK: - Brain Dump

struct BrainDumpResponse: Codable {
    var parsedTasks: [ParsedTask]
    var unparseableFragments: [String]
    var askForPlans: Bool

    enum CodingKeys: String, CodingKey {
        case parsedTasks = "parsed_tasks"
        case unparseableFragments = "unparseable_fragments"
        case askForPlans = "ask_for_plans"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        parsedTasks          = try c.decodeIfPresent([ParsedTask].self, forKey: .parsedTasks) ?? []
        unparseableFragments = try c.decodeIfPresent([String].self, forKey: .unparseableFragments) ?? []
        askForPlans          = try c.decodeIfPresent(Bool.self, forKey: .askForPlans) ?? false
    }
}

struct ParsedSubtask: Codable, Identifiable {
    var id = UUID()
    var title: String
    var description: String?
    var deadline: String?
    var estimatedMinutes: Int?
    var suggested: Bool

    enum CodingKeys: String, CodingKey {
        case title, description, deadline, suggested
        case estimatedMinutes = "estimated_minutes"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title            = try c.decode(String.self, forKey: .title)
        description      = try c.decodeIfPresent(String.self, forKey: .description)
        deadline         = try c.decodeIfPresent(String.self, forKey: .deadline)
        estimatedMinutes = try c.decodeIfPresent(Int.self, forKey: .estimatedMinutes)
        suggested        = try c.decodeIfPresent(Bool.self, forKey: .suggested) ?? false
    }
}

struct ParsedTask: Codable, Identifiable {
    var id = UUID()
    var taskId: String?
    var title: String
    var description: String?
    var priority: Int
    var deadline: String?
    var estimatedMinutes: Int?
    var source: String
    var tags: [String]
    var subtasks: [ParsedSubtask]

    enum CodingKeys: String, CodingKey {
        case title, description, priority, deadline, source, tags, subtasks
        case taskId = "task_id"
        case estimatedMinutes = "estimated_minutes"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        taskId           = try c.decodeIfPresent(String.self, forKey: .taskId)
        title            = try c.decode(String.self, forKey: .title)
        description      = try c.decodeIfPresent(String.self, forKey: .description)
        priority         = try c.decodeIfPresent(Int.self, forKey: .priority) ?? 0
        deadline         = try c.decodeIfPresent(String.self, forKey: .deadline)
        estimatedMinutes = try c.decodeIfPresent(Int.self, forKey: .estimatedMinutes)
        source           = try c.decodeIfPresent(String.self, forKey: .source) ?? "brain_dump"
        tags             = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        subtasks         = try c.decodeIfPresent([ParsedSubtask].self, forKey: .subtasks) ?? []
    }

    var priorityLabel: String {
        switch priority {
        case 1: return "Low"
        case 2: return "Med"
        case 3: return "High"
        case 4: return "Urgent"
        default: return "—"
        }
    }
}

// MARK: - Plan

struct PlanResponse: Codable {
    var taskId: String
    var planType: String
    var steps: [StepOut]

    enum CodingKeys: String, CodingKey {
        case steps
        case taskId = "task_id"
        case planType = "plan_type"
    }
}

// MARK: - Session Resume

struct ResumeResponse: Codable {
    var sessionId: String
    var task: ResumeTask
    var currentStep: StepOut?
    var progress: SessionProgress
    var resumeCard: ResumeCard

    enum CodingKeys: String, CodingKey {
        case task, progress
        case sessionId = "session_id"
        case currentStep = "current_step"
        case resumeCard = "resume_card"
    }
}

struct ResumeTask: Codable {
    var title: String
    var overallGoal: String?

    enum CodingKeys: String, CodingKey {
        case title
        case overallGoal = "overall_goal"
    }
}

struct SessionProgress: Codable {
    var completed: Int
    var total: Int
    var attentionScore: Int?
    var distractionCount: Int

    enum CodingKeys: String, CodingKey {
        case completed, total
        case attentionScore = "attention_score"
        case distractionCount = "distraction_count"
    }
}

struct ResumeCard: Codable {
    var welcomeBack: String
    var youWereDoing: String
    var nextStep: String
    var motivation: String

    enum CodingKeys: String, CodingKey {
        case motivation
        case welcomeBack = "welcome_back"
        case youWereDoing = "you_were_doing"
        case nextStep = "next_step"
    }
}

// MARK: - App Check (Distraction Intercept)

struct AppCheckResponse: Codable {
    var isDistractionApp: Bool
    var pendingTaskCount: Int
    var mostUrgentTask: UrgentTask?
    var nudge: String?

    enum CodingKeys: String, CodingKey {
        case nudge
        case isDistractionApp = "is_distraction_app"
        case pendingTaskCount = "pending_task_count"
        case mostUrgentTask = "most_urgent_task"
    }
}

struct UrgentTask: Codable {
    var title: String
    var priority: Int
    var deadline: String?
    var currentStep: String?
    var stepsRemaining: Int?

    enum CodingKeys: String, CodingKey {
        case title, priority, deadline
        case currentStep = "current_step"
        case stepsRemaining = "steps_remaining"
    }
}

// MARK: - Join Session

struct JoinSessionResponse: Codable {
    var sessionId: String
    var joined: Bool
    var task: ResumeTask?
    var currentStep: StepOut?
    var allSteps: [StepOut]
    var suggestedAppScheme: String?
    var suggestedAppName: String?

    enum CodingKeys: String, CodingKey {
        case joined
        case sessionId = "session_id"
        case task
        case currentStep = "current_step"
        case allSteps = "all_steps"
        case suggestedAppScheme = "suggested_app_scheme"
        case suggestedAppName = "suggested_app_name"
    }
}
