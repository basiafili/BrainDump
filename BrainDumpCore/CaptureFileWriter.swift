import Foundation
import Darwin

nonisolated enum CaptureWriteError: Error, LocalizedError, Sendable {
    case invalidBinding, unsafeTarget, pathChanged, coordinationFailed, nameExhausted
    case io(operation: String, code: Int32)

    var errorDescription: String? {
        switch self {
        case .invalidBinding: "The capture's file location is invalid. Its text has not been discarded."
        case .unsafeTarget: "The capture path is not a regular file or folder. It was not overwritten."
        case .pathChanged: "The capture location changed during saving. Please try again."
        case .coordinationFailed: "File access could not be coordinated. Please try saving again."
        case .nameExhausted: "No unused capture filename could be allocated."
        case .io(let operation, let code):
            "\(operation): \(POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO).localizedDescription)"
        }
    }
}

/// Synchronous observation seam for deterministic failure/race tests, never a UI callback.
nonisolated struct CaptureWriteHooks: Sendable {
    enum Phase: Sendable { case wroteChunk, staged, inspected }
    var observe: @Sendable (Phase, URL) throws -> Void = { _, _ in }
}

/// The actor serializes BrainDump's critical writes. Each synchronous operation
/// creates/uses its NSFileCoordinator on one thread, without suspending in its accessor.
actor CaptureFileWriter: CaptureWriting, ProjectFolderPreparing {
    private let folders: any FolderAuthorizing
    private let now: @Sendable () -> Date
    private let hooks: CaptureWriteHooks

    init(folders: any FolderAuthorizing,
         now: @escaping @Sendable () -> Date = { Date() },
         hooks: CaptureWriteHooks = CaptureWriteHooks()) {
        self.folders = folders
        self.now = now
        self.hooks = hooks
    }

    func save(_ request: CaptureWriteRequest) async throws -> CaptureWriteOutcome {
        guard !request.isEmpty else { return .empty }
        try Task.checkCancellation()
        let access = try await folders.acquire(request.binding?.folder ?? request.projectFolder)
        let result: Result<CaptureWriteOutcome, any Error>
        do {
            try Task.checkCancellation()
            result = .success(try performSave(request, folder: access.folder))
        } catch { result = .failure(error) }
        await folders.release(access.token)
        // Do not check cancellation after publication: the caller must receive the
        // successful binding even if cancellation arrived during lease cleanup.
        return try result.get()
    }

    func ensureCurrentMonthFolder(in folder: AuthorizedFolder) async throws {
        try Task.checkCancellation()
        let access = try await folders.acquire(folder)
        let result: Result<Void, any Error>
        do {
            try Task.checkCancellation()
            let directory = try CaptureDirectory(folder: access.folder, month: CaptureNaming(firstSavedAt: now()).monthFolder)
            directory.close()
            result = .success(())
        } catch { result = .failure(error) }
        await folders.release(access.token)
        try result.get()
    }

    // Synchronous helper: executes on the writer actor's calling thread, with
    // local non-Sendable descriptors/coordinator confined to this stack frame.
    // It reads only immutable Sendable dependencies, not actor-owned mutable state.
    private nonisolated func performSave(_ request: CaptureWriteRequest, folder: AuthorizedFolder) throws -> CaptureWriteOutcome {
        let timestamp = request.binding?.firstSavedAt ?? now()
        let naming = CaptureNaming(firstSavedAt: timestamp)
        let directory = try CaptureDirectory(folder: folder, month: naming.monthFolder)
        defer { directory.close() }
        let initialName = request.binding?.fileURL.lastPathComponent ?? naming.filename()
        let initialURL = directory.url.appendingPathComponent(initialName)
        if let binding = request.binding {
            guard binding.fileURL.isFileURL,
                  binding.fileURL.standardizedFileURL.path == initialURL.path,
                  validFilename(initialName, naming: naming) else { throw CaptureWriteError.invalidBinding }
        }
        let bytes = Data(request.text.utf8)
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var outcome: Result<CaptureWriteOutcome, any Error>?
        coordinator.coordinate(writingItemAt: initialURL, options: .forReplacing, error: &coordinationError) { coordinatedURL in
            outcome = Result {
                guard coordinatedURL.standardizedFileURL.path == initialURL.path else { throw CaptureWriteError.pathChanged }
                try Task.checkCancellation()
                try directory.validateLocation()
                return try directory.withStaged(bytes, afterChunk: { try hooks.observe(.wroteChunk, initialURL) }) { stage in
                    try hooks.observe(.staged, initialURL)
                    var target = initialName
                    if let binding = request.binding {
                        _ = try directory.inspect(initialName)
                        try hooks.observe(.inspected, initialURL)
                        // Re-read after staging and any intervening external change,
                        // not just from cached metadata or a pre-coordination read.
                        let current = try directory.inspect(initialName)
                        try Task.checkCancellation()
                        try directory.validateLocation()
                        if let current {
                            if current.bytes == binding.baseline {
                                try stage.setPermissions(current.permissions)
                                try stage.replace(initialName)
                            } else {
                                target = try allocateCopy(stage, naming: naming)
                            }
                        } else if try !stage.publishExclusively(initialName) {
                            // A competing creator won after the missing-file check.
                            // Never replace its new file without inspecting it again.
                            throw CaptureWriteError.pathChanged
                        }
                    } else {
                        try Task.checkCancellation()
                        target = try allocateNew(stage, naming: naming)
                    }
                    return .saved(CaptureBinding(folder: folder,
                                                  fileURL: directory.url.appendingPathComponent(target),
                                                  firstSavedAt: timestamp, baseline: bytes))
                }
            }
        }
        // If publication ran, its receipt takes precedence: never report a
        // committed write as failed merely because later bookkeeping complains.
        if let outcome { return try outcome.get() }
        if let coordinationError { throw coordinationError }
        throw CaptureWriteError.coordinationFailed
    }

    private nonisolated func allocateNew(_ stage: StagedCapture, naming: CaptureNaming) throws -> String {
        if try stage.publishExclusively(naming.filename()) { return naming.filename() }
        return try allocateCopy(stage, naming: naming)
    }

    private nonisolated func allocateCopy(_ stage: StagedCapture, naming: CaptureNaming) throws -> String {
        var suffix: UInt = 1
        while true {
            try Task.checkCancellation()
            let name = naming.filename(suffix: suffix)
            if try stage.publishExclusively(name) { return name }
            guard suffix < UInt.max else { throw CaptureWriteError.nameExhausted }
            suffix += 1
        }
    }

    private nonisolated func validFilename(_ name: String, naming: CaptureNaming) -> Bool {
        if name == naming.filename() { return true }
        let prefix = naming.timestampStem + "_"
        guard name.hasPrefix(prefix), name.hasSuffix(".md") else { return false }
        let digits = name.dropFirst(prefix.count).dropLast(3)
        guard let suffix = UInt(digits), suffix > 0 else { return false }
        return name == naming.filename(suffix: suffix)
    }
}

/// Descriptors prevent symlink substitution from redirecting writes. These helper
/// objects are confined to one synchronous accessor and never cross an actor boundary.
nonisolated private final class CaptureDirectory {
    let folder: AuthorizedFolder
    let month: String
    let url: URL
    private(set) var rootFD: Int32 = -1
    private(set) var monthFD: Int32 = -1
    private var monthStat = stat()

    init(folder: AuthorizedFolder, month: String) throws {
        self.folder = folder
        self.month = month
        self.url = folder.url.appendingPathComponent(month, isDirectory: true)
        rootFD = Darwin.open(folder.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard rootFD >= 0 else { throw posixFailure("Open project folder") }
        do {
            var root = stat()
            guard fstat(rootFD, &root) == 0 else { throw posixFailure("Inspect project folder") }
            guard UInt64(truncatingIfNeeded: root.st_dev) == folder.identity.device,
                  root.st_ino == folder.identity.inode else { throw CaptureWriteError.pathChanged }
            if mkdirat(rootFD, month, 0o755) != 0 && errno != EEXIST { throw posixFailure("Create month folder") }
            monthFD = openat(rootFD, month, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard monthFD >= 0 else { throw posixFailure("Open month folder") }
            guard fstat(monthFD, &monthStat) == 0 else { throw posixFailure("Inspect month folder") }
            try validateLocation()
        } catch { close(); throw error }
    }

    func close() {
        if monthFD >= 0 { Darwin.close(monthFD); monthFD = -1 }
        if rootFD >= 0 { Darwin.close(rootFD); rootFD = -1 }
    }

    func validateLocation() throws {
        var root = stat()
        var monthInfo = stat()
        guard fstatat(AT_FDCWD, folder.path, &root, AT_SYMLINK_NOFOLLOW) == 0,
              fstatat(rootFD, month, &monthInfo, AT_SYMLINK_NOFOLLOW) == 0 else {
            throw CaptureWriteError.pathChanged
        }
        guard root.st_mode & S_IFMT == S_IFDIR,
              UInt64(truncatingIfNeeded: root.st_dev) == folder.identity.device,
              root.st_ino == folder.identity.inode,
              monthInfo.st_mode & S_IFMT == S_IFDIR,
              monthInfo.st_dev == monthStat.st_dev, monthInfo.st_ino == monthStat.st_ino else {
            throw CaptureWriteError.pathChanged
        }
    }

    struct ExistingFile {
        let bytes: Data
        let permissions: mode_t
    }

    func inspect(_ name: String) throws -> ExistingFile? {
        let fd = openat(monthFD, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        if fd < 0 {
            if errno == ENOENT { return nil }
            throw posixFailure("Read existing capture")
        }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? handle.close() }
        var info = stat()
        guard fstat(fd, &info) == 0 else { throw posixFailure("Inspect existing capture") }
        guard info.st_mode & S_IFMT == S_IFREG else { throw CaptureWriteError.unsafeTarget }
        return ExistingFile(bytes: try handle.readToEnd() ?? Data(), permissions: info.st_mode & 0o777)
    }

    func withStaged<Result>(_ bytes: Data, afterChunk: () throws -> Void,
                            operation: (StagedCapture) throws -> Result) throws -> Result {
        let stage = try StagedCapture(directory: self, bytes: bytes, afterChunk: afterChunk)
        defer { stage.cleanup() }
        return try operation(stage)
    }
}

nonisolated private final class StagedCapture {
    private let directory: CaptureDirectory
    private let name = ".BrainDump-staging-\(UUID().uuidString).tmp"
    private var published = false

    init(directory: CaptureDirectory, bytes: Data, afterChunk: () throws -> Void) throws {
        self.directory = directory
        let fd = openat(directory.monthFD, name, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw posixFailure("Stage capture") }
        do {
            try bytes.withUnsafeBytes { buffer in
                var offset = 0
                while offset < buffer.count {
                    try Task.checkCancellation()
                    let count = Darwin.write(fd, buffer.baseAddress!.advanced(by: offset), min(65_536, buffer.count - offset))
                    if count < 0 {
                        if errno == EINTR { continue }
                        throw posixFailure("Write staged capture")
                    }
                    guard count > 0 else { throw CaptureWriteError.io(operation: "Write staged capture", code: EIO) }
                    offset += count
                    try afterChunk()
                }
            }
            guard fsync(fd) == 0 else { throw posixFailure("Flush staged capture") }
        } catch {
            Darwin.close(fd)
            unlinkat(directory.monthFD, name, 0)
            throw error
        }
        if Darwin.close(fd) != 0 {
            let failure = posixFailure("Close staged capture")
            cleanup()
            throw failure
        }
    }

    func cleanup() {
        if !published { unlinkat(directory.monthFD, name, 0) }
    }

    func setPermissions(_ permissions: mode_t) throws {
        let fd = openat(directory.monthFD, name, O_WRONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw posixFailure("Open staged capture") }
        defer { Darwin.close(fd) }
        guard fchmod(fd, permissions) == 0 else { throw posixFailure("Preserve capture permissions") }
    }

    func publishExclusively(_ target: String) throws -> Bool {
        try directory.validateLocation()
        if renameatx_np(directory.monthFD, name, directory.monthFD, target, UInt32(RENAME_EXCL)) == 0 {
            published = true
            return true
        }
        if errno == EEXIST { return false }
        throw posixFailure("Publish new capture")
    }

    func replace(_ target: String) throws {
        try directory.validateLocation()
        guard renameat(directory.monthFD, name, directory.monthFD, target) == 0 else {
            throw posixFailure("Replace capture")
        }
        published = true
    }
}

nonisolated private func posixFailure(_ operation: String) -> CaptureWriteError {
    .io(operation: operation, code: errno)
}
