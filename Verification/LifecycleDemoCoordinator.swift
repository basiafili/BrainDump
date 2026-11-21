import Foundation
import Observation

/// Temporary checkpoint-1 demonstration fixture. Production workflows live in
/// BrainDumpCore/EditorCoordinator; this no-write demo is removed at checkpoint 5.
@MainActor
@Observable
final class LifecycleDemoCoordinator {
    private(set) var sessions: [UUID: LifecycleDemoSession] = [:]
    private(set) var activeEditorID: UUID?
    private(set) var mostRecentlyActiveEditorID: UUID?
    private(set) var isPreparingQuit = false
    private(set) var status = "Lifecycle demonstration only. Captures are not saved."
    private var activationOrder: [UUID] = []
    private let decisions: any LifecycleDecisionProviding

    init(decisions: any LifecycleDecisionProviding) {
        self.decisions = decisions
    }

    func createSession(projectName: String = "Lifecycle Demo") -> LifecycleDemoSession? {
        guard !isPreparingQuit else { return nil }
        let session = LifecycleDemoSession(projectName: projectName)
        sessions[session.id] = session
        return session
    }

    func activate(_ id: UUID) {
        guard sessions[id] != nil else { return }
        activeEditorID = id
        activationOrder.removeAll { $0 == id }
        activationOrder.append(id)
        mostRecentlyActiveEditorID = id
    }

    func deactivate(_ id: UUID) {
        if activeEditorID == id { activeEditorID = nil }
    }

    func windowDidClose(_ id: UUID) {
        sessions.removeValue(forKey: id)
        activationOrder.removeAll { $0 == id }
        deactivate(id)
        mostRecentlyActiveEditorID = activationOrder.last
    }

    func prepareClose(_ id: UUID) async -> Bool {
        guard !isPreparingQuit, let session = sessions[id], !session.isReadOnly else { return false }
        session.isReadOnly = true
        status = "Waiting for the simulated close decision."
        var closeAllowed = false
        defer {
            if !closeAllowed { session.isReadOnly = false }
        }
        do {
            let allowed = try await decisions.decide()
            try Task.checkCancellation()
            guard sessions[id] === session else { return false }
            closeAllowed = allowed
            status = allowed ? "Close allowed. No file was written." : "Close rejected. Capture remains open."
            return allowed
        } catch {
            status = "Close cancelled. Capture remains open."
            return false
        }
    }

    func prepareForAppQuit() async -> Bool {
        guard !isPreparingQuit, !sessions.values.contains(where: \.isReadOnly) else {
            status = "Finish the pending lifecycle operation before quitting."
            return false
        }
        isPreparingQuit = true
        let affectedSessions = Array(sessions.values)
        affectedSessions.forEach { $0.isReadOnly = true }
        var allowed = false
        defer {
            if !allowed {
                affectedSessions.forEach { $0.isReadOnly = false }
                isPreparingQuit = false
            }
        }
        status = "Waiting for the simulated quit decision. All captures remain open."
        do {
            allowed = try await decisions.decide()
            try Task.checkCancellation()
            status = allowed ? "Quit allowed. No file was written." : "Quit rejected. All captures remain open."
            return allowed
        } catch {
            allowed = false
            status = "Quit cancelled. All captures remain open."
            return false
        }
    }
}
