import Foundation
import Observation

@MainActor
@Observable
final class NewProjectDraft: Identifiable {
    let id = UUID()
    let originatingEditorID: UUID?
    let explanation: String?
    var name = ""
    var openInNewWindow: Bool
    private(set) var selectedURL: URL?
    private(set) var selectedFolder: AuthorizedFolder?
    private(set) var folderError: String?
    var creationError: String?
    var isWorking = false
    private(set) var didCreateProject = false
    var closeRequested = false

    func nameValidationMessage(projects: ProjectStore?) -> String? {
        // The new name becomes registered before the closing form disappears.
        // That successful commit must never announce a duplicate-name error.
        guard !isWorking, !didCreateProject else { return nil }
        return projects?.nameValidationMessage(name)
    }

    func completeCreation() {
        didCreateProject = true
        creationError = nil
        closeRequested = true
        isWorking = false
    }

    init(originatingEditorID: UUID?, explanation: String?, openInNewWindow: Bool) {
        self.originatingEditorID = originatingEditorID
        self.explanation = explanation
        self.openInNewWindow = openInNewWindow
    }

    func choose(_ url: URL, folders: any FolderAuthorizing, projects: ProjectStore) async {
        guard !isWorking else { return }
        isWorking = true
        selectedURL = nil
        selectedFolder = nil
        folderError = nil
        creationError = nil
        defer { isWorking = false }
        do {
            let folder = try await folders.authorizeSelection(url)
            guard !projects.projects.contains(where: { $0.folder.path == folder.path || $0.folder.identity == folder.identity }) else {
                throw ProjectError.duplicateFolder
            }
            selectedURL = url
            selectedFolder = folder
        } catch { folderError = error.localizedDescription }
    }

    func selectionFailed(_ error: any Error) { folderError = error.localizedDescription }
}
