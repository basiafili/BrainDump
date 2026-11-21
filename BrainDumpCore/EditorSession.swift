import Foundation
import Observation

/// Coordinator-owned source of truth. Views read state and send edits as intent;
/// they cannot bypass read-only transitions by assigning to text/binding directly.
@MainActor
@Observable
final class EditorSession: Identifiable {
    let id: UUID
    private(set) var project: ProjectRecord
    private(set) var text = ""
    private(set) var textRevision: UInt64 = 0
    private(set) var captureID = UUID()
    private(set) var focusRequestID = UUID()
    private(set) var binding: CaptureBinding?
    private(set) var pendingSaveCount = 0
    private(set) var transitionID: UUID?
    private(set) var issue: EditorWorkflowIssue?

    var isReadOnly: Bool { transitionID != nil }
    var isSaving: Bool { pendingSaveCount > 0 }
    var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var isUnsaved: Bool { binding.map { Data(text.utf8) != $0.baseline } ?? !isEmpty }
    var title: String { CaptureTitleFormatter().title(projectName: project.name, firstSavedAt: binding?.firstSavedAt) }

    init(project: ProjectRecord) {
        id = UUID()
        self.project = project
    }

    // State updates only, not workflow or persistence logic.
    func acceptText(_ value: String) {
        guard text != value else { return }
        text = value
        textRevision &+= 1
    }
    func updateProject(_ value: ProjectRecord) { project = value }
    func beginTransition(_ token: UUID) { transitionID = token }
    func endTransition(_ token: UUID) { if transitionID == token { transitionID = nil } }
    func enqueueSave() { pendingSaveCount += 1 }
    func finishSave() { pendingSaveCount -= 1 }
    func recordIssue(_ value: EditorWorkflowIssue) { issue = value }
    func recordSaved(_ value: CaptureBinding) {
        binding = value
        if issue?.kind == .save { issue = nil }
    }
    func resetCapture(project: ProjectRecord? = nil) {
        if let project { self.project = project }
        text = ""
        textRevision &+= 1
        captureID = UUID()
        focusRequestID = UUID()
        binding = nil
        issue = nil
    }
}
