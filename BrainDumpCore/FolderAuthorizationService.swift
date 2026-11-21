import Foundation

/// All bookmark/filesystem work is isolated from the UI actor. Leases retain the
/// original folder independently of later registry edits.
actor FolderAuthorizationService: FolderAuthorizing {
    private struct Lease {
        let url: URL
        let didStart: Bool
    }
    private var leases: [UUID: Lease] = [:]

    func authorizeSelection(_ url: URL) throws -> AuthorizedFolder {
        let started = url.startAccessingSecurityScopedResource()
        defer { if started { url.stopAccessingSecurityScopedResource() } }
        return try describe(url)
    }

    func inspect(_ folder: AuthorizedFolder) throws -> AuthorizedFolder {
        let (url, started) = try resolve(folder)
        defer { if started { url.stopAccessingSecurityScopedResource() } }
        return try describe(url)
    }

    func acquire(_ folder: AuthorizedFolder) throws -> FolderAccess {
        let (url, started) = try resolve(folder)
        do {
            let resolved = try describe(url)
            let token = UUID()
            leases[token] = Lease(url: url, didStart: started)
            return FolderAccess(token: token, folder: resolved)
        } catch {
            if started { url.stopAccessingSecurityScopedResource() }
            throw error
        }
    }

    func release(_ token: UUID) {
        guard let lease = leases.removeValue(forKey: token) else { return }
        if lease.didStart { lease.url.stopAccessingSecurityScopedResource() }
    }

    /// Scoped operation for callers that need access for one async operation only.
    func withAccess<Result: Sendable>(
        to folder: AuthorizedFolder,
        operation: @Sendable (URL) async throws -> Result
    ) async throws -> Result {
        let access = try acquire(folder)
        defer { release(access.token) }
        return try await operation(access.folder.url)
    }

    private func resolve(_ folder: AuthorizedFolder) throws -> (URL, Bool) {
        var stale = false
        let url = try URL(resolvingBookmarkData: folder.bookmark,
                          options: [.withSecurityScope, .withoutUI],
                          relativeTo: nil, bookmarkDataIsStale: &stale)
        let started = url.startAccessingSecurityScopedResource()
        do {
            let actual = try metadata(url)
            // A bookmark's ability to follow a move is NOT permission to change
            // the registered path. Also reject a replacement at that old path.
            guard actual.path == folder.path else { throw ProjectError.movedFolder }
            guard actual.identity == folder.identity else { throw ProjectError.replacedFolder }
            return (url, started)
        } catch {
            if started { url.stopAccessingSecurityScopedResource() }
            throw error
        }
    }

    private func metadata(_ url: URL) throws -> (path: String, identity: FolderIdentity) {
        let canonical = url.standardizedFileURL.resolvingSymlinksInPath()
        let values = try canonical.resourceValues(forKeys: [.isDirectoryKey, .isReadableKey, .isWritableKey, .volumeUUIDStringKey])
        guard values.isDirectory == true, values.isReadable == true, values.isWritable == true else {
            throw ProjectError.inaccessibleFolder
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: canonical.path)
        guard let device = attributes[.systemNumber] as? NSNumber,
              let inode = attributes[.systemFileNumber] as? NSNumber else {
            throw ProjectError.inaccessibleFolder
        }
        // Device numbers can change when a volume is remounted. Prefer its stable
        // UUID; use device+inode only on filesystems that do not provide one.
        return (canonical.path, FolderIdentity(device: device.uint64Value, inode: inode.uint64Value,
                                               volumeUUID: values.volumeUUIDString))
    }

    private func describe(_ url: URL) throws -> AuthorizedFolder {
        let actual = try metadata(url)
        // Bookmark the physical directory, not a symlink URL with a trailing slash
        // (which Foundation cannot always open). The selected/resolved security
        // scope remains active for this entire operation.
        let canonical = url.standardizedFileURL.resolvingSymlinksInPath()
        let bookmark = try canonical.bookmarkData(options: .withSecurityScope,
                                            includingResourceValuesForKeys: nil, relativeTo: nil)
        return AuthorizedFolder(path: actual.path, identity: actual.identity, bookmark: bookmark)
    }
}

extension FolderAuthorizationService {
    /// Checkpoint-only user-invoked probe. It creates no capture and touches only
    /// its own uniquely named temporary file while testing real read/write access.
    func verifyWriteAccess(_ folder: AuthorizedFolder) throws -> AuthorizedFolder {
        let access = try acquire(folder)
        defer { release(access.token) }
        let file = access.folder.url.appendingPathComponent(".BrainDump-access-check-\(UUID().uuidString).tmp")
        let payload = Data("BrainDump folder-access verification".utf8)
        // Foundation forbids combining .atomic with .withoutOverwriting.
        // This is a disposable probe, not a capture: exclusive creation matters
        // here, while capture publication will have its own atomic writer.
        try payload.write(to: file, options: .withoutOverwriting)
        do {
            guard try Data(contentsOf: file) == payload else { throw ProjectError.inaccessibleFolder }
            try FileManager.default.removeItem(at: file)
        } catch {
            try? FileManager.default.removeItem(at: file)
            throw error
        }
        return access.folder
    }
}
