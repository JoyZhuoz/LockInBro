// FloatingPanel.swift — Always-on-top NSPanel that hosts the floating HUD

import AppKit
import SwiftUI

// MARK: - Panel subclass

final class FloatingPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 140),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        // Always float above other windows, including full-screen apps
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        // Drag anywhere on the panel body
        isMovableByWindowBackground = true
        isMovable = true

        // Hide the standard title bar chrome
        titleVisibility = .hidden
        titlebarAppearsTransparent = true

        // Transparent background so the SwiftUI material shows through
        backgroundColor = .clear
        isOpaque = false

        // Don't activate the app when clicked (user keeps focus on their work)
        becomesKeyOnlyIfNeeded = true
    }
}

// MARK: - Controller

@MainActor
final class FloatingPanelController {
    static let shared = FloatingPanelController()

    private var panel: FloatingPanel?

    private init() {}

    func show(session: SessionManager) {
        if panel == nil {
            let p = FloatingPanel()
            let hud = FloatingHUDView()
                .environment(session)
            p.contentView = NSHostingView(rootView: hud)

            // Position: top-right of the main screen, just below the menu bar
            if let screen = NSScreen.main {
                let margin: CGFloat = 16
                let x = screen.visibleFrame.maxX - 320 - margin
                let y = screen.visibleFrame.maxY - 160 - margin
                p.setFrameOrigin(NSPoint(x: x, y: y))
            } else {
                p.center()
            }

            panel = p
        }
        panel?.orderFront(nil)
    }

    func hide() {
        panel?.orderOut(nil)
    }

    /// Call when the session fully ends to release the panel
    func close() {
        panel?.close()
        panel = nil
    }
}
