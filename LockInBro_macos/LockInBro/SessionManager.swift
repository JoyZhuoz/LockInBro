// SessionManager.swift — Focus session state, screenshot engine, distraction detection

import AppKit
import SwiftUI
import UserNotifications
import ScreenCaptureKit

@Observable
@MainActor
final class SessionManager {
    static let shared = SessionManager()

    // MARK: - State

    var activeSession: FocusSession?
    var activeTask: AppTask?
    var activeSteps: [Step] = []
    var currentStepIndex: Int = 0
    var isSessionActive: Bool = false
    var sessionStartDate: Date?
    var distractionCount: Int = 0
    var lastNudge: String?
    var resumeCard: ResumeCard?
    var showingResumeCard: Bool = false
    var errorMessage: String?
    var isLoading: Bool = false

    // Proactive agent
    var proactiveCard: ProactiveCard?
    /// Set when the user approves a proposed action — shown as a confirmation toast
    var approvedActionLabel: String?
    /// Latest one-sentence summary from the VLM, shown in the floating HUD
    var latestVlmSummary: String?
    /// True while the argus executor is running an approved action
    var isExecuting: Bool = false
    /// Result produced by the executor's output() tool — shown as a sticky card in the HUD
    var executorOutput: (title: String, content: String)?
    /// Non-nil when monitoring is in an error or degraded state — shown in HUD as a warning banner
    var monitoringError: String?

    // Screenshot engine
    var isCapturing: Bool = false

    private var captureTask: Task<Void, Never>?
    private let captureInterval: TimeInterval = 5.0

    // Rolling screenshot history buffer (max 4 entries, ~20-second window)
    // Provides temporal context to the VLM so it can detect patterns across captures.
    private struct ScreenshotHistoryEntry {
        let summary: String   // vlm_summary text from the previous analysis
        let timestamp: Date
    }
    @ObservationIgnored private var screenshotHistory: [ScreenshotHistoryEntry] = []

    // App switch tracking
    @ObservationIgnored private var appSwitches: [(name: String, bundleId: String, time: Date)] = []
    @ObservationIgnored private var appSwitchObserver: (any NSObjectProtocol)?
    @ObservationIgnored private var lastApp: (name: String, bundleId: String) = ("", "")
    @ObservationIgnored private var lastAppEnteredAt: Date = Date()

    // Argus subprocess (device-side VLM)
    @ObservationIgnored private var argusProcess: Process?
    @ObservationIgnored private var argusReadTask: Task<Void, Never>?
    @ObservationIgnored private var argusStdinPipe: Pipe?
    @ObservationIgnored private var argusRestartCount = 0
    @ObservationIgnored private var argusCaptureFeedTask: Task<Void, Never>?
    private let argusCaptureFilePath = "/tmp/lockinbro_capture.jpg"
    /// Whether the current proactive card came from VLM vs local heuristic
    @ObservationIgnored private var proactiveCardNeedsArgusResponse = false
    @ObservationIgnored private var proactiveCardTimer: Task<Void, Never>?
    /// Polls the backend session checkpoint every 15s to surface VLM summaries in the HUD.
    @ObservationIgnored private var checkpointPollTask: Task<Void, Never>?
    private let argusPythonPath = "/Users/joyzhuo/miniconda3/envs/gmr/bin/python3"
    private let argusRepoPath = "/Users/joyzhuo/yhack/lockinbro-argus"

    private init() {}

    // MARK: - Computed

    var currentStep: Step? {
        guard currentStepIndex < activeSteps.count else { return nil }
        return activeSteps[currentStepIndex]
    }

    var completedCount: Int { activeSteps.filter(\.isDone).count }
    var totalSteps: Int { activeSteps.count }

    var sessionElapsed: TimeInterval {
        guard let start = sessionStartDate else { return 0 }
        return Date().timeIntervalSince(start)
    }

    // MARK: - Always-On Monitoring

    /// Immediately shuts down all monitoring without making any API calls.
    /// Called on logout and session expiry so no further authenticated requests are made.
    func stopMonitoring() {
        stopArgus()
        stopCapture()
        stopAppObserver()
        stopCheckpointPolling()
        proactiveCardTimer?.cancel()
        proactiveCardTimer = nil
        activeSession = nil
        activeTask = nil
        activeSteps = []
        isSessionActive = false
        sessionStartDate = nil
        lastNudge = nil
        resumeCard = nil
        showingResumeCard = false
        proactiveCard = nil
        approvedActionLabel = nil
        latestVlmSummary = nil
        isExecuting = false
        executorOutput = nil
        monitoringError = nil
        screenshotHistory = []
        persistedSessionId = nil
        argusRestartCount = 0
    }

    /// Called once after login. Auto-resumes any existing active session and
    /// starts argus in monitoring mode (dry-run if no session is found).
    func startMonitoring() async {
        guard TokenStore.shared.token != nil else { return }
        guard !isCapturing else { return }  // already running

        monitoringError = nil
        argusRestartCount = 0
        await requestNotificationPermission()

        // Silent preflight — if permission isn't granted yet, ask once then bail.
        // CGPreflightScreenCaptureAccess never shows UI; CGRequestScreenCaptureAccess shows
        // the one-time system dialog and returns immediately (user responds async in Settings).
        if !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
            monitoringError = "Screen Recording permission required — enable in System Settings \u{2192} Privacy & Security \u{2192} Screen Recording, then tap Retry"
            return
        }

        do {
            if let existing = try await APIClient.shared.getActiveSession() {
                // Auto-resume the active session without user interaction
                await autoResumeSession(existing)
            } else {
                // No session — start argus in monitoring-only mode (dry-run)
                startArgus(session: nil, task: nil, dryRun: true)
                startAppObserver()
            }
        } catch {
            // Network unavailable — still start monitoring locally
            startArgus(session: nil, task: nil, dryRun: true)
            startAppObserver()
        }
    }

    /// Silently resume an active session returned by the backend (no loading state shown).
    private func autoResumeSession(_ session: FocusSession) async {
        activeSession = session
        persistedSessionId = session.id
        isSessionActive = true
        sessionStartDate = Date()
        distractionCount = 0
        lastNudge = nil
        screenshotHistory = []

        if let taskId = session.taskId {
            do {
                let tasks = try await APIClient.shared.getTasks()
                activeTask = tasks.first(where: { $0.id == taskId })
                if let task = activeTask {
                    let steps = try await APIClient.shared.getSteps(taskId: task.id)
                    activeSteps = steps.sorted { $0.sortOrder < $1.sortOrder }
                    currentStepIndex = activeSteps.firstIndex(where: { $0.isActive })
                        ?? activeSteps.firstIndex(where: { $0.status == "pending" })
                        ?? 0
                }
            } catch {}
        }

        // Show attachment status in the HUD immediately — replaced by real VLM summary later
        let shortId = String(session.id.prefix(8))
        let taskLabel = activeTask?.title ?? "(no task)"
        latestVlmSummary = "Attached to session \(shortId) · \(taskLabel)"

        argusRestartCount = 0
        startArgus(session: session, task: activeTask, dryRun: false)
        startAppObserver()
        startCheckpointPolling()
    }

    // MARK: - Session Lifecycle

    // Persisted so we can end a stale session after an app restart
    private var persistedSessionId: String? {
        get { UserDefaults.standard.string(forKey: "lockInBro.lastSessionId") }
        set {
            if let v = newValue { UserDefaults.standard.set(v, forKey: "lockInBro.lastSessionId") }
            else { UserDefaults.standard.removeObject(forKey: "lockInBro.lastSessionId") }
        }
    }

    func startSession(task: AppTask?) async {
        isLoading = true
        errorMessage = nil
        do {
            // Backend idempotently returns existing active session (never 409).
            // Proactively end any existing session so we always start a fresh one.
            var staleId: String? = activeSession?.id ?? persistedSessionId
            if staleId == nil {
                staleId = (try? await APIClient.shared.getActiveSession())?.id
            }
            if let id = staleId {
                _ = try? await APIClient.shared.endSession(sessionId: id, status: "completed")
            }

            let session = try await APIClient.shared.startSession(taskId: task?.id)
            activeSession = session
            persistedSessionId = session.id
            activeTask = task
            activeSteps = []
            currentStepIndex = 0
            isSessionActive = true
            sessionStartDate = Date()
            distractionCount = 0
            lastNudge = nil

            if let task {
                let steps = try await APIClient.shared.getSteps(taskId: task.id)
                activeSteps = steps.sorted { $0.sortOrder < $1.sortOrder }
                // Pick first in-progress or first pending step
                currentStepIndex = activeSteps.firstIndex(where: { $0.isActive })
                    ?? activeSteps.firstIndex(where: { $0.status == "pending" })
                    ?? 0
            }

            screenshotHistory = []
            await requestNotificationPermission()
            argusRestartCount = 0
            startArgus(session: session, task: task, dryRun: false)
            startAppObserver()
            startCheckpointPolling()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func endSession(status: String = "completed") async {
        stopCapture()
        stopAppObserver()
        stopCheckpointPolling()
        if let session = activeSession {
            _ = try? await APIClient.shared.endSession(sessionId: session.id, status: status)
        }
        activeSession = nil
        activeTask = nil
        activeSteps = []
        isSessionActive = false
        sessionStartDate = nil
        lastNudge = nil
        resumeCard = nil
        showingResumeCard = false
        proactiveCard = nil
        approvedActionLabel = nil
        latestVlmSummary = nil
        isExecuting = false
        executorOutput = nil
        proactiveCardTimer?.cancel()
        proactiveCardTimer = nil
        screenshotHistory = []
        persistedSessionId = nil

        // Resume always-on monitoring in dry-run mode (argus watches screen without an active session)
        if TokenStore.shared.token != nil {
            startArgus(session: nil, task: nil, dryRun: true)
            startAppObserver()
        }
    }

    func fetchResumeCard() async {
        guard let session = activeSession else { return }
        do {
            let response = try await APIClient.shared.resumeSession(sessionId: session.id)
            resumeCard = response.resumeCard
            showingResumeCard = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func completeCurrentStep() async {
        guard let step = currentStep else { return }
        do {
            let updated = try await APIClient.shared.completeStep(stepId: step.id)
            if let idx = activeSteps.firstIndex(where: { $0.id == updated.id }) {
                activeSteps[idx] = updated
            }
            // Advance to next pending
            if let next = activeSteps.firstIndex(where: { $0.status == "pending" }) {
                currentStepIndex = next
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Proactive Card Lifecycle

    /// Show a proactive card and start the 15-second auto-dismiss timer.
    /// - Parameter vlmCard: Pass true when the card came from VLM so argus gets a stdin response on dismiss.
    private func showProactiveCard(_ card: ProactiveCard, vlmCard: Bool = false) {
        proactiveCardNeedsArgusResponse = vlmCard
        proactiveCardTimer?.cancel()
        withAnimation { proactiveCard = card }

        proactiveCardTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard !Task.isCancelled, let self else { return }
            await MainActor.run { self.dismissProactiveCard() }
        }
    }

    /// Dismiss the current card (user tapped "Not now" or 15s elapsed).
    func dismissProactiveCard() {
        proactiveCardTimer?.cancel()
        proactiveCardTimer = nil
        withAnimation { proactiveCard = nil }
        if proactiveCardNeedsArgusResponse { sendArgusResponse(0) }
        proactiveCardNeedsArgusResponse = false
    }

    /// Approve action at the given index (0-based). Argus stdin uses 1-based (1 = action 0).
    func approveProactiveCard(actionIndex: Int) {
        proactiveCardTimer?.cancel()
        proactiveCardTimer = nil
        withAnimation { proactiveCard = nil }
        if proactiveCardNeedsArgusResponse {
            sendArgusResponse(actionIndex + 1)
            isExecuting = true
        }
        proactiveCardNeedsArgusResponse = false
    }

    /// Handle a SESSION_ACTION IPC line from the new argus — show a ProactiveCard for session lifecycle.
    private func applySessionAction(_ obj: [String: Any]) {
        guard proactiveCard == nil else { return }
        let type = obj["type"] as? String ?? "none"
        guard type != "none" else { return }
        let taskTitle = obj["task_title"] as? String ?? ""
        let checkpoint = obj["checkpoint_note"] as? String ?? ""
        let reason = obj["reason"] as? String ?? ""
        let sessionId = obj["session_id"] as? String
        let card = ProactiveCard(source: .sessionAction(
            type: type,
            taskTitle: taskTitle,
            checkpoint: checkpoint,
            reason: reason,
            sessionId: sessionId
        ))
        showProactiveCard(card, vlmCard: true)
    }

    private func sendArgusResponse(_ choice: Int) {
        guard let pipe = argusStdinPipe,
              let data = "\(choice)\n".data(using: .utf8) else { return }
        try? pipe.fileHandleForWriting.write(contentsOf: data)
    }

    // MARK: - App Switch Observer

    private func startAppObserver() {
        let current = NSWorkspace.shared.frontmostApplication
        lastApp = (current?.localizedName ?? "", current?.bundleIdentifier ?? "")
        lastAppEnteredAt = Date()
        appSwitches = []

        appSwitchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            else { return }
            Task { @MainActor [weak self] in self?.handleAppSwitch(app: app) }
        }
    }

    private func stopAppObserver() {
        if let observer = appSwitchObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            appSwitchObserver = nil
        }
        appSwitches = []
    }

    private func handleAppSwitch(app: NSRunningApplication) {
        let name = app.localizedName ?? "Unknown"
        let bundleId = app.bundleIdentifier ?? ""
        let now = Date()

        guard name != lastApp.name else { return }

        // Log previous app's dwell time to backend (fire-and-forget)
        let duration = max(1, Int(now.timeIntervalSince(lastAppEnteredAt)))
        let prev = lastApp
        if let session = activeSession, !prev.name.isEmpty {
            Task {
                _ = try? await APIClient.shared.appActivity(
                    sessionId: session.id,
                    appBundleId: prev.bundleId,
                    appName: prev.name,
                    durationSeconds: duration
                )
            }
        }

        lastApp = (name, bundleId)
        lastAppEnteredAt = now

        appSwitches.append((name: name, bundleId: bundleId, time: now))
        if appSwitches.count > 30 { appSwitches.removeFirst() }

        // Only trigger card during active session and when none is already showing
        guard isSessionActive, proactiveCard == nil else { return }
        if let loop = detectRepetitiveLoop() {
            showProactiveCard(ProactiveCard(source: .appSwitchLoop(apps: loop.apps, switchCount: loop.count)), vlmCard: false)
        }
    }

    // Detects a back-and-forth pattern between exactly 2 apps within a 5-minute window.
    // Requires 3 full cycles (6 consecutive alternating switches) to avoid false positives.
    private func detectRepetitiveLoop() -> (apps: [String], count: Int)? {
        let cutoff = Date().addingTimeInterval(-300)
        let recent = appSwitches.filter { $0.time > cutoff }.map(\.name)
        guard recent.count >= 6 else { return nil }

        let last6 = Array(recent.suffix(6))
        guard Set(last6).count == 2 else { return nil }

        // Strictly alternating — no two consecutive identical app names
        for i in 1..<last6.count {
            if last6[i] == last6[i - 1] { return nil }
        }
        return (apps: Array(Set(last6)).sorted(), count: 3)
    }

    // MARK: - Argus Subprocess (device-side VLM)

    /// Launch the argus Python daemon as a subprocess.
    /// Argus captures screenshots itself, runs them through a local VLM (Ollama/Gemini),
    /// posts results to the backend, and emits RESULT:{json} lines to stdout for Swift to consume.
    /// Falls back to the internal `startCapture()` loop if the process cannot be launched (active sessions only).
    /// - Parameters:
    ///   - session: Active focus session, or nil for monitoring-only (dry-run) mode.
    ///   - task: The task associated with the session, if any.
    ///   - dryRun: When true, argus analyzes but does not POST results to the backend.
    /// Kill any orphaned argus Python processes left over from previous app launches.
    /// Swift's `Process.terminate()` only kills the process we launched in this session;
    /// processes from earlier launches (e.g. after a crash or force-quit) accumulate as orphans.
    /// `pkill` sweeps them all away before we launch a fresh instance.
    private func killOrphanedArgusProcesses() {
        let pkill = Process()
        pkill.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        pkill.arguments = ["-f", "python3 -m argus"]
        try? pkill.run()
        // Don't waitUntilExit — pkill is fast; failure (no matches) is fine
    }

    private func startArgus(session: FocusSession?, task: AppTask?, dryRun: Bool = false) {
        // Kill orphaned argus processes from previous app runs, then shut down our own tracked process
        killOrphanedArgusProcesses()
        stopArgus()

        guard FileManager.default.fileExists(atPath: argusPythonPath),
              FileManager.default.fileExists(atPath: argusRepoPath) else {
            // Fall back to built-in capture only when we have an active session
            if session != nil { startCapture() }
            return
        }

        // Encode steps as JSON for --steps-json arg
        var stepsJSONString = "[]"
        if !activeSteps.isEmpty {
            let stepsArray: [[String: Any]] = activeSteps.map { step in
                var s: [String: Any] = [
                    "id": step.id,
                    "sort_order": step.sortOrder,
                    "title": step.title,
                    "status": step.status
                ]
                if let note = step.checkpointNote { s["checkpoint_note"] = note }
                return s
            }
            if let data = try? JSONSerialization.data(withJSONObject: stepsArray),
               let str = String(data: data, encoding: .utf8) {
                stepsJSONString = str
            }
        }

        let jwt = TokenStore.shared.token ?? ""
        let geminiKey = UserDefaults.standard.string(forKey: "geminiApiKey") ?? ""

        var arguments = [
            "-m", "argus",
            "--session-id", session?.id ?? "00000000-0000-0000-0000-000000000000",
            "--task-title", task?.title ?? "(no task)",
            "--task-goal", task?.description ?? "",
            "--steps-json", stepsJSONString,
            "--window-title", NSWorkspace.shared.frontmostApplication?.localizedName ?? "",
            "--vlm", "gemini",
            "--backend-url", "https://wahwa.com/api/v1"
        ]
        // Only pass JWT when we actually have one — passing an empty string
        // causes argus to make unauthenticated requests (401s).
        if !jwt.isEmpty {
            arguments += ["--jwt", jwt]
        }
        if dryRun {
            arguments.append("--dry-run")
        }
        if !geminiKey.isEmpty {
            arguments += ["--gemini-key", geminiKey]
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: argusPythonPath)
        process.currentDirectoryURL = URL(fileURLWithPath: argusRepoPath)
        process.arguments = arguments
        // Force unbuffered stdout so `print(json.dumps(...))` in dry-run mode
        // arrives at our pipe reader immediately instead of sitting in Python's
        // block-level pipe buffer until it fills up.
        var env = ProcessInfo.processInfo.environment
        env["PYTHONUNBUFFERED"] = "1"
        process.environment = env

        // Pipe stdout for RESULT:/STATUS:/EXEC_OUTPUT: lines
        // stderr is NOT captured — leaving it unset lets argus log to the system console
        // without risk of the pipe buffer filling and blocking the process.
        let stdoutPipe = Pipe()
        let stdinPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardInput = stdinPipe

        print("[Argus] Launching: \(argusPythonPath) \(arguments.joined(separator: " "))")
        do {
            try process.run()
            print("[Argus] Process started, PID=\(process.processIdentifier)")
        } catch {
            print("[Argus] Launch FAILED: \(error)")
            monitoringError = "Failed to launch monitoring: \(error.localizedDescription)"
            if session != nil { startCapture() }
            return
        }

        argusProcess = process
        argusStdinPipe = stdinPipe
        isCapturing = true
        startArgusCaptureFeed()

        // Read stdout in a background task.
        // In dry-run mode argus emits json.dumps(payload, indent=2) — multi-line JSON.
        // We accumulate lines between the root '{' and '}' and decode the result.
        // In live session mode argus POSTs to the backend directly and stdout is silent;
        // the loop just waits for the pipe to close (process exit) and then restarts argus.
        let fileHandle = stdoutPipe.fileHandleForReading

        argusReadTask = Task { [weak self] in
            var jsonLines: [String] = []
            var inJsonBlock = false

            do {
                for try await line in fileHandle.bytes.lines {
                    guard let self, !Task.isCancelled else { break }

                    print("[Argus stdout] \(line)")

                    // Detect start of a root-level JSON object
                    if line == "{" {
                        inJsonBlock = true
                        jsonLines = [line]
                    } else if inJsonBlock {
                        jsonLines.append(line)
                        // Root close brace — complete JSON object received
                        if line == "}" {
                            let jsonStr = jsonLines.joined(separator: "\n")
                            print("[Argus JSON] Received complete block (\(jsonStr.count) chars)")
                            if let data = jsonStr.data(using: .utf8) {
                                if let result = try? JSONDecoder().decode(DistractionAnalysisResponse.self, from: data) {
                                    print("[Argus JSON] Decoded OK — on_task=\(result.onTask), friction=\(result.friction?.type ?? "none")")
                                    await MainActor.run {
                                        if self.monitoringError != nil { self.monitoringError = nil }
                                        self.applyDistractionResult(result)
                                    }
                                } else {
                                    print("[Argus JSON] Decode FAILED — raw:\n\(jsonStr)")
                                }
                            }
                            jsonLines = []
                            inJsonBlock = false
                        }
                    }
                }
            } catch {
                print("[Argus] Pipe read error: \(error)")
            }

            // Pipe closed — argus exited. Restart unless we deliberately cancelled (stopArgus).
            print("[Argus] Pipe closed — process exited (cancelled=\(Task.isCancelled))")
            guard !Task.isCancelled else { return }
            guard let self else { return }
            await MainActor.run { self.handleArgusExit() }
        }
    }

    private func stopArgus() {
        argusReadTask?.cancel()
        argusReadTask = nil
        argusStdinPipe = nil
        if let proc = argusProcess {
            proc.terminate()
            argusProcess = nil
            isCapturing = false
        }
        stopArgusCaptureFeed()
    }

    /// Writes a fresh JPEG screenshot to a temp file every 5s so Argus can read it
    /// without needing Screen Recording permission on the Python process.
    private func startArgusCaptureFeed() {
        stopArgusCaptureFeed()
        argusCaptureFeedTask = Task { [weak self] in
            // Write first frame immediately so Argus has a capture available on startup
            if let self, let jpeg = await self.captureScreen() {
                try? jpeg.write(
                    to: URL(fileURLWithPath: self.argusCaptureFilePath),
                    options: .atomic
                )
            }
            while !Task.isCancelled {
                // 3s keeps the frame fresh enough that argus (which reads every 2.5s)
                // gets ~3 unique frames per 10s VLM call instead of just 2.
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled, let self else { break }
                if let jpeg = await self.captureScreen() {
                    try? jpeg.write(
                        to: URL(fileURLWithPath: self.argusCaptureFilePath),
                        options: .atomic
                    )
                }
            }
        }
    }

    private func stopArgusCaptureFeed() {
        argusCaptureFeedTask?.cancel()
        argusCaptureFeedTask = nil
        try? FileManager.default.removeItem(atPath: argusCaptureFilePath)
    }

    // MARK: - Argus Error Handling & Restart

    /// Called when the argus process exits unexpectedly. Retries up to 3 times with backoff.
    private func handleArgusExit() {
        isCapturing = false

        argusRestartCount += 1
        guard argusRestartCount <= 3 else {
            monitoringError = "Screen monitoring stopped after \(argusRestartCount - 1) restarts — tap Retry"
            return
        }

        let delay = TimeInterval(argusRestartCount * argusRestartCount)  // 1, 4, 9 s
        monitoringError = "Monitoring restarting… (attempt \(argusRestartCount) of 3)"

        let capturedSession = activeSession
        let capturedTask = activeTask
        let capturedDryRun = !isSessionActive   // dry-run when no active session

        Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self else { return }
            await MainActor.run {
                self.startArgus(session: capturedSession, task: capturedTask, dryRun: capturedDryRun)
            }
        }
    }

    /// Public — lets the HUD "Retry" button manually restart monitoring.
    func retryMonitoring() {
        monitoringError = nil
        argusRestartCount = 0
        let s = activeSession
        let t = activeTask
        startArgus(session: s, task: t, dryRun: !isSessionActive)
        if appSwitchObserver == nil { startAppObserver() }
    }

    // MARK: - Checkpoint Polling (live session mode)

    /// Polls GET /sessions/active every 15s and surfaces checkpoint data in the HUD.
    /// Argus posts VLM results directly to the backend; this is how Swift reads them back.
    private func startCheckpointPolling() {
        checkpointPollTask?.cancel()
        var lastSummary: String? = nil

        checkpointPollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled, let self else { break }

                guard let session = try? await APIClient.shared.getActiveSession(),
                      let checkpoint = session.checkpoint else { continue }

                await MainActor.run {
                    // vlmSummary coalesces last_vlm_summary (argus) and
                    // last_screenshot_analysis (Swift fallback) into one field.
                    if let summary = checkpoint.vlmSummary,
                       !summary.isEmpty, summary != lastSummary {
                        lastSummary = summary
                        self.latestVlmSummary = summary
                        if self.monitoringError != nil { self.monitoringError = nil }
                    }
                    // Mirror distraction count from backend
                    if let count = checkpoint.distractionCount {
                        self.distractionCount = count
                    }
                }
            }
        }
    }

    private func stopCheckpointPolling() {
        checkpointPollTask?.cancel()
        checkpointPollTask = nil
    }

    // MARK: - Screenshot Capture Loop (fallback when argus is unavailable)

    private func startCapture() {
        isCapturing = true
        captureTask = Task { [weak self] in
            guard let self else { return }
            // Capture immediately on session start, then repeat on interval
            await self.captureAndAnalyze()
            while !Task.isCancelled && self.isSessionActive {
                try? await Task.sleep(for: .seconds(self.captureInterval))
                guard !Task.isCancelled && self.isSessionActive else { break }
                await self.captureAndAnalyze()
            }
        }
    }

    private func stopCapture() {
        captureTask?.cancel()
        captureTask = nil
        isCapturing = false
    }

    private func captureAndAnalyze() async {
        guard let session = activeSession else { return }
        guard let imageData = await captureScreen() else { return }

        let windowTitle = NSWorkspace.shared.frontmostApplication?.localizedName ?? "Unknown"
        var context = buildTaskContext()

        // Inject rolling history so the VLM has temporal context across captures.
        // Only summaries (text) are sent — not the raw images — to keep token cost low.
        if !screenshotHistory.isEmpty {
            let iso = ISO8601DateFormatter()
            context["screenshot_history"] = screenshotHistory.map { entry in
                ["summary": entry.summary, "timestamp": iso.string(from: entry.timestamp)]
            }
        }

        do {
            let result = try await APIClient.shared.analyzeScreenshot(
                imageData: imageData,
                windowTitle: windowTitle,
                sessionId: session.id,
                taskContext: context
            )

            // Append this result's summary to the rolling buffer (max 4 entries)
            if let summary = result.vlmSummary {
                screenshotHistory.append(ScreenshotHistoryEntry(summary: summary, timestamp: Date()))
                if screenshotHistory.count > 4 { screenshotHistory.removeFirst() }
            }

            applyDistractionResult(result)
        } catch {
            // Silent fail — don't interrupt the user
        }
    }

    private func captureScreen() async -> Data? {
        // CGPreflightScreenCaptureAccess() checks TCC silently — no dialog, no picker.
        // Avoids re-prompting on every launch when permission is already granted.
        guard CGPreflightScreenCaptureAccess() else { return nil }
        do {
            let content = try await SCShareableContent.current
            guard let display = content.displays.first else { return nil }

            let config = SCStreamConfiguration()
            config.width = 1280
            config.height = 720

            let filter = SCContentFilter(display: display, excludingWindows: [])
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: config
            )
            return cgImageToJPEG(image)
        } catch {
            return nil
        }
    }

    private func cgImageToJPEG(_ image: CGImage) -> Data? {
        let nsImage = NSImage(cgImage: image, size: .zero)
        guard let tiff = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.5])
        else { return nil }
        return jpeg
    }

    private func buildTaskContext() -> [String: Any] {
        var ctx: [String: Any] = [:]
        guard let task = activeTask else { return ctx }
        ctx["task_title"] = task.title
        ctx["task_goal"] = task.description ?? task.title
        ctx["steps"] = activeSteps.map { step -> [String: Any] in
            var s: [String: Any] = [
                "id": step.id,
                "sort_order": step.sortOrder,
                "title": step.title,
                "status": step.status
            ]
            if let note = step.checkpointNote { s["checkpoint_note"] = note }
            return s
        }
        return ctx
    }

    private func applyDistractionResult(_ result: DistractionAnalysisResponse) {
        // 0. Store latest summary for the floating HUD
        if let summary = result.vlmSummary { latestVlmSummary = summary }

        // 1. Apply step side-effects (always)
        for completedId in result.stepsCompleted {
            if let idx = activeSteps.firstIndex(where: { $0.id == completedId }) {
                activeSteps[idx].status = "done"
            }
        }
        if let note = result.checkpointNoteUpdate,
           let stepId = result.currentStepId,
           let idx = activeSteps.firstIndex(where: { $0.id == stepId }) {
            activeSteps[idx].checkpointNote = note
        }
        if let stepId = result.currentStepId,
           let idx = activeSteps.firstIndex(where: { $0.id == stepId }) {
            currentStepIndex = idx
        }

        // 2. Notification priority (design spec §1.5):
        //    Proactive friction help → Context resume → Gentle nudge
        //    NEVER nudge when the system could help instead.
        if let friction = result.friction, friction.isActionable {
            if friction.isResumption {
                // Task resumption detected — auto-surface resume card without button press
                Task { await fetchResumeCard() }
            } else if proactiveCard == nil {
                showProactiveCard(ProactiveCard(source: .vlmFriction(
                    frictionType: friction.type,
                    description: friction.description,
                    actions: friction.proposedActions
                )), vlmCard: true)
            }
        } else if !result.onTask, result.confidence > 0.7, let nudge = result.gentleNudge {
            // Only nudge if VLM found no actionable friction
            distractionCount += 1
            lastNudge = nudge
            sendNudgeNotification(nudge)
        }
    }

    // MARK: - Notifications

    private func sendNudgeNotification(_ nudge: String) {
        let content = UNMutableNotificationContent()
        content.title = "Hey, quick check-in!"
        content.body = nudge
        content.sound = .default
        let req = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(req)
    }

    private func requestNotificationPermission() async {
        try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])
    }
}
