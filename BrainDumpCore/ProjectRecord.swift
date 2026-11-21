import Foundation

/// Stable registry handles survive an explicit path edit; folder identity still
/// defines uniqueness. All values crossing the filesystem actor are Sendable.
nonisolated struct FolderIdentity: Codable, Equatable, Sendable {
    let device: UInt64
    let inode: UInt64
    var volumeUUID: String? = nil

    static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.inode == rhs.inode else { return false }
        switch (lhs.volumeUUID, rhs.volumeUUID) {
        case (.some(let left), .some(let right)): return left == right
        case (nil, nil): return lhs.device == rhs.device
        default: return false
        }
    }
}

nonisolated struct AuthorizedFolder: Codable, Equatable, Sendable {
    let path: String
    let identity: FolderIdentity
    let bookmark: Data

    var url: URL { URL(fileURLWithPath: path, isDirectory: true) }
}

nonisolated struct ProjectRecord: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    var folder: AuthorizedFolder
}

nonisolated enum ProjectAvailability: Equatable, Sendable {
    case unchecked
    case available
    case unavailable(String)

    var isAvailable: Bool { self == .available }
    var explanation: String {
        switch self {
        case .unchecked: String(localized: "Folder access has not been checked yet.")
        case .available: String(localized: "Folder is available.")
        case .unavailable(let reason): reason
        }
    }
}

nonisolated enum ProjectError: Error, LocalizedError, Equatable, Sendable {
    case emptyName, duplicateName, duplicateFolder, missingProject, changedDuringOperation
    case invalidRegistry, movedFolder, replacedFolder, inaccessibleFolder, selectionChanged

    var errorDescription: String? {
        switch self {
        case .emptyName: String(localized: "Enter a project name.")
        case .duplicateName: String(localized: "A project with this name is already registered.")
        case .duplicateFolder: String(localized: "This folder is already registered as a project.")
        case .missingProject: String(localized: "This project is no longer registered.")
        case .changedDuringOperation: String(localized: "The project changed during this operation. Please try again.")
        case .invalidRegistry: String(localized: "The saved project registry could not be read. It has not been replaced.")
        case .movedFolder: String(localized: "The project folder was moved or renamed. Use Change Folder in Project Settings to reconnect it.")
        case .replacedFolder: String(localized: "The original project folder is no longer at this path. Use Change Folder in Project Settings to reconnect it.")
        case .inaccessibleFolder: String(localized: "The folder is missing or cannot be accessed for reading and writing. Choose an accessible folder.")
        case .selectionChanged: String(localized: "The selected folder changed. Choose the folder again before creating the project.")
        }
    }
}

nonisolated struct FolderAccess: Sendable {
    let token: UUID
    let folder: AuthorizedFolder
}

nonisolated struct ProjectFolderConflictError: Error, LocalizedError, Equatable, Sendable {
    let projectID: UUID
    let projectName: String
    let registeredPath: String

    var errorDescription: String? {
        String(localized: "This folder is already registered to “\(projectName)” at \(registeredPath). Select that project in Project Settings to repair it, or choose a different folder.")
    }
}

nonisolated protocol FolderAuthorizing: Sendable {
    func authorizeSelection(_ url: URL) async throws -> AuthorizedFolder
    func inspect(_ folder: AuthorizedFolder) async throws -> AuthorizedFolder
    func acquire(_ folder: AuthorizedFolder) async throws -> FolderAccess
    func release(_ token: UUID) async
}
