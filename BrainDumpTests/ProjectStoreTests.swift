import Foundation
import Testing

actor TestFolderAuthorization: FolderAuthorizing {
    private var failures: [String: ProjectError] = [:]
    private var selected: [String: AuthorizedFolder] = [:]
    private var leases: [UUID: AuthorizedFolder] = [:]

    func authorizeSelection(_ url: URL) throws -> AuthorizedFolder {
        if let folder = selected[url.path] { return folder }
        let number = UInt64(selected.count + 1)
        let folder = AuthorizedFolder(path: url.path, identity: FolderIdentity(device: 1, inode: number), bookmark: Data(url.path.utf8))
        selected[url.path] = folder
        return folder
    }
    func inspect(_ folder: AuthorizedFolder) throws -> AuthorizedFolder {
        if let failure = failures[folder.path] { throw failure }
        return folder
    }
    func acquire(_ folder: AuthorizedFolder) throws -> FolderAccess {
        let inspected = try inspect(folder)
        let access = FolderAccess(token: UUID(), folder: inspected)
        leases[access.token] = inspected
        return access
    }
    func release(_ token: UUID) { leases.removeValue(forKey: token) }
    func fail(_ path: String, with error: ProjectError) { failures[path] = error }
    func alias(_ path: String, to folder: AuthorizedFolder) { selected[path] = folder }
    var leaseCount: Int { leases.count }
}

@MainActor
private struct StoreFixture {
    let suite = "BrainDumpTests.\(UUID().uuidString)"
    let defaults: UserDefaults
    let folders = TestFolderAuthorization()
    let store: ProjectStore

    init() throws {
        defaults = try #require(UserDefaults(suiteName: suite))
        store = try ProjectStore(defaults: defaults, folders: folders)
    }
    func cleanup() { defaults.removePersistentDomain(forName: suite) }
    func register(_ number: Int, name: String? = nil) async throws -> ProjectRecord {
        try await store.register(name: name ?? "Project \(number)", selectedFolder: URL(fileURLWithPath: "/fixtures/folder\(number)"))
    }
}

@Suite("Project registry", .timeLimit(.minutes(1)))
@MainActor
struct ProjectStoreTests {
    @Test func persistenceAndDefaults() async throws {
        let f = try StoreFixture(); defer { f.cleanup() }
        #expect(!f.store.alwaysOpenInNewWindow)
        let project = try await f.register(1, name: "  Notes \n")
        #expect(project.name == "Notes")
        #expect(f.store.recentIDs.isEmpty && f.store.lastActiveID == nil)
        try f.store.recordOpened(project.id)
        try f.store.setAlwaysOpenInNewWindow(true)
        let reopened = try ProjectStore(defaults: f.defaults, folders: f.folders)
        #expect(reopened.projects == [project])
        #expect(reopened.recentIDs == [project.id] && reopened.lastActiveID == project.id)
        #expect(reopened.alwaysOpenInNewWindow)
        #expect(reopened.reachableProjects.isEmpty)
        await reopened.refreshAvailability()
        #expect(reopened.reachableProjects == [project])
    }

    @Test func namesAndPhysicalFolderDuplicates() async throws {
        let f = try StoreFixture(); defer { f.cleanup() }
        let project = try await f.register(1, name: "Notes")
        await #expect(throws: ProjectError.duplicateName) { try await f.register(2, name: " notes ") }
        await #expect(throws: ProjectError.emptyName) { try await f.register(3, name: " \n ") }
        await f.folders.alias("/fixtures/alias", to: project.folder)
        await #expect(throws: ProjectError.duplicateFolder) {
            try await f.store.register(name: "Alias", selectedFolder: URL(fileURLWithPath: "/fixtures/alias"))
        }
        #expect(f.store.projects.count == 1)
    }

    @Test func focusNeverReordersMRU() async throws {
        let f = try StoreFixture(); defer { f.cleanup() }
        let first = try await f.register(1)
        let second = try await f.register(2)
        try f.store.recordOpened(first.id)
        try f.store.recordOpened(second.id)
        try f.store.recordEditorActivated(first.id)
        #expect(f.store.recentIDs == [second.id, first.id])
        #expect(f.store.lastActiveID == first.id)
        try f.store.clearRecent()
        #expect(f.store.recentIDs.isEmpty && f.store.lastActiveID == first.id)
        #expect(f.store.projects.count == 2)
    }

    @Test func mruCapAndRemoval() async throws {
        let f = try StoreFixture(); defer { f.cleanup() }
        var projects: [ProjectRecord] = []
        for i in 0..<12 {
            let p = try await f.register(i)
            projects.append(p)
            try f.store.recordOpened(p.id)
        }
        #expect(f.store.recentIDs == projects.suffix(10).reversed().map(\.id))
        let last = try #require(projects.last)
        try f.store.remove(last.id)
        #expect(f.store.lastActiveID == nil)
        #expect(!f.store.recentIDs.contains(last.id))
        #expect(f.store.projects.count == 11)
    }

    @Test func movedFolderRemainsRegisteredAndCanBeRepaired() async throws {
        let f = try StoreFixture(); defer { f.cleanup() }
        let p = try await f.register(1)
        try f.store.recordOpened(p.id)
        await f.folders.fail(p.folder.path, with: .movedFolder)
        await #expect(throws: ProjectError.movedFolder) { try await f.store.revalidate(p.id) }
        #expect(f.store.projects == [p])
        #expect(f.store.reachableProjects.isEmpty && f.store.recentProjects.isEmpty)
        #expect(f.store.recentIDs == [p.id] && f.store.lastActiveID == p.id)
        #expect(f.store.availability[p.id] == .unavailable(ProjectError.movedFolder.localizedDescription))
        try await f.store.changeFolder(p.id, selectedFolder: URL(fileURLWithPath: "/fixtures/repaired"))
        #expect(f.store.projects.first?.id == p.id)
        #expect(f.store.projects.first?.folder.path == "/fixtures/repaired")
        #expect(f.store.reachableProjects.count == 1)
        #expect(f.store.recentIDs == [p.id] && f.store.lastActiveID == p.id)
    }

    @Test func existingLeaseSurvivesPathEditAndRemoval() async throws {
        let f = try StoreFixture(); defer { f.cleanup() }
        let p = try await f.register(1)
        let access = try await f.folders.acquire(p.folder)
        try await f.store.changeFolder(p.id, selectedFolder: URL(fileURLWithPath: "/fixtures/new"))
        try f.store.remove(p.id)
        #expect(access.folder == p.folder)
        #expect(await f.folders.leaseCount == 1)
        await f.folders.release(access.token)
        await f.folders.release(access.token)
        #expect(await f.folders.leaseCount == 0)
    }

    @Test func invalidPersistenceIsNotOverwritten() throws {
        let f = try StoreFixture(); defer { f.cleanup() }
        let bad = Data("invalid registry".utf8)
        f.defaults.set(bad, forKey: "projectRegistry")
        #expect(throws: ProjectError.invalidRegistry) { try ProjectStore(defaults: f.defaults, folders: f.folders) }
        #expect(f.defaults.data(forKey: "projectRegistry") == bad)
    }

    @Test func renameValidationUsesEntireRegistry() async throws {
        let f = try StoreFixture(); defer { f.cleanup() }
        let first = try await f.register(1, name: "First")
        let second = try await f.register(2, name: "Second")
        await f.folders.fail(first.folder.path, with: .inaccessibleFolder)
        await f.store.refreshAvailability()
        #expect(throws: ProjectError.duplicateName) { try f.store.rename(second.id, to: "FIRST") }
        try f.store.rename(first.id, to: "  Renamed  ")
        #expect(f.store.projects.first?.name == "Renamed")
    }
}
