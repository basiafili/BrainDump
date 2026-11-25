import AppKit

/// Owns native adapters and callback tasks, never capture workflow logic.
@MainActor
final class WindowLifecycleRegistry {
    let coordinator: EditorCoordinator
    var onFailure: ((EditorWorkflowIssue) -> Void)?
    var recordsUsageForActivation: ((UUID) -> Bool)?
    private var adapters: [UUID: EditorWindowDelegate] = [:]
    private var closeTasks: [UUID: Task<Void, Never>] = [:]
    private var internalCloseDepth = 0

    init(coordinator: EditorCoordinator) {
        self.coordinator = coordinator
    }

    func attach(_ window: NSWindow, sessionID: UUID) {
        WindowAccessibility.configure(window)
        let identifier = "editor.\(sessionID.uuidString)"
        if window.accessibilityIdentifier() != identifier { window.setAccessibilityIdentifier(identifier) }
        window.isRestorable = false
        window.tabbingMode = .disallowed
        if window.toolbar?.displayMode != .iconAndLabel { window.toolbar?.displayMode = .iconAndLabel }
        if let adapter = adapters[sessionID], adapter.window === window { return }
        let adapter = EditorWindowDelegate(window: window, sessionID: sessionID, registry: self)
        adapters[sessionID] = adapter
        window.delegate = adapter
        if window.isKeyWindow { didBecomeKey(sessionID) }
    }

    func requestClose(_ sessionID: UUID) {
        guard closeTasks[sessionID] == nil, !coordinator.isPreparingQuit else { return }
        // Synchronous prefix and completion both access main-actor window/session state.
        closeTasks[sessionID] = Task { [weak self] in
            guard let self else { return }
            defer { self.closeTasks.removeValue(forKey: sessionID) }
            switch await self.coordinator.prepareClose(sessionID) {
            case .closeWindows(let ids):
                // close() bypasses windowShouldClose; performClose() asks again.
                self.closeAuthorizedWindows(ids)
            case .failed(let issue): self.onFailure?(issue)
            default: break
            }
        }
    }

    func activate(_ sessionID: UUID) { adapters[sessionID]?.window?.makeKeyAndOrderFront(nil) }

    /// Use only IDs granted by a completed coordinator transition.
    func closeAuthorizedWindows(_ ids: [UUID]) {
        internalCloseDepth += 1
        defer { internalCloseDepth -= 1 }
        for id in ids { adapters[id]?.window?.close() }
    }

    func didBecomeKey(_ sessionID: UUID) {
        coordinator.activate(sessionID, recordUsage: internalCloseDepth == 0 && (recordsUsageForActivation?(sessionID) ?? true))
    }

    func didClose(_ sessionID: UUID) {
        coordinator.windowDidClose(sessionID)
        adapters.removeValue(forKey: sessionID)
    }
}
