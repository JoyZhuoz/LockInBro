// LockInBroApp.swift — App entry point with menu bar + main window

import SwiftUI

// MARK: - AppDelegate (subprocess cleanup on quit)

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Called for normal quits (Cmd+Q), window close, and SIGTERM.
    /// Ensures the argus subprocess is killed before the process exits.
    func applicationWillTerminate(_ notification: Notification) {
        // applicationWillTerminate runs on the main thread, so we can safely
        // call @MainActor methods synchronously via assumeIsolated.
        MainActor.assumeIsolated {
            SessionManager.shared.stopMonitoring()
        }
    }
}

@main
struct LockInBroApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @State private var auth = AuthManager.shared
    @State private var session = SessionManager.shared

    var body: some Scene {
        // Main window
        WindowGroup("LockInBro") {
            ContentView()
                .environment(auth)
                .environment(session)
                .onChange(of: auth.isLoggedIn, initial: true) { _, loggedIn in
                    if loggedIn {
                        // Show HUD and start always-on monitoring as soon as user logs in
                        FloatingPanelController.shared.show(session: session)
                        Task { await session.startMonitoring() }
                    } else {
                        FloatingPanelController.shared.close()
                    }
                }
        }
        .defaultSize(width: 840, height: 580)

        // Menu bar extra
        MenuBarExtra {
            MenuBarView()
                .environment(auth)
                .environment(session)
        } label: {
            // Show a filled icon when a session is active
            if session.isSessionActive {
                Image(systemName: "brain.head.profile")
                    .symbolEffect(.pulse)
            } else {
                Image(systemName: "brain.head.profile")
            }
        }
        .menuBarExtraStyle(.window)
    }
}
