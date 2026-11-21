import Foundation
import Testing

@Suite("Folder authorization", .timeLimit(.minutes(1)))
struct FolderAuthorizationTests {
    @Test func remountDeviceNumberDoesNotChangePhysicalIdentity() {
        let before = FolderIdentity(device: 1, inode: 42, volumeUUID: "volume-A")
        let remounted = FolderIdentity(device: 2, inode: 42, volumeUUID: "volume-A")
        let differentVolume = FolderIdentity(device: 1, inode: 42, volumeUUID: "volume-B")
        #expect(before == remounted)
        #expect(before != differentVolume)
        #expect(before != FolderIdentity(device: 1, inode: 43, volumeUUID: "volume-A"))
    }

    private func temporaryFolder() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("BrainDumpTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @Test func realBookmarkRoundTripAndSymlinkIdentity() async throws {
        let root = try temporaryFolder(); defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("Project", isDirectory: true)
        let alias = root.appendingPathComponent("Alias", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: folder)
        let service = FolderAuthorizationService()
        let selected = try await service.authorizeSelection(folder)
        let linked = try await service.authorizeSelection(alias)
        #expect(selected.identity == linked.identity)
        #expect(selected.path == linked.path)
        let reopened = try await service.inspect(selected)
        #expect(reopened.identity == selected.identity && reopened.path == selected.path)
        let access = try await service.acquire(selected)
        #expect(access.folder.identity == selected.identity)
        await service.release(access.token)
        await service.release(access.token)
        _ = try await service.verifyWriteAccess(selected)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
    }

    @Test func externalMoveNeverChangesRegistration() async throws {
        let root = try temporaryFolder(); defer { try? FileManager.default.removeItem(at: root) }
        let original = root.appendingPathComponent("Original", isDirectory: true)
        let moved = root.appendingPathComponent("Moved", isDirectory: true)
        try FileManager.default.createDirectory(at: original, withIntermediateDirectories: false)
        let service = FolderAuthorizationService()
        let saved = try await service.authorizeSelection(original)
        try FileManager.default.moveItem(at: original, to: moved)
        await #expect(throws: (any Error).self) { try await service.inspect(saved) }
        let repaired = try await service.authorizeSelection(moved)
        #expect(repaired.identity == saved.identity)
        #expect(repaired.path != saved.path)
    }

    @Test func replacementAtOldPathIsNotTheOriginalFolder() async throws {
        let root = try temporaryFolder(); defer { try? FileManager.default.removeItem(at: root) }
        let original = root.appendingPathComponent("Original", isDirectory: true)
        let moved = root.appendingPathComponent("Moved", isDirectory: true)
        try FileManager.default.createDirectory(at: original, withIntermediateDirectories: false)
        let service = FolderAuthorizationService()
        let saved = try await service.authorizeSelection(original)
        try FileManager.default.moveItem(at: original, to: moved)
        try FileManager.default.createDirectory(at: original, withIntermediateDirectories: false)
        await #expect(throws: (any Error).self) { try await service.acquire(saved) }
        let replacement = try await service.authorizeSelection(original)
        #expect(replacement.identity != saved.identity)
    }

    @Test func nonexistentFolderIsRejected() async {
        let service = FolderAuthorizationService()
        await #expect(throws: (any Error).self) {
            try await service.authorizeSelection(URL(fileURLWithPath: "/private/tmp/BrainDumpMissing-\(UUID().uuidString)"))
        }
    }

    @Test func caseAliasesRespectFilesystemIdentity() async throws {
        let root = try temporaryFolder(); defer { try? FileManager.default.removeItem(at: root) }
        let uppercase = root.appendingPathComponent("Project", isDirectory: true)
        let lowercase = root.appendingPathComponent("project", isDirectory: true)
        try FileManager.default.createDirectory(at: uppercase, withIntermediateDirectories: false)
        let service = FolderAuthorizationService()
        let first = try await service.authorizeSelection(uppercase)
        if FileManager.default.fileExists(atPath: lowercase.path) {
            let alias = try await service.authorizeSelection(lowercase)
            #expect(first.identity == alias.identity)
        } else {
            try FileManager.default.createDirectory(at: lowercase, withIntermediateDirectories: false)
            let distinct = try await service.authorizeSelection(lowercase)
            #expect(first.identity != distinct.identity)
        }
    }
}
