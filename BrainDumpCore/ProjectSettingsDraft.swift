import Foundation
import Observation

@MainActor
@Observable
final class ProjectSettingsDraft {
    private(set) var original: ProjectRecord
    var name: String { didSet { if oldValue != name { commitError = nil } } }
    let folderChoice: ProjectFolderDraft
    private(set) var authorizedFolder: AuthorizedFolder?
    private(set) var folderError: String?
    var commitError: String?
    private var validationID: UUID?

    init(project: ProjectRecord) {
        original = project
        name = project.name
        folderChoice = ProjectFolderDraft(projectID: project.id)
    }

    var hasChanges: Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines) != original.name || folderChoice.change != nil
    }

    func inputProblems(projects: ProjectStore) -> [String] {
        var messages: [String] = []
        if let issue = projects.nameValidationMessage(name, excluding: original.id) { messages.append(issue) }
        if let folderError { messages.append(folderError) }
        if let authorizedFolder, let issue = projects.folderValidationMessage(authorizedFolder, excluding: original.id) { messages.append(issue) }
        return messages
    }

    func beginValidation(_ url: URL, choice: ProjectFolderDraft.Choice) -> Bool {
        guard folderChoice.accept(url, for: choice) else { return false }
        validationID = choice.id
        authorizedFolder = nil
        folderError = nil
        commitError = nil
        return true
    }

    func finishValidation(_ result: Result<AuthorizedFolder, any Error>, choice: ProjectFolderDraft.Choice) {
        guard validationID == choice.id else { return }
        validationID = nil
        switch result {
        case .success(let folder): authorizedFolder = folder; folderError = nil
        case .failure(let error): folderError = error.localizedDescription
        }
    }

    func snapshot() -> ProjectSettingsChange {
        ProjectSettingsChange(projectID: original.id, name: name, folder: authorizedFolder)
    }

    func didCommit(_ project: ProjectRecord, snapshot: ProjectSettingsChange) {
        original = project
        // Preserve any newer draft input rather than replacing it with the
        // submitted snapshot, even though the UI normally disables edits here.
        if name == snapshot.name { name = project.name }
        if authorizedFolder == snapshot.folder {
            folderChoice.clear()
            authorizedFolder = nil
            folderError = nil
        }
        commitError = nil
    }
}
