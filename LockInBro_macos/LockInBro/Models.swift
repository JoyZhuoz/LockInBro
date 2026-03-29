// Models.swift — LockInBro data models

import Foundation

// MARK: - Auth

struct User: Codable, Identifiable {
    let id: String
    let email: String?
    let displayName: String?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, email
        case displayName = "display_name"
        case createdAt = "created_at"
    }
}

struct AuthResponse: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
    let user: User

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case user
    }
}

// MARK: - Tasks

struct AppTask: Identifiable, Codable, Hashable {
    let id: String
    var title: String
    var description: String?
    var priority: Int
    var status: String
    var deadline: String?
    var estimatedMinutes: Int?
    let source: String
    var tags: [String]
    var planType: String?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, title, description, priority, status, deadline, tags, source
        case estimatedMinutes = "estimated_minutes"
        case planType = "plan_type"
        case createdAt = "created_at"
    }

    var priorityLabel: String {
        switch priority {
        case 4: return "Urgent"
        case 3: return "High"
        case 2: return "Medium"
        case 1: return "Low"
        default: return "Unset"
        }
    }

    var priorityColor: String {
        switch priority {
        case 4: return "red"
        case 3: return "orange"
        case 2: return "yellow"
        case 1: return "green"
        default: return "gray"
        }
    }

    var isActive: Bool { status == "in_progress" }
    var isDone: Bool { status == "done" }
}

// MARK: - Steps

struct Step: Identifiable, Codable, Hashable {
    let id: String
    let taskId: String
    let sortOrder: Int
    var title: String
    var description: String?
    var estimatedMinutes: Int?
    var status: String
    var checkpointNote: String?
    var lastCheckedAt: String?
    var completedAt: String?
    let createdAt: String

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

    var isDone: Bool { status == "done" }
    var isActive: Bool { status == "in_progress" }
}

// MARK: - Focus Session

/// Subset of the JSONB checkpoint dict stored on the backend session record.
/// Populated by argus when it POSTs to /distractions/analyze-result.
struct SessionCheckpoint: Codable {
    /// Written by POST /distractions/analyze-result (argus live mode).
    let lastVlmSummary: String?
    /// Written by POST /distractions/analyze-screenshot (Swift fallback).
    let lastScreenshotAnalysis: String?
    /// Concise summary of the last completed action.
    let lastActionSummary: String?
    /// Frontmost application name at last checkpoint.
    let activeApp: String?
    /// Running count of distractions logged during this session.
    let distractionCount: Int?

    /// Returns whichever VLM summary field is populated, preferring the most recent.
    var vlmSummary: String? { lastVlmSummary ?? lastScreenshotAnalysis }

    enum CodingKeys: String, CodingKey {
        case lastVlmSummary = "last_vlm_summary"
        case lastScreenshotAnalysis = "last_screenshot_analysis"
        case lastActionSummary = "last_action_summary"
        case activeApp = "active_app"
        case distractionCount = "distraction_count"
    }
}

struct FocusSession: Identifiable, Codable {
    let id: String
    let userId: String
    var taskId: String?
    let platform: String
    let startedAt: String
    var endedAt: String?
    var status: String
    /// Live checkpoint data written by argus (nil when no checkpoint exists yet).
    var checkpoint: SessionCheckpoint?

    enum CodingKeys: String, CodingKey {
        case id, platform, status, checkpoint
        case userId = "user_id"
        case taskId = "task_id"
        case startedAt = "started_at"
        case endedAt = "ended_at"
    }
}

// MARK: - Brain Dump

struct BrainDumpResponse: Codable {
    let parsedTasks: [ParsedTask]
    let unparseableFragments: [String]
    let askForPlans: Bool

    enum CodingKeys: String, CodingKey {
        case parsedTasks = "parsed_tasks"
        case unparseableFragments = "unparseable_fragments"
        case askForPlans = "ask_for_plans"
    }
}

struct ParsedTask: Codable, Identifiable {
    // local UUID for list identity before saving
    var localId: String = UUID().uuidString
    var id: String { taskId ?? localId }

    /// Set by backend when the brain-dump endpoint creates the task automatically.
    let taskId: String?
    let title: String
    let description: String?
    let priority: Int
    let deadline: String?
    let estimatedMinutes: Int?
    let tags: [String]

    enum CodingKeys: String, CodingKey {
        case taskId = "task_id"
        case title, description, priority, deadline, tags
        case estimatedMinutes = "estimated_minutes"
    }
}

// MARK: - Step Planning

struct StepPlanResponse: Codable {
    let taskId: String
    let planType: String
    let steps: [Step]

    enum CodingKeys: String, CodingKey {
        case taskId = "task_id"
        case planType = "plan_type"
        case steps
    }
}

// MARK: - Distraction Analysis

/// A single action the proactive agent can take on the user's behalf.
struct ProposedAction: Codable {
    let label: String        // e.g. "Extract all 14 events"
    let actionType: String   // e.g. "auto_extract", "brain_dump"
    let details: String?

    enum CodingKeys: String, CodingKey {
        case label, details
        case actionType = "action_type"
    }
}

/// Friction pattern detected by the upgraded Argus VLM prompt.
struct FrictionInfo: Codable {
    /// repetitive_loop | stalled | tedious_manual | context_overhead | task_resumption | none
    let type: String
    let confidence: Double
    let description: String?
    let proposedActions: [ProposedAction]
    let sourceContext: String?
    let targetContext: String?

    enum CodingKeys: String, CodingKey {
        case type, confidence, description
        case proposedActions = "proposed_actions"
        case sourceContext = "source_context"
        case targetContext = "target_context"
    }

    var isActionable: Bool { type != "none" && confidence > 0.5 }
    var isResumption: Bool { type == "task_resumption" }
}

/// Session lifecycle action suggested by the VLM (new argus feature).
struct SessionAction: Codable {
    /// resume | switch | complete | start_new | none
    let type: String
    let sessionId: String?
    let reason: String?

    enum CodingKeys: String, CodingKey {
        case type, reason
        case sessionId = "session_id"
    }
}

struct DistractionAnalysisResponse: Codable {
    let onTask: Bool
    let currentStepId: String?
    let checkpointNoteUpdate: String?
    let stepsCompleted: [String]
    // Upgraded Argus prompt fields (nil when backend uses legacy prompt)
    let friction: FrictionInfo?
    let sessionAction: SessionAction?   // new argus: session lifecycle suggestions
    let intent: String?                 // skimming | engaged | unclear | null
    let distractionType: String?
    let appName: String?
    let confidence: Double
    let gentleNudge: String?
    let vlmSummary: String?

    enum CodingKeys: String, CodingKey {
        case onTask = "on_task"
        case currentStepId = "current_step_id"
        case checkpointNoteUpdate = "checkpoint_note_update"
        case stepsCompleted = "steps_completed"
        case friction, intent
        case sessionAction = "session_action"
        case distractionType = "distraction_type"
        case appName = "app_name"
        case confidence
        case gentleNudge = "gentle_nudge"
        case vlmSummary = "vlm_summary"
    }
}

// MARK: - Session Resume

struct ResumeCard: Codable {
    let welcomeBack: String
    let youWereDoing: String
    let nextStep: String
    let motivation: String

    enum CodingKeys: String, CodingKey {
        case welcomeBack = "welcome_back"
        case youWereDoing = "you_were_doing"
        case nextStep = "next_step"
        case motivation
    }
}

struct StepSummary: Codable {
    let id: String
    let title: String
    let checkpointNote: String?

    enum CodingKeys: String, CodingKey {
        case id, title
        case checkpointNote = "checkpoint_note"
    }
}

struct ProgressSummary: Codable {
    let completed: Int
    let total: Int
    let attentionScore: Int?
    let distractionCount: Int?

    enum CodingKeys: String, CodingKey {
        case completed, total
        case attentionScore = "attention_score"
        case distractionCount = "distraction_count"
    }
}

struct ResumeResponse: Codable {
    let sessionId: String
    let resumeCard: ResumeCard
    let currentStep: StepSummary?
    let progress: ProgressSummary?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case resumeCard = "resume_card"
        case currentStep = "current_step"
        case progress
    }
}

// MARK: - Proactive Agent

struct ProactiveCard: Identifiable {
    enum Source {
        /// VLM detected a friction pattern (primary signal — from upgraded Argus prompt).
        case vlmFriction(frictionType: String, description: String?, actions: [ProposedAction])
        /// Heuristic app-switch loop detected by NSWorkspace observer (fallback when VLM hasn't returned friction yet).
        case appSwitchLoop(apps: [String], switchCount: Int)
        /// VLM suggests a session lifecycle action (new argus: resume, switch, complete, start_new).
        case sessionAction(type: String, taskTitle: String, checkpoint: String, reason: String, sessionId: String?)
    }

    let id = UUID()
    let source: Source

    /// Human-readable title for the card header.
    var title: String {
        switch source {
        case .vlmFriction(let frictionType, _, _):
            switch frictionType {
            case "repetitive_loop":   return "Repetitive Pattern Detected"
            case "stalled":           return "Looks Like You're Stuck"
            case "tedious_manual":    return "I Can Help With This"
            case "context_overhead":  return "Too Many Windows?"
            default:                  return "I Noticed Something"
            }
        case .appSwitchLoop:
            return "Repetitive Pattern Detected"
        case .sessionAction(let type, let taskTitle, _, _, _):
            switch type {
            case "resume":     return "Resume: \(taskTitle)"
            case "switch":     return "Switch to: \(taskTitle)"
            case "complete":   return "Done with \(taskTitle)?"
            case "start_new":  return "Start a Focus Session?"
            default:           return "Session Suggestion"
            }
        }
    }

    /// SF Symbol name for the card icon.
    var icon: String {
        switch source {
        case .vlmFriction(let frictionType, _, _):
            switch frictionType {
            case "repetitive_loop":   return "arrow.triangle.2.circlepath"
            case "stalled":           return "pause.circle"
            case "tedious_manual":    return "wand.and.stars"
            case "context_overhead":  return "macwindow"
            default:                  return "sparkles"
            }
        case .appSwitchLoop:
            return "arrow.triangle.2.circlepath"
        case .sessionAction(let type, _, _, _, _):
            switch type {
            case "resume":     return "arrow.counterclockwise.circle"
            case "switch":     return "arrow.left.arrow.right"
            case "complete":   return "checkmark.circle"
            case "start_new":  return "plus.circle"
            default:           return "circle"
            }
        }
    }
}

// MARK: - API Error

struct APIErrorResponse: Codable {
    let detail: String
}
