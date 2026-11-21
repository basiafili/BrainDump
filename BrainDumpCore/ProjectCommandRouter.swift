import Foundation

nonisolated struct ProjectOpenRequest: Sendable {
    let projectID: UUID
    let originatingEditorID: UUID?
    let inNewWindow: Bool
}

nonisolated enum ProjectPresentationOutcome: Equatable, Sendable {
    case opened(UUID), reused(UUID), failed(EditorWorkflowIssue), busy, cancelled
}

/// Resolves presentation intent once, before the coordinator begins awaiting.
/// Saving and switching remain exclusively in EditorCoordinator.
@MainActor
final class ProjectCommandRouter {
    private let projects: ProjectStore
    private let coordinator: EditorCoordinator

    init(projects: ProjectStore, coordinator: EditorCoordinator) {
        self.projects = projects
        self.coordinator = coordinator
    }

    var targetEditorID: UUID? {
        if let id = coordinator.activeEditorID, coordinator.sessions[id] != nil { return id }
        if let id = coordinator.mostRecentlyActiveEditorID, coordinator.sessions[id] != nil { return id }
        return nil
    }

    func targetEditorID(retaining origin: UUID?) -> UUID? {
        if let origin, coordinator.sessions[origin] != nil { return origin }
        return targetEditorID
    }

    func canUseEditor(_ id: UUID) -> Bool {
        guard !coordinator.isPreparingQuit, let session = coordinator.sessions[id] else { return false }
        return !session.isReadOnly && !coordinator.isProjectBusy(session.project.id)
    }

    var canNewCapture: Bool {
        guard !coordinator.isPreparingQuit else { return false }
        return targetEditorID.map(canUseEditor) ?? true
    }

    var canSave: Bool { targetEditorID.map(canUseEditor) ?? false }

    func canOpen(_ projectID: UUID, inNewWindow: Bool, origin: UUID? = nil) -> Bool {
        guard !coordinator.isPreparingQuit, !coordinator.isProjectBusy(projectID),
              projects.reachableProjects.contains(where: { $0.id == projectID }) else { return false }
        guard !inNewWindow, let target = targetEditorID(retaining: origin) else { return true }
        return canUseEditor(target)
    }

    func menuRequest(for projectID: UUID) -> ProjectOpenRequest {
        ProjectOpenRequest(projectID: projectID, originatingEditorID: targetEditorID,
                           inNewWindow: projects.alwaysOpenInNewWindow)
    }

    func open(_ request: ProjectOpenRequest) async -> ProjectPresentationOutcome {
        guard !coordinator.isPreparingQuit else { return .busy }
        let target = targetEditorID(retaining: request.originatingEditorID)
        if !request.inNewWindow, let target {
            switch await coordinator.switchProject(target, to: request.projectID) {
            case .completed: return .reused(target)
            case .failed(let issue): return .failed(issue)
            case .cancelled: return .cancelled
            default: return .busy
            }
        }
        do {
            let session = try await coordinator.registerWindow(for: request.projectID)
            return .opened(session.id)
        } catch {
            if error is CancellationError { return .cancelled }
            if let workflowError = error as? EditorWorkflowError, case .busy = workflowError { return .busy }
            return .failed(EditorWorkflowIssue(kind: .project, sessionID: target, message: error.localizedDescription))
        }
    }
}
