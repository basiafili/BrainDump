import Foundation

/// Keep the original folder authorization when project registration changes.
/// A new binding is returned only after a successful publication, never on failure.
nonisolated struct CaptureBinding: Equatable, Sendable {
    let folder: AuthorizedFolder
    let fileURL: URL
    let firstSavedAt: Date
    let baseline: Data
}

nonisolated struct CaptureWriteRequest: Sendable {
    let text: String
    let projectFolder: AuthorizedFolder
    let binding: CaptureBinding?

    var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

nonisolated enum CaptureWriteOutcome: Equatable, Sendable {
    /// Includes a cleared bound capture: keep its old binding/baseline unchanged.
    case empty
    case saved(CaptureBinding)
}

nonisolated protocol CaptureWriting: Sendable {
    func save(_ request: CaptureWriteRequest) async throws -> CaptureWriteOutcome
}

nonisolated protocol ProjectFolderPreparing: Sendable {
    func ensureCurrentMonthFolder(in folder: AuthorizedFolder) async throws
}

nonisolated enum ProjectCreationOutcome: Equatable, Sendable {
    case opened(UUID)
    case failed(EditorWorkflowIssue)
    case busy, cancelled
}
