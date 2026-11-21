import Foundation
import Testing

actor PausedFolderAuthorization: FolderAuthorizing {
    private let immediate = TestFolderAuthorization()
    private var shouldPause = true
    private var pending: CheckedContinuation<Void, Never>?
    private var observer: CheckedContinuation<Void, Never>?

    func authorizeSelection(_ url: URL) async throws -> AuthorizedFolder {
        if shouldPause {
            shouldPause = false
            await withCheckedContinuation { continuation in
                pending = continuation
                observer?.resume()
                observer = nil
            }
        }
        return try await immediate.authorizeSelection(url)
    }
    func inspect(_ folder: AuthorizedFolder) async throws -> AuthorizedFolder { try await immediate.inspect(folder) }
    func acquire(_ folder: AuthorizedFolder) async throws -> FolderAccess { try await immediate.acquire(folder) }
    func release(_ token: UUID) async { await immediate.release(token) }
    func waitUntilPaused() async {
        if pending != nil { return }
        await withCheckedContinuation { observer = $0 }
    }
    func resume() { pending?.resume(); pending = nil }
}

@Suite("Registry concurrency", .timeLimit(.minutes(1)))
@MainActor
struct ProjectConcurrencyTests {
    @Test func suspendedRegistrationRechecksNamesBeforeCommit() async throws {
        let suite = "BrainDumpTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let folders = PausedFolderAuthorization()
        let store = try ProjectStore(defaults: defaults, folders: folders)
        let pending = Task { @MainActor in
            try await store.register(name: "Notes", selectedFolder: URL(fileURLWithPath: "/fixtures/first"))
        }
        await folders.waitUntilPaused()
        _ = try await store.register(name: "NOTES", selectedFolder: URL(fileURLWithPath: "/fixtures/second"))
        await folders.resume()
        await #expect(throws: ProjectError.duplicateName) { try await pending.value }
        #expect(store.projects.count == 1 && store.projects.first?.name == "NOTES")
    }

    @Test func cancelledRegistrationDoesNotCommit() async throws {
        let suite = "BrainDumpTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let folders = PausedFolderAuthorization()
        let store = try ProjectStore(defaults: defaults, folders: folders)
        let pending = Task { @MainActor in
            try await store.register(name: "Notes", selectedFolder: URL(fileURLWithPath: "/fixtures/cancelled"))
        }
        await folders.waitUntilPaused()
        pending.cancel()
        await folders.resume()
        await #expect(throws: CancellationError.self) { try await pending.value }
        #expect(store.projects.isEmpty && store.recentIDs.isEmpty && store.lastActiveID == nil)
        #expect(defaults.object(forKey: "projectRegistry") == nil)
    }
}
