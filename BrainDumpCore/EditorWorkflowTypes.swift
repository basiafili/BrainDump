import Foundation

nonisolated struct EditorWorkflowIssue: Identifiable, Equatable, Sendable {
    enum Kind: Sendable { case save, project, state }
    let id = UUID()
    let kind: Kind
    let sessionID: UUID?
    let message: String
}

nonisolated enum EditorOperationOutcome: Equatable, Sendable {
    case completed
    /// Permission to close these windows; unregister only on native closure.
    case closeWindows([UUID])
    case failed(EditorWorkflowIssue)
    case busy
    case cancelled
    case missingSession

    var succeeded: Bool {
        switch self {
        case .completed, .closeWindows: true
        default: false
        }
    }
}

nonisolated enum EditorSaveOutcome: Equatable, Sendable {
    case saved(CaptureBinding)
    case empty
    case failed(EditorWorkflowIssue)
    case busy
    case cancelled
    case missingSession

    var transitionFailure: EditorOperationOutcome? {
        switch self {
        case .saved, .empty: nil
        case .failed(let issue): .failed(issue)
        case .busy: .busy
        case .cancelled: .cancelled
        case .missingSession: .missingSession
        }
    }
}

nonisolated enum EditorWorkflowError: Error, LocalizedError, Sendable {
    case busy, projectChanged, captureChanged, invalidSaveReceipt, unexpectedClose

    var errorDescription: String? {
        switch self {
        case .busy: "Finish the pending operation before starting this action."
        case .projectChanged: "The project changed during this operation. Please try again."
        case .captureChanged: "The capture changed during this operation. Its current text has been preserved. Please try again."
        case .invalidSaveReceipt: "The save service returned an unexpected result. The editor's text has been preserved."
        case .unexpectedClose: "A window closed without completing its save workflow. Its session has been retained."
        }
    }
}

nonisolated enum EditorFolderChangeMode: Sendable { case keepOpen, saveAndClose }
