import Foundation
import Observation

/// Settings presentation state without native windows or filesystem operations.
/// Each metadata commit and required capture save belongs to the coordinator.
@MainActor
@Observable
final class ProjectSettingsController {
    nonisolated enum Activity { case checkingFolder, applyingChanges, removingProject }
    nonisolated struct Decision: Identifiable, Sendable {
        let id = UUID()
        let change: ProjectSettingsChange
        let projectName: String
    }

    private(set) var selectedID: UUID?
    private(set) var drafts: [UUID: ProjectSettingsDraft] = [:]
    private(set) var activity: Activity?
    var isWorking: Bool { activity != nil }
    private(set) var decision: Decision?
    private(set) var removal: ProjectRecord?
    private(set) var requestsClose = false
    private(set) var closeIDs: [UUID] = []
    private(set) var appliedIDs: [UUID] = []
    var error: String?
    var blockedIssue: EditorWorkflowIssue?
    @ObservationIgnored private let projects: ProjectStore
    @ObservationIgnored private let coordinator: EditorCoordinator
    @ObservationIgnored private let onCloseAuthorized: (@MainActor ([UUID]) -> Void)?
    @ObservationIgnored private let onApplied: (@MainActor (UUID) -> Void)?
    @ObservationIgnored private var queue: [UUID] = []
    @ObservationIgnored private var closeAfterQueue = false
    @ObservationIgnored private var cancelledDraft = false

    init(projects: ProjectStore, coordinator: EditorCoordinator, selectedID: UUID?,
         onCloseAuthorized: (@MainActor ([UUID]) -> Void)? = nil, onApplied: (@MainActor (UUID) -> Void)? = nil) {
        self.projects = projects
        self.coordinator = coordinator
        self.selectedID = selectedID
        self.onCloseAuthorized = onCloseAuthorized
        self.onApplied = onApplied
        if let selectedID { _ = draft(for: selectedID) }
    }

    var selectedDraft: ProjectSettingsDraft? { selectedID.flatMap { drafts[$0] } }
    var isBusy: Bool { isWorking || decision != nil || removal != nil }
    var hasInvalidDrafts: Bool { drafts.values.contains { !$0.inputProblems(projects: projects).isEmpty } }
    var canOK: Bool { !isBusy && !hasInvalidDrafts && !coordinator.isPreparingQuit }

    func draft(for id: UUID) -> ProjectSettingsDraft? {
        if let value = drafts[id] { return value }
        guard let project = projects.projects.first(where: { $0.id == id }) else { return nil }
        let value = ProjectSettingsDraft(project: project)
        drafts[id] = value
        return value
    }

    func problems(for id: UUID) -> [String] {
        guard let draft = drafts[id] else { return [] }
        return draft.inputProblems(projects: projects) + (draft.commitError.map { [$0] } ?? [])
    }

    func select(_ id: UUID?) async {
        guard !isBusy, !requestsClose, id != selectedID else { return }
        let previous = selectedID
        selectedID = id
        if let id { _ = draft(for: id) }
        error = nil
        guard let previous, let old = drafts[previous], old.hasChanges,
              old.inputProblems(projects: projects).isEmpty else { return }
        queue = [previous]
        closeAfterQueue = false
        cancelledDraft = false
        await drain()
    }

    func beginFolderChoice() -> ProjectFolderDraft.Choice? {
        guard !isBusy else { return nil }
        return selectedDraft?.folderChoice.beginChoice()
    }

    func acceptFolder(_ url: URL, choice: ProjectFolderDraft.Choice) async {
        guard !isBusy else { return }
        guard let draft = drafts[choice.projectID], draft.beginValidation(url, choice: choice) else {
            error = String(localized: "The folder choice is no longer current. Choose the folder again.")
            return
        }
        activity = .checkingFolder
        defer { activity = nil }
        do {
            let folder = try await projects.authorizeReplacementFolder(choice.projectID, selectedFolder: url)
            draft.finishValidation(.success(folder), choice: choice)
        } catch { draft.finishValidation(.failure(error), choice: choice) }
    }

    func cancelFolderChoice(_ choice: ProjectFolderDraft.Choice) { drafts[choice.projectID]?.folderChoice.cancel(choice) }

    func ok() async {
        guard canOK else { return }
        queue = projects.projects.map(\.id).filter { drafts[$0]?.hasChanges == true }
        closeAfterQueue = true
        cancelledDraft = false
        error = nil
        await drain()
    }

    func cancel() {
        guard !isBusy else { return }
        drafts.removeAll() // Earlier row commits are deliberately not rolled back.
        requestsClose = true
    }

    func resolveDecision(_ mode: EditorFolderChangeMode?) async {
        guard let decision, !isWorking else { return }
        self.decision = nil
        if let mode {
            if !(await apply(decision.change, mode: mode)) { stopQueue(); return }
        } else { cancelledDraft = true }
        await drain()
    }

    func requestRemoval() {
        guard !isBusy, let selectedID else { return }
        removal = projects.projects.first { $0.id == selectedID } // Never use draft name/folder.
    }

    func cancelRemoval() { removal = nil }

    func confirmRemoval() async {
        guard let removal, !isWorking else { return }
        self.removal = nil
        activity = .removingProject
        defer { activity = nil }
        let result = await coordinator.removeProject(removal.id)
        switch result {
        case .completed, .closeWindows:
            drafts.removeValue(forKey: removal.id)
            if selectedID == removal.id { selectedID = nil }
            publishApplied(removal.id)
            if case .closeWindows(let ids) = result { publishClose(ids) }
            error = nil
        case .failed(let issue): recordFailure(issue, projectID: removal.id, name: removal.name)
        case .busy: error = EditorWorkflowError.busy.localizedDescription
        default: break
        }
    }

    func takeCloseIDs() -> [UUID] { defer { closeIDs.removeAll() }; return closeIDs }
    func takeAppliedIDs() -> [UUID] { defer { appliedIDs.removeAll() }; return appliedIDs }

    private func drain() async {
        while !queue.isEmpty {
            let id = queue.removeFirst()
            guard let draft = drafts[id], draft.hasChanges else { continue }
            guard draft.inputProblems(projects: projects).isEmpty else { cancelledDraft = true; continue }
            let change = draft.snapshot()
            let folderChangesDestination = change.folder.map {
                $0.path != draft.original.folder.path || $0.identity != draft.original.folder.identity
            } ?? false
            if folderChangesDestination && coordinator.sessions.values.contains(where: { $0.project.id == id && $0.isUnsaved }) {
                decision = Decision(change: change, projectName: draft.original.name)
                return
            }
            if !(await apply(change, mode: .keepOpen)) { stopQueue(); return }
        }
        if closeAfterQueue && !cancelledDraft && !drafts.values.contains(where: \.hasChanges) && !hasInvalidDrafts {
            requestsClose = true
        }
        closeAfterQueue = false
    }

    private func apply(_ change: ProjectSettingsChange, mode: EditorFolderChangeMode) async -> Bool {
        activity = .applyingChanges
        defer { activity = nil }
        let result = await coordinator.applyProjectSettings(change, mode: mode)
        switch result {
        case .completed, .closeWindows:
            if let current = projects.projects.first(where: { $0.id == change.projectID }) {
                drafts[change.projectID]?.didCommit(current, snapshot: change)
            }
            publishApplied(change.projectID)
            if case .closeWindows(let ids) = result { publishClose(ids) }
            return true
        case .failed(let issue):
            let name = projects.projects.first(where: { $0.id == change.projectID })?.name ?? change.name
            recordFailure(issue, projectID: change.projectID, name: name)
        case .busy: error = EditorWorkflowError.busy.localizedDescription
        default: break
        }
        return false
    }

    private func recordFailure(_ issue: EditorWorkflowIssue, projectID: UUID, name: String) {
        let message = String(localized: "Could not apply changes for “\(name)”. \(issue.message)")
        drafts[projectID]?.commitError = message
        if issue.kind == .save { blockedIssue = issue }
        else { error = message }
    }

    private func stopQueue() { queue.removeAll(); closeAfterQueue = false }

    private func publishClose(_ ids: [UUID]) {
        if let onCloseAuthorized { onCloseAuthorized(ids) }
        else { closeIDs.append(contentsOf: ids) }
    }

    private func publishApplied(_ id: UUID) {
        if let onApplied { onApplied(id) }
        else { appliedIDs.append(id) }
    }
}
