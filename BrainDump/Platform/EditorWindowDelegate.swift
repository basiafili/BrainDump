import AppKit

/// Interposes close/activation callbacks and preserves SwiftUI’s standard window notifications.
@MainActor
final class EditorWindowDelegate: NSObject, NSWindowDelegate {
    weak var window: NSWindow?
    private weak var originalDelegate: (any NSWindowDelegate)?
    private weak var registry: WindowLifecycleRegistry?
    private let sessionID: UUID

    init(window: NSWindow, sessionID: UUID, registry: WindowLifecycleRegistry) {
        self.window = window
        self.originalDelegate = window.delegate
        self.registry = registry
        self.sessionID = sessionID
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        registry?.requestClose(sessionID)
        return false
    }

    func windowWillClose(_ notification: Notification) {
        // Keep the adapter alive until the original delegate has observed closure.
        originalDelegate?.windowWillClose?(notification)
        registry?.didClose(sessionID)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        registry?.didBecomeKey(sessionID)
        originalDelegate?.windowDidBecomeKey?(notification)
    }

    func windowDidResignKey(_ notification: Notification) {
        registry?.coordinator.deactivate(sessionID)
        originalDelegate?.windowDidResignKey?(notification)
    }

    func windowDidResize(_ notification: Notification) {
        originalDelegate?.windowDidResize?(notification)
    }

    func windowDidMove(_ notification: Notification) {
        originalDelegate?.windowDidMove?(notification)
    }

    func windowDidBecomeMain(_ notification: Notification) {
        originalDelegate?.windowDidBecomeMain?(notification)
    }

    func windowDidResignMain(_ notification: Notification) {
        originalDelegate?.windowDidResignMain?(notification)
    }

    func windowWillStartLiveResize(_ notification: Notification) {
        originalDelegate?.windowWillStartLiveResize?(notification)
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        originalDelegate?.windowDidEndLiveResize?(notification)
    }

    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
        if let text = window.firstResponder as? CaptureTextEditor.CaptureTextView { return text.undoManager }
        return originalDelegate?.windowWillReturnUndoManager?(window)
    }
}
