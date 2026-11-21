import Foundation
import Observation

/// One production workflow authority; no AppKit/SwiftUI objects or filesystem I/O.
@MainActor
@Observable
final class EditorCoordinator {
    private(set) var sessions: [UUID: EditorSession] = [:]
    private(set) var activeEditorID: UUID?
    private(set) var mostRecentlyActiveEditorID: UUID?
    private(set) var isPreparingQuit = false
    private(set) var isCreatingProject = false
    private(set) var lastIssue: EditorWorkflowIssue?
    @ObservationIgnored private let projects: ProjectStore
    @ObservationIgnored private let writer: any CaptureWriting
    @ObservationIgnored private var creationOrder: [UUID] = []
    @ObservationIgnored private var activationOrder: [UUID] = []
    @ObservationIgnored private var saveTails: [UUID: SaveJob] = [:]
    private var projectOperations: Set<UUID> = []
    @ObservationIgnored private var closingSessionIDs: Set<UUID> = []
    @ObservationIgnored private var projectClosures: [UUID: Set<UUID>] = [:]
    @ObservationIgnored private var quitAuthorized = false

    private struct SaveJob {
        let id: UUID
        let task: Task<EditorSaveOutcome, Never>
    }
    private struct SaveSnapshot {
        let captureID: UUID
        let text: String
        let projectFolder: AuthorizedFolder
    }

    init(projects: ProjectStore, writer: any CaptureWriting) {
        self.projects = projects
        self.writer = writer
    }

    func registerWindow(for projectID: UUID, recordUsage: Bool = true) async throws -> EditorSession {
        guard !isPreparingQuit, !projectOperations.contains(projectID) else { throw EditorWorkflowError.busy }
        let project = try await projects.revalidate(projectID)
        try Task.checkCancellation()
        guard !isPreparingQuit, !projectOperations.contains(projectID) else { throw EditorWorkflowError.busy }
        let session = EditorSession(project: project)
        if recordUsage { try projects.recordOpened(projectID) }
        sessions[session.id] = session
        creationOrder.append(session.id)
        return session
    }

    func createProject(name: String, selectedFolder: URL, expectedFolder: AuthorizedFolder? = nil, reusing sessionID: UUID?,
                       folderPreparer: any ProjectFolderPreparing) async -> ProjectCreationOutcome {
        guard !isPreparingQuit, !isCreatingProject else { return .busy }
        let session = sessionID.flatMap { sessions[$0] }
        let token: UUID?
        if let session {
            guard let acquired = beginTransition(session) else { return .busy }
            token = acquired
        } else { token = nil }
        isCreatingProject = true
        let captureID = session?.captureID
        defer {
            if let session, let token { session.endTransition(token) }
            isCreatingProject = false
        }
        do {
            let draft = try await projects.prepareRegistration(name: name, selectedFolder: selectedFolder)
            if let expectedFolder {
                guard draft.folder.path == expectedFolder.path, draft.folder.identity == expectedFolder.identity else {
                    throw ProjectError.selectionChanged
                }
            }
            if let session, let failed = await enqueueSave(session).transitionFailure {
                switch failed {
                case .failed(let issue): return .failed(issue)
                case .cancelled: return .cancelled
                default: throw EditorWorkflowError.captureChanged
                }
            }
            try Task.checkCancellation()
            try await folderPreparer.ensureCurrentMonthFolder(in: draft.folder)
            let project = try await projects.revalidateRegistration(draft)
            try Task.checkCancellation()
            if let session, let captureID {
                guard isCurrent(session, captureID: captureID) else { throw EditorWorkflowError.captureChanged }
            }
            // No await between the single registry/usage commit and session state.
            try projects.commitRegistration(project, opened: true)
            if let session {
                session.resetCapture(project: project)
                return .opened(session.id)
            }
            let created = EditorSession(project: project)
            sessions[created.id] = created
            creationOrder.append(created.id)
            return .opened(created.id)
        } catch {
            if error is CancellationError { return .cancelled }
            let issue = EditorWorkflowIssue(kind: .project, sessionID: session?.id, message: error.localizedDescription)
            lastIssue = issue
            return .failed(issue)
        }
    }

    /// Native activation during a coordinated bulk close must not guess a new
    /// persisted last-active project. Explicit typing/click activation may do so.
    func activate(_ id: UUID, userInitiated: Bool = false, recordUsage: Bool = true) {
        guard !isPreparingQuit, !closingSessionIDs.contains(id), let session = sessions[id] else { return }
        activeEditorID = id
        activationOrder.removeAll { $0 == id }
        activationOrder.append(id)
        mostRecentlyActiveEditorID = id
        guard recordUsage else { return }
        guard closingSessionIDs.isEmpty || userInitiated else { return }
        guard projects.lastActiveID != session.project.id else { return }
        do { try projects.recordEditorActivated(session.project.id) }
        catch { _ = failure(error, sessionID: id, kind: .project) }
    }

    func deactivate(_ id: UUID) { if activeEditorID == id { activeEditorID = nil } }

    @discardableResult
    func updateText(_ id: UUID, text: String) -> Bool {
        guard let session = sessions[id], !session.isReadOnly else { return false }
        guard session.text != text else { return true }
        session.acceptText(text)
        activate(id, userInitiated: true)
        return true
    }

    func dismissIssue(_ id: UUID) { if lastIssue?.id == id { lastIssue = nil } }

    /// Observable query for shared command/form enabled state across windows.
    func isProjectBusy(_ projectID: UUID) -> Bool { projectOperations.contains(projectID) }

    func save(_ id: UUID) async -> EditorSaveOutcome {
        guard let session = sessions[id] else { return .missingSession }
        guard !isPreparingQuit, !session.isReadOnly else { return .busy }
        return await enqueueSave(session)
    }

    func newCapture(_ id: UUID) async -> EditorOperationOutcome {
        guard let session = sessions[id] else { return .missingSession }
        guard let token = beginTransition(session) else { return .busy }
        defer { session.endTransition(token) }
        let captureID = session.captureID
        if let failed = await enqueueSave(session).transitionFailure { return failed }
        if Task.isCancelled { return .cancelled }
        guard isCurrent(session, captureID: captureID) else { return .missingSession }
        session.resetCapture()
        return .completed
    }

    func prepareClose(_ id: UUID) async -> EditorOperationOutcome {
        guard let session = sessions[id] else { return .missingSession }
        guard let token = beginTransition(session) else { return .busy }
        var allowed = false
        defer { if !allowed { session.endTransition(token) } }
        let captureID = session.captureID
        if let failed = await enqueueSave(session).transitionFailure { return failed }
        if Task.isCancelled { return .cancelled }
        guard isCurrent(session, captureID: captureID) else { return .missingSession }
        closingSessionIDs.insert(id)
        allowed = true
        return .closeWindows([id])
    }

    func switchProject(_ id: UUID, to projectID: UUID) async -> EditorOperationOutcome {
        guard let session = sessions[id] else { return .missingSession }
        guard !projectOperations.contains(projectID), let token = beginTransition(session) else { return .busy }
        defer { session.endTransition(token) }
        let captureID = session.captureID
        do {
            _ = try await projects.revalidate(projectID)
            if let failed = await enqueueSave(session).transitionFailure { return failed }
            try Task.checkCancellation()
            // Access/name/path could have changed while the old capture saved.
            let target = try await projects.revalidate(projectID)
            try Task.checkCancellation()
            guard isCurrent(session, captureID: captureID) else { return .missingSession }
            guard !projectOperations.contains(projectID) else { return .busy }
            try projects.recordOpened(projectID)
            session.resetCapture(project: target)
            return .completed
        } catch { return failure(error, sessionID: id, kind: .project) }
    }

    func prepareForAppQuit() async -> EditorOperationOutcome {
        guard !isPreparingQuit, !isCreatingProject, projectOperations.isEmpty,
              !sessions.values.contains(where: \.isReadOnly) else { return .busy }
        isPreparingQuit = true
        let token = UUID()
        let affected = orderedSessions()
        let captures = affected.map(\.captureID)
        affected.forEach { $0.beginTransition(token) }
        var allowed = false
        defer {
            if !allowed {
                affected.forEach { $0.endTransition(token) }
                isPreparingQuit = false
            }
        }
        for (index, session) in affected.enumerated() {
            guard isCurrent(session, captureID: captures[index]) else {
                return failure(EditorWorkflowError.captureChanged, kind: .state)
            }
            if let failed = await enqueueSave(session).transitionFailure { return failed }
            if Task.isCancelled { return .cancelled }
            guard isCurrent(session, captureID: captures[index]) else {
                return failure(EditorWorkflowError.captureChanged, kind: .state)
            }
        }
        guard zip(affected, captures).allSatisfy({ isCurrent($0.0, captureID: $0.1) }) else {
            return failure(EditorWorkflowError.captureChanged, kind: .state)
        }
        quitAuthorized = true
        allowed = true
        return .closeWindows(affected.map(\.id))
    }

    /// The UI must obtain removal confirmation before calling this method.
    func removeProject(_ projectID: UUID) async -> EditorOperationOutcome {
        await applyProjectChange(projectID, change: .remove)
    }

    /// The UI obtains the unsaved-capture decision; Cancel means do not call.
    func changeProjectFolder(_ projectID: UUID, selectedFolder: URL, mode: EditorFolderChangeMode) async -> EditorOperationOutcome {
        await applyProjectChange(projectID, change: .folder(selectedFolder, mode))
    }

    func applyProjectSettings(_ change: ProjectSettingsChange, mode: EditorFolderChangeMode) async -> EditorOperationOutcome {
        await applyProjectChange(change.projectID, change: .settings(change, mode))
    }

    func renameProject(_ projectID: UUID, to name: String) -> EditorOperationOutcome {
        guard !isPreparingQuit, !projectOperations.contains(projectID) else { return .busy }
        do {
            try projects.rename(projectID, to: name)
            updateSessionProjects(projectID)
            return .completed
        } catch { return failure(error, kind: .project) }
    }

    /// A disappearing SwiftUI view is not permission to discard its session.
    @discardableResult
    func windowDidClose(_ id: UUID) -> Bool {
        guard let session = sessions[id] else { return false }
        guard closingSessionIDs.contains(id) || quitAuthorized else {
            _ = failure(EditorWorkflowError.unexpectedClose, sessionID: id, kind: .state)
            return false
        }
        sessions.removeValue(forKey: id)
        creationOrder.removeAll { $0 == id }
        activationOrder.removeAll { $0 == id }
        if activeEditorID == id { activeEditorID = nil }
        mostRecentlyActiveEditorID = activationOrder.last
        closingSessionIDs.remove(id)
        let projectID = session.project.id
        if projectClosures[projectID] != nil {
            projectClosures[projectID]?.remove(id)
            if projectClosures[projectID]?.isEmpty == true {
                projectClosures.removeValue(forKey: projectID)
                projectOperations.remove(projectID)
            }
        }
        return true
    }

    private func beginTransition(_ session: EditorSession) -> UUID? {
        guard !isPreparingQuit, !session.isReadOnly, !projectOperations.contains(session.project.id) else { return nil }
        let token = UUID()
        session.beginTransition(token)
        return token
    }

    private func isCurrent(_ session: EditorSession, captureID: UUID) -> Bool {
        sessions[session.id] === session && session.captureID == captureID
    }

    /// Each command freezes its text immediately, but resolves the binding only
    /// when its FIFO turn starts, after adopting the predecessor's successful receipt.
    private func enqueueSave(_ session: EditorSession) async -> EditorSaveOutcome {
        let snapshot = SaveSnapshot(captureID: session.captureID, text: session.text, projectFolder: session.project.folder)
        let previous = saveTails[session.id]?.task
        let jobID = UUID()
        session.enqueueSave()
        // Finite tasks are owned by saveTails/the awaiting caller; cancellation of
        // one command cancels only its own job, never the preceding writer.
        let job = Task { @MainActor in
            defer { session.finishSave() }
            guard self.isCurrent(session, captureID: snapshot.captureID) else { return EditorSaveOutcome.missingSession }
            if let previous { _ = await previous.value }
            guard self.isCurrent(session, captureID: snapshot.captureID) else { return .missingSession }
            do {
                try Task.checkCancellation()
                let request = CaptureWriteRequest(text: snapshot.text, projectFolder: snapshot.projectFolder, binding: session.binding)
                guard !request.isEmpty else { return .empty }
                let receipt = try await self.writer.save(request)
                // A writer may have committed despite caller cancellation. Adopt
                // that receipt before deciding whether a transition should abort.
                guard case .saved(let binding) = receipt, binding.baseline == Data(snapshot.text.utf8) else {
                    return self.saveFailure(EditorWorkflowError.invalidSaveReceipt, session: session, captureID: snapshot.captureID)
                }
                if self.isCurrent(session, captureID: snapshot.captureID) { session.recordSaved(binding) }
                return .saved(binding)
            } catch { return self.saveFailure(error, session: session, captureID: snapshot.captureID) }
        }
        saveTails[session.id] = SaveJob(id: jobID, task: job)
        let outcome = await withTaskCancellationHandler {
            await job.value
        } onCancel: { job.cancel() }
        if saveTails[session.id]?.id == jobID { saveTails.removeValue(forKey: session.id) }
        return outcome
    }

    private func saveFailure(_ error: any Error, session: EditorSession, captureID: UUID) -> EditorSaveOutcome {
        if error is CancellationError { return .cancelled }
        let issue = EditorWorkflowIssue(kind: .save, sessionID: session.id, message: error.localizedDescription)
        if isCurrent(session, captureID: captureID) {
            lastIssue = issue
            session.recordIssue(issue)
        }
        return .failed(issue)
    }

    private func failure(_ error: any Error, sessionID: UUID? = nil, kind: EditorWorkflowIssue.Kind) -> EditorOperationOutcome {
        if error is CancellationError { return .cancelled }
        let issue = EditorWorkflowIssue(kind: kind, sessionID: sessionID, message: error.localizedDescription)
        lastIssue = issue
        if let sessionID { sessions[sessionID]?.recordIssue(issue) }
        return .failed(issue)
    }

    private func orderedSessions(projectID: UUID? = nil) -> [EditorSession] {
        creationOrder.compactMap { sessions[$0] }.filter { projectID == nil || $0.project.id == projectID }
    }

    private func updateSessionProjects(_ projectID: UUID) {
        guard let project = projects.projects.first(where: { $0.id == projectID }) else { return }
        for session in sessions.values where session.project.id == projectID { session.updateProject(project) }
    }

    private enum ProjectChange {
        case remove
        case folder(URL, EditorFolderChangeMode)
        case settings(ProjectSettingsChange, EditorFolderChangeMode)
        var closesCaptures: Bool {
            switch self {
            case .remove, .folder(_, .saveAndClose): true
            case .folder(_, .keepOpen): false
            case .settings(let change, .saveAndClose): change.folder != nil
            case .settings(_, .keepOpen): false
            }
        }
        var changesFolder: Bool {
            switch self {
            case .folder: true
            case .settings(let change, _): change.folder != nil
            case .remove: false
            }
        }
    }

    private func applyProjectChange(_ projectID: UUID, change: ProjectChange) async -> EditorOperationOutcome {
        guard !isPreparingQuit, !projectOperations.contains(projectID) else { return .busy }
        guard let original = projects.projects.first(where: { $0.id == projectID }) else {
            return failure(ProjectError.missingProject, kind: .project)
        }
        let affected = orderedSessions(projectID: projectID)
        let captures = affected.map(\.captureID)
        guard !affected.contains(where: \.isReadOnly) else { return .busy }
        projectOperations.insert(projectID)
        let token = UUID()
        if change.closesCaptures { affected.forEach { $0.beginTransition(token) } }
        var closing = false
        defer {
            if !closing {
                affected.forEach { $0.endTransition(token) }
                projectOperations.remove(projectID)
            }
        }
        do {
            let prepared: PreparedProjectSettingsChange?
            if case .settings(let settings, _) = change { prepared = try await projects.prepareSettingsChange(settings) }
            else { prepared = nil }
            if change.changesFolder && !change.closesCaptures {
                // Finish already-accepted manual saves without starting another
                // save or cancelling them. A pending first save becomes bound to
                // its old destination before unbound captures are redirected.
                for (index, session) in affected.enumerated() {
                    if let pending = saveTails[session.id]?.task { _ = await pending.value }
                    try Task.checkCancellation()
                    guard isCurrent(session, captureID: captures[index]) else {
                        return failure(EditorWorkflowError.captureChanged, kind: .state)
                    }
                }
            }
            if change.closesCaptures {
                for (index, session) in affected.enumerated() {
                    guard isCurrent(session, captureID: captures[index]) else {
                        return failure(EditorWorkflowError.captureChanged, kind: .state)
                    }
                    if let failed = await enqueueSave(session).transitionFailure { return failed }
                    if Task.isCancelled { return .cancelled }
                    guard isCurrent(session, captureID: captures[index]) else {
                        return failure(EditorWorkflowError.captureChanged, kind: .state)
                    }
                }
                guard zip(affected, captures).allSatisfy({ isCurrent($0.0, captureID: $0.1) }) else {
                    return failure(EditorWorkflowError.captureChanged, kind: .state)
                }
            }
            try Task.checkCancellation()
            if prepared == nil {
                guard projects.projects.first(where: { $0.id == projectID }) == original else { throw EditorWorkflowError.projectChanged }
            }
            switch change {
            case .remove: try projects.remove(projectID)
            case .folder(let url, _): try await projects.changeFolder(projectID, selectedFolder: url)
            case .settings:
                guard let prepared else { throw EditorWorkflowError.projectChanged }
                let final = try await projects.revalidateSettingsChange(prepared)
                try Task.checkCancellation()
                try projects.commitSettingsChange(final)
            }
            // No cancellation check after a registry commit. Reflect committed
            // metadata and return the corresponding close permission coherently.
            updateSessionProjects(projectID)
            if change.closesCaptures {
                let ids = affected.map(\.id)
                closingSessionIDs.formUnion(ids)
                if !ids.isEmpty {
                    projectClosures[projectID] = Set(ids)
                    closing = true
                }
                return .closeWindows(ids)
            }
            return .completed
        } catch { return failure(error, kind: .project) }
    }
}
