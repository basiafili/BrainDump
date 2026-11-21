import Foundation
import Observation

/// A folder choice belongs to one registration, never to whichever row happens
/// to be selected when the native picker returns or a confirmation completes.
@MainActor
@Observable
final class ProjectFolderDraft {
    nonisolated struct Choice: Identifiable, Equatable, Sendable {
        let id = UUID()
        let projectID: UUID
    }
    nonisolated struct Change: Equatable, Sendable {
        let projectID: UUID
        let folder: URL
    }

    private(set) var projectID: UUID?
    private(set) var pendingChoice: Choice?
    private(set) var change: Change?

    init(projectID: UUID?) { self.projectID = projectID }

    func select(_ id: UUID?) {
        guard id != projectID else { return }
        projectID = id
        pendingChoice = nil
        change = nil
    }

    func beginChoice() -> Choice? {
        guard let projectID else { return nil }
        let choice = Choice(projectID: projectID)
        pendingChoice = choice
        return choice
    }

    @discardableResult
    func accept(_ folder: URL, for choice: Choice) -> Bool {
        guard pendingChoice == choice, projectID == choice.projectID else { return false }
        change = Change(projectID: choice.projectID, folder: folder)
        pendingChoice = nil
        return true
    }

    func cancel(_ choice: Choice) {
        if pendingChoice == choice { pendingChoice = nil }
    }

    func clear() { pendingChoice = nil; change = nil }
}
