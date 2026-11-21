import Foundation
import Observation

nonisolated private struct RegistryState: Codable {
    var projects: [ProjectRecord] = []
    var recent: [UUID] = []
    var lastActive: UUID?
    var alwaysOpenInNewWindow = false
}

@MainActor
@Observable
final class ProjectStore {
    private var state: RegistryState
    private(set) var availability: [UUID: ProjectAvailability] = [:]
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let folders: any FolderAuthorizing
    private static let storageKey = "projectRegistry"

    init(defaults: UserDefaults = .standard, folders: any FolderAuthorizing) throws {
        self.defaults = defaults
        self.folders = folders
        if let bytes = defaults.data(forKey: Self.storageKey) {
            guard let loaded = try? JSONDecoder().decode(RegistryState.self, from: bytes),
                  Self.isValid(loaded) else { throw ProjectError.invalidRegistry }
            state = loaded
        } else if defaults.object(forKey: Self.storageKey) != nil {
            throw ProjectError.invalidRegistry
        } else {
            state = RegistryState()
        }
    }

    var projects: [ProjectRecord] { state.projects }
    var recentIDs: [UUID] { state.recent }
    var lastActiveID: UUID? { state.lastActive }
    var alwaysOpenInNewWindow: Bool { state.alwaysOpenInNewWindow }
    var reachableProjects: [ProjectRecord] { projects.filter { availability[$0.id]?.isAvailable == true } }
    var recentProjects: [ProjectRecord] {
        state.recent.compactMap { id in reachableProjects.first { $0.id == id } }
    }

    func register(name: String, selectedFolder: URL) async throws -> ProjectRecord {
        let project = try await prepareRegistration(name: name, selectedFolder: selectedFolder)
        try commitRegistration(project, opened: false)
        return project
    }

    /// Preparation has no registry/usage side effects. Recheck at commit after
    /// any intervening save or filesystem await.
    func prepareRegistration(name: String, selectedFolder: URL) async throws -> ProjectRecord {
        let name = try validatedName(name)
        let folder = try await folders.authorizeSelection(selectedFolder)
        try Task.checkCancellation()
        // Await may have allowed another registration: validate AGAIN before commit.
        _ = try validatedName(name)
        try validateUniqueFolder(folder)
        let project = ProjectRecord(id: UUID(), name: name, folder: folder)
        return project
    }

    func revalidateRegistration(_ project: ProjectRecord) async throws -> ProjectRecord {
        let folder = try await folders.inspect(project.folder)
        try Task.checkCancellation()
        guard folder.path == project.folder.path else { throw ProjectError.movedFolder }
        guard folder.identity == project.folder.identity else { throw ProjectError.replacedFolder }
        return ProjectRecord(id: project.id, name: project.name, folder: folder)
    }

    func commitRegistration(_ project: ProjectRecord, opened: Bool) throws {
        _ = try validatedName(project.name)
        try validateUniqueFolder(project.folder)
        guard !projects.contains(where: { $0.id == project.id }) else { throw ProjectError.changedDuringOperation }
        var next = state
        next.projects.append(project)
        if opened {
            next.recent.insert(project.id, at: 0)
            next.recent = Array(next.recent.prefix(10))
            next.lastActive = project.id
        }
        try commit(next)
        availability[project.id] = .available
    }

    func nameValidationMessage(_ name: String, excluding projectID: UUID? = nil) -> String? {
        do { _ = try validatedName(name, excluding: projectID); return nil }
        catch { return error.localizedDescription }
    }

    func folderValidationMessage(_ folder: AuthorizedFolder, excluding projectID: UUID) -> String? {
        do { try validateReplacement(folder, excluding: projectID); return nil }
        catch { return error.localizedDescription }
    }

    func authorizeReplacementFolder(_ id: UUID, selectedFolder: URL) async throws -> AuthorizedFolder {
        guard let original = projects.first(where: { $0.id == id }) else { throw ProjectError.missingProject }
        let folder = try await folders.authorizeSelection(selectedFolder)
        try Task.checkCancellation()
        try requireUnchangedRegistration(original)
        try validateReplacement(folder, excluding: id)
        return folder
    }

    func prepareSettingsChange(_ change: ProjectSettingsChange) async throws -> PreparedProjectSettingsChange {
        guard let original = projects.first(where: { $0.id == change.projectID }) else { throw ProjectError.missingProject }
        let name = try validatedName(change.name, excluding: original.id)
        let folder = try await inspectReplacement(change.folder)
        try Task.checkCancellation()
        try requireUnchangedRegistration(original)
        _ = try validatedName(name, excluding: original.id)
        if let folder { try validateReplacement(folder, excluding: original.id) }
        return PreparedProjectSettingsChange(original: original, name: name, folder: folder)
    }

    func revalidateSettingsChange(_ prepared: PreparedProjectSettingsChange) async throws -> PreparedProjectSettingsChange {
        try requireUnchangedRegistration(prepared.original)
        let folder = try await inspectReplacement(prepared.folder)
        try Task.checkCancellation()
        try requireUnchangedRegistration(prepared.original)
        return PreparedProjectSettingsChange(original: prepared.original, name: prepared.name, folder: folder)
    }

    /// No await: registry fields and session references can commit in one
    /// main-actor segment after all validation/saves have completed.
    func commitSettingsChange(_ prepared: PreparedProjectSettingsChange) throws {
        try requireUnchangedRegistration(prepared.original)
        let name = try validatedName(prepared.name, excluding: prepared.original.id)
        if let folder = prepared.folder { try validateReplacement(folder, excluding: prepared.original.id) }
        guard let index = state.projects.firstIndex(where: { $0.id == prepared.original.id }) else { throw ProjectError.missingProject }
        var next = state
        next.projects[index].name = name
        if let folder = prepared.folder { next.projects[index].folder = folder }
        try commit(next)
        if prepared.folder != nil { availability[prepared.original.id] = .available }
    }

    private func inspectReplacement(_ expected: AuthorizedFolder?) async throws -> AuthorizedFolder? {
        guard let expected else { return nil } // Renaming unavailable projects must not require folder access.
        let actual = try await folders.inspect(expected)
        guard actual.path == expected.path else { throw ProjectError.movedFolder }
        guard actual.identity == expected.identity else { throw ProjectError.replacedFolder }
        return actual
    }

    private func requireUnchangedRegistration(_ original: ProjectRecord) throws {
        guard let current = projects.first(where: { $0.id == original.id }) else { throw ProjectError.missingProject }
        // Bookmark refresh alone is not a competing metadata edit.
        guard current.name == original.name, current.folder.path == original.folder.path,
              current.folder.identity == original.folder.identity else { throw ProjectError.changedDuringOperation }
    }

    private func validateReplacement(_ folder: AuthorizedFolder, excluding id: UUID) throws {
        if let conflict = conflictingProject(folder, excluding: id) {
            throw ProjectFolderConflictError(projectID: conflict.id, projectName: conflict.name, registeredPath: conflict.folder.path)
        }
    }

    func rename(_ id: UUID, to name: String) throws {
        let name = try validatedName(name, excluding: id)
        guard let index = state.projects.firstIndex(where: { $0.id == id }) else { throw ProjectError.missingProject }
        var next = state
        next.projects[index].name = name
        try commit(next)
    }

    /// Workflow coordinator must prepare/close affected sessions before calling
    /// this registry commit. Existing leases and bound files are never released here.
    func changeFolder(_ id: UUID, selectedFolder: URL) async throws {
        guard let original = projects.first(where: { $0.id == id }) else { throw ProjectError.missingProject }
        let replacement = try await folders.authorizeSelection(selectedFolder)
        try Task.checkCancellation()
        guard let index = state.projects.firstIndex(where: { $0.id == id }), state.projects[index] == original else {
            throw ProjectError.changedDuringOperation
        }
        if let conflict = conflictingProject(replacement, excluding: id) {
            throw ProjectFolderConflictError(projectID: conflict.id, projectName: conflict.name, registeredPath: conflict.folder.path)
        }
        var next = state
        next.projects[index].folder = replacement
        try commit(next)
        availability[id] = .available
    }

    func remove(_ id: UUID) throws {
        guard projects.contains(where: { $0.id == id }) else { throw ProjectError.missingProject }
        var next = state
        next.projects.removeAll { $0.id == id }
        next.recent.removeAll { $0 == id }
        if next.lastActive == id { next.lastActive = nil }
        try commit(next)
        availability.removeValue(forKey: id)
    }

    func setAlwaysOpenInNewWindow(_ enabled: Bool) throws {
        var next = state
        next.alwaysOpenInNewWindow = enabled
        try commit(next)
    }

    func clearRecent() throws {
        var next = state
        next.recent = []
        try commit(next)
    }

    /// Call only after a successful explicit open/create-and-open/switch.
    func recordOpened(_ id: UUID) throws {
        guard availability[id]?.isAvailable == true, projects.contains(where: { $0.id == id }) else {
            throw ProjectError.inaccessibleFolder
        }
        var next = state
        next.recent.removeAll { $0 == id }
        next.recent.insert(id, at: 0)
        next.recent = Array(next.recent.prefix(10))
        next.lastActive = id
        try commit(next)
    }

    /// Focus affects last active, never MRU. Already-open sessions can retain a
    /// project whose current registration becomes unavailable.
    func recordEditorActivated(_ id: UUID) throws {
        guard projects.contains(where: { $0.id == id }) else { throw ProjectError.missingProject }
        var next = state
        next.lastActive = id
        try commit(next)
    }

    /// Revalidate immediately before opening. Does not update usage on its own.
    func revalidate(_ id: UUID) async throws -> ProjectRecord {
        guard let original = projects.first(where: { $0.id == id }) else { throw ProjectError.missingProject }
        do {
            let inspected = try await folders.inspect(original.folder)
            try Task.checkCancellation()
            guard let index = state.projects.firstIndex(where: { $0.id == id }), state.projects[index] == original else {
                throw ProjectError.changedDuringOperation
            }
            guard inspected.path == original.folder.path else { throw ProjectError.movedFolder }
            guard inspected.identity == original.folder.identity else { throw ProjectError.replacedFolder }
            var next = state
            next.projects[index].folder = inspected
            try commit(next)
            availability[id] = .available
            return state.projects[index]
        } catch {
            if error is CancellationError { throw error }
            // A stale failure must not mark an explicitly repaired record unavailable.
            if projects.first(where: { $0.id == id }) == original {
                availability[id] = .unavailable(error.localizedDescription)
            }
            throw error
        }
    }

    func refreshAvailability() async {
        for id in projects.map(\.id) {
            if Task.isCancelled { return }
            _ = try? await revalidate(id)
        }
    }

    private func validatedName(_ raw: String, excluding: UUID? = nil) throws -> String {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw ProjectError.emptyName }
        guard !projects.contains(where: {
            $0.id != excluding && $0.name.compare(name, options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX")) == .orderedSame
        }) else { throw ProjectError.duplicateName }
        return name
    }

    private func validateUniqueFolder(_ folder: AuthorizedFolder, excluding: UUID? = nil) throws {
        guard conflictingProject(folder, excluding: excluding) == nil else { throw ProjectError.duplicateFolder }
    }

    private func conflictingProject(_ folder: AuthorizedFolder, excluding: UUID? = nil) -> ProjectRecord? {
        projects.first(where: {
            $0.id != excluding && ($0.folder.identity == folder.identity || $0.folder.path == folder.path)
        })
    }

    private func commit(_ next: RegistryState) throws {
        let bytes = try JSONEncoder().encode(next)
        // One UserDefaults value keeps registry/usage/preference snapshots together.
        // UserDefaults is not a synchronous durable-storage transaction API.
        defaults.set(bytes, forKey: Self.storageKey)
        state = next
    }

    private static func isValid(_ value: RegistryState) -> Bool {
        let ids = Set(value.projects.map(\.id))
        guard ids.count == value.projects.count, value.recent.count <= 10,
              Set(value.recent).count == value.recent.count,
              value.recent.allSatisfy(ids.contains), value.lastActive.map(ids.contains) ?? true else { return false }
        for (index, project) in value.projects.enumerated() {
            guard !project.name.isEmpty,
                  project.name == project.name.trimmingCharacters(in: .whitespacesAndNewlines),
                  project.folder.path.hasPrefix("/"), !project.folder.bookmark.isEmpty else { return false }
            for other in value.projects.prefix(index) {
                if other.name.compare(project.name, options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX")) == .orderedSame
                    || other.folder.path == project.folder.path || other.folder.identity == project.folder.identity { return false }
            }
        }
        return true
    }
}
