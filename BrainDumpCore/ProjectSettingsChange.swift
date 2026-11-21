import Foundation

nonisolated struct ProjectSettingsChange: Equatable, Sendable {
    let projectID: UUID
    let name: String
    let folder: AuthorizedFolder?
}

nonisolated struct PreparedProjectSettingsChange: Sendable {
    let original: ProjectRecord
    let name: String
    let folder: AuthorizedFolder?
}
