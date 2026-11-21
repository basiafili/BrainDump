import Foundation
import Darwin
import Testing

nonisolated private extension CaptureWriteOutcome {
    var savedBinding: CaptureBinding? {
        if case .saved(let binding) = self { return binding }
        return nil
    }
}

nonisolated private struct CaptureFixture {
    let root: URL
    let folder: AuthorizedFolder
    let service: FolderAuthorizationService
    let date: Date
    var naming: CaptureNaming { CaptureNaming(firstSavedAt: date) }
    var month: URL { root.appendingPathComponent(naming.monthFolder, isDirectory: true) }

    static func make() async throws -> Self {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("BrainDumpWriterTests-\(UUID().uuidString)", isDirectory: true)
            .standardizedFileURL.resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let service = FolderAuthorizationService()
        do {
            let folder = try await service.authorizeSelection(root)
            let date = try #require(ISO8601DateFormatter().date(from: "2026-11-30T23:59:59Z"))
            return Self(root: root, folder: folder, service: service, date: date)
        } catch { try? FileManager.default.removeItem(at: root); throw error }
    }
    func cleanup() { try? FileManager.default.removeItem(at: root) }
    func writer(hooks: CaptureWriteHooks = CaptureWriteHooks()) -> CaptureFileWriter {
        CaptureFileWriter(folders: service, now: { date }, hooks: hooks)
    }
    func request(_ text: String, binding: CaptureBinding? = nil) -> CaptureWriteRequest {
        CaptureWriteRequest(text: text, projectFolder: folder, binding: binding)
    }
    func save(_ text: String, with writer: CaptureFileWriter, binding: CaptureBinding? = nil) async throws -> CaptureBinding {
        try #require(try await writer.save(request(text, binding: binding)).savedBinding)
    }
    func entries() throws -> [String] { try FileManager.default.contentsOfDirectory(atPath: month.path).sorted() }
}

@Suite("Capture filesystem writer", .timeLimit(.minutes(1)))
nonisolated struct CaptureFileWriterTests {
    @Test func exactUTF8AndEmptyNoOps() async throws {
        let f = try await CaptureFixture.make(); defer { f.cleanup() }
        let writer = f.writer()
        #expect(try await writer.save(f.request(" \t\n")) == .empty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: f.root.path).isEmpty)
        let text = "  # Żółć 🧠\n\n"
        let saved = try await f.save(text, with: writer)
        #expect(saved.fileURL.lastPathComponent == "2026-11-30_23-59-59.md")
        #expect(saved.fileURL.deletingLastPathComponent().lastPathComponent == "2026-11")
        #expect(try Data(contentsOf: saved.fileURL) == Data(text.utf8))
        #expect(saved.baseline == Data(text.utf8) && saved.firstSavedAt == f.date)
        #expect(try await writer.save(f.request("\n ", binding: saved)) == .empty)
        #expect(try Data(contentsOf: saved.fileURL) == saved.baseline)
        #expect(try f.entries() == [saved.fileURL.lastPathComponent])
    }

    @Test func projectCreationCanPrepareMonthWithoutCapture() async throws {
        let f = try await CaptureFixture.make(); defer { f.cleanup() }
        try await f.writer().ensureCurrentMonthFolder(in: f.folder)
        #expect(try f.entries().isEmpty)
    }

    @Test func updatesRetainTimestampPathAndPermissions() async throws {
        let f = try await CaptureFixture.make(); defer { f.cleanup() }
        let first = try await f.save("first", with: f.writer())
        try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: first.fileURL.path)
        let laterWriter = CaptureFileWriter(folders: f.service, now: { f.date.addingTimeInterval(86400) })
        let updated = try await f.save("updated", with: laterWriter, binding: first)
        #expect(updated.fileURL == first.fileURL && updated.firstSavedAt == first.firstSavedAt)
        #expect(try Data(contentsOf: first.fileURL) == Data("updated".utf8))
        let attributes = try FileManager.default.attributesOfItem(atPath: updated.fileURL.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o640)
        #expect(try f.entries().count == 1)
    }

    @Test func collisionSuffixGrowsBeyondNinetyNine() async throws {
        let f = try await CaptureFixture.make(); defer { f.cleanup() }
        try FileManager.default.createDirectory(at: f.month, withIntermediateDirectories: false)
        for suffix in UInt(0)...100 {
            try Data("external \(suffix)".utf8).write(to: f.month.appendingPathComponent(f.naming.filename(suffix: suffix)))
        }
        let saved = try await f.save("capture", with: f.writer())
        #expect(saved.fileURL.lastPathComponent == f.naming.filename(suffix: 101))
        #expect(try String(contentsOf: f.month.appendingPathComponent(f.naming.filename()), encoding: .utf8) == "external 0")
    }

    @Test func externalEditsCreateCopiesAndRebindWithoutStackedSuffixes() async throws {
        let f = try await CaptureFixture.make(); defer { f.cleanup() }
        let writer = f.writer()
        let first = try await f.save("original", with: writer)
        try Data("outside".utf8).write(to: first.fileURL, options: .atomic)
        let copy = try await f.save("my edits", with: writer, binding: first)
        #expect(copy.fileURL.lastPathComponent == f.naming.filename(suffix: 1))
        #expect(try String(contentsOf: first.fileURL, encoding: .utf8) == "outside")
        let updated = try await f.save("later", with: writer, binding: copy)
        #expect(updated.fileURL == copy.fileURL)
        try Data("outside again".utf8).write(to: copy.fileURL, options: .atomic)
        let secondCopy = try await f.save("my later edits", with: writer, binding: updated)
        #expect(secondCopy.fileURL.lastPathComponent == f.naming.filename(suffix: 2))
        #expect(secondCopy.firstSavedAt == first.firstSavedAt)
        #expect(try String(contentsOf: copy.fileURL, encoding: .utf8) == "outside again")
    }

    @Test func externalRenameRecreatesOriginalNameWithoutFollowingIt() async throws {
        let f = try await CaptureFixture.make(); defer { f.cleanup() }
        let writer = f.writer()
        let first = try await f.save("before rename", with: writer)
        let renamed = f.month.appendingPathComponent("renamed.md")
        try FileManager.default.moveItem(at: first.fileURL, to: renamed)
        let saved = try await f.save("after rename", with: writer, binding: first)
        #expect(saved.fileURL == first.fileURL)
        #expect(try String(contentsOf: renamed, encoding: .utf8) == "before rename")
        #expect(try String(contentsOf: saved.fileURL, encoding: .utf8) == "after rename")
    }

    @Test func deletedMonthIsRecreatedForTheBoundFile() async throws {
        let f = try await CaptureFixture.make(); defer { f.cleanup() }
        let first = try await f.save("old", with: f.writer())
        try FileManager.default.removeItem(at: f.month)
        let later = CaptureFileWriter(folders: f.service, now: { f.date.addingTimeInterval(86400) })
        let saved = try await f.save("restored", with: later, binding: first)
        #expect(saved.fileURL == first.fileURL && saved.firstSavedAt == first.firstSavedAt)
        #expect(try String(contentsOf: saved.fileURL, encoding: .utf8) == "restored")
    }

    @Test func changedProjectFolderDoesNotRedirectBoundCapture() async throws {
        let old = try await CaptureFixture.make(); defer { old.cleanup() }
        let new = try await CaptureFixture.make(); defer { new.cleanup() }
        let writer = old.writer()
        let first = try await old.save("first", with: writer)
        let request = CaptureWriteRequest(text: "updated at old path", projectFolder: new.folder, binding: first)
        let saved = try #require(try await writer.save(request).savedBinding)
        #expect(saved.fileURL == first.fileURL && saved.folder == old.folder)
        #expect(try FileManager.default.contentsOfDirectory(atPath: new.root.path).isEmpty)
    }

    @Test(arguments: [false, true])
    func failedStagingPublishesNothingAndPreservesOldCapture(bound: Bool) async throws {
        let f = try await CaptureFixture.make(); defer { f.cleanup() }
        let original = bound ? try await f.save("original", with: f.writer()) : nil
        let hooks = CaptureWriteHooks { phase, _ in
            if phase == .staged { throw POSIXError(.ENOSPC) }
        }
        await #expect(throws: POSIXError.self) { try await f.writer(hooks: hooks).save(f.request("new text", binding: original)) }
        if let original {
            #expect(try Data(contentsOf: original.fileURL) == original.baseline)
            #expect(try f.entries() == [original.fileURL.lastPathComponent])
        } else { #expect(try f.entries().isEmpty) }
    }

    @Test func externalEditBetweenInspectionAndPublicationIsCopied() async throws {
        let f = try await CaptureFixture.make(); defer { f.cleanup() }
        let first = try await f.save("original", with: f.writer())
        let hooks = CaptureWriteHooks { phase, url in
            if phase == .inspected { try Data("racing external edit".utf8).write(to: url, options: .atomic) }
        }
        let copy = try await f.save("mine", with: f.writer(hooks: hooks), binding: first)
        #expect(copy.fileURL != first.fileURL)
        #expect(try String(contentsOf: first.fileURL, encoding: .utf8) == "racing external edit")
        #expect(try String(contentsOf: copy.fileURL, encoding: .utf8) == "mine")
    }

    @Test func competingCreatorCannotBeOverwritten() async throws {
        let f = try await CaptureFixture.make(); defer { f.cleanup() }
        let hooks = CaptureWriteHooks { phase, url in
            if phase == .staged { try Data("competing creator".utf8).write(to: url, options: .withoutOverwriting) }
        }
        let saved = try await f.save("mine", with: f.writer(hooks: hooks))
        #expect(saved.fileURL.lastPathComponent == f.naming.filename(suffix: 1))
        #expect(try String(contentsOf: f.month.appendingPathComponent(f.naming.filename()), encoding: .utf8) == "competing creator")
    }

    @Test func symlinkMonthCannotRedirectWrites() async throws {
        let f = try await CaptureFixture.make(); defer { f.cleanup() }
        let outside = try await CaptureFixture.make(); defer { outside.cleanup() }
        try FileManager.default.createSymbolicLink(at: f.month, withDestinationURL: outside.root)
        await #expect(throws: (any Error).self) { try await f.writer().save(f.request("mine")) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: outside.root.path).isEmpty)
    }

    @Test func symlinkCaptureCannotModifyAnUnrelatedFile() async throws {
        let f = try await CaptureFixture.make(); defer { f.cleanup() }
        let writer = f.writer()
        let first = try await f.save("original", with: writer)
        let unrelated = f.root.appendingPathComponent("unrelated.md")
        try Data("unrelated".utf8).write(to: unrelated)
        try FileManager.default.removeItem(at: first.fileURL)
        try FileManager.default.createSymbolicLink(at: first.fileURL, withDestinationURL: unrelated)
        await #expect(throws: (any Error).self) { try await writer.save(f.request("mine", binding: first)) }
        #expect(try String(contentsOf: unrelated, encoding: .utf8) == "unrelated")
        #expect(try f.entries() == [first.fileURL.lastPathComponent])
    }

    @Test func directoryAtCapturePathFailsSafely() async throws {
        let f = try await CaptureFixture.make(); defer { f.cleanup() }
        let first = try await f.save("original", with: f.writer())
        try FileManager.default.removeItem(at: first.fileURL)
        try FileManager.default.createDirectory(at: first.fileURL, withIntermediateDirectories: false)
        await #expect(throws: (any Error).self) { try await f.writer().save(f.request("mine", binding: first)) }
        #expect(try f.entries() == [first.fileURL.lastPathComponent])
    }

    @Test(.enabled(if: geteuid() != 0))
    func unreadableCaptureIsNotReplaced() async throws {
        let f = try await CaptureFixture.make(); defer { f.cleanup() }
        let first = try await f.save("original", with: f.writer())
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: first.fileURL.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: first.fileURL.path) }
        await #expect(throws: (any Error).self) { try await f.writer().save(f.request("mine", binding: first)) }
        #expect(try f.entries() == [first.fileURL.lastPathComponent])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: first.fileURL.path)
        #expect(try Data(contentsOf: first.fileURL) == first.baseline)
    }

    @Test func independentWriterActorsAllocateDistinctFiles() async throws {
        let f = try await CaptureFixture.make(); defer { f.cleanup() }
        let writers = (0..<8).map { _ in f.writer() }
        let bindings = try await withThrowingTaskGroup(of: CaptureBinding.self) { group in
            for index in 0..<24 {
                group.addTask { try await f.save("capture \(index)", with: writers[index % writers.count]) }
            }
            var results: [CaptureBinding] = []
            for try await binding in group { results.append(binding) }
            return results
        }
        #expect(Set(bindings.map(\.fileURL)).count == 24)
        for binding in bindings { #expect(try Data(contentsOf: binding.fileURL) == binding.baseline) }
        #expect(try f.entries().count == 24)
    }

    @Test func independentWritersCoordinateUpdatesToTheSameBaseline() async throws {
        let f = try await CaptureFixture.make(); defer { f.cleanup() }
        let first = try await f.save("original", with: f.writer())
        async let a = f.save("A", with: f.writer(), binding: first)
        async let b = f.save("B", with: f.writer(), binding: first)
        let results = try await [a, b]
        #expect(Set(results.map(\.fileURL)).count == 2)
        for binding in results { #expect(try Data(contentsOf: binding.fileURL) == binding.baseline) }
        #expect(try f.entries().count == 2)
    }

    @Test func malformedBindingCannotWriteOutsideItsFolder() async throws {
        let f = try await CaptureFixture.make(); defer { f.cleanup() }
        let outside = try await CaptureFixture.make(); defer { outside.cleanup() }
        let otherURL = outside.root.appendingPathComponent(f.naming.filename())
        try Data("outside".utf8).write(to: otherURL)
        let forged = CaptureBinding(folder: f.folder, fileURL: otherURL, firstSavedAt: f.date, baseline: Data("outside".utf8))
        await #expect(throws: (any Error).self) { try await f.writer().save(f.request("mine", binding: forged)) }
        #expect(try String(contentsOf: otherURL, encoding: .utf8) == "outside")
    }

    @Test func monthReplacementDuringSaveFailsWithoutPublishingIntoReplacement() async throws {
        let f = try await CaptureFixture.make(); defer { f.cleanup() }
        let first = try await f.save("original", with: f.writer())
        let moved = f.root.appendingPathComponent("moved-month", isDirectory: true)
        let hooks = CaptureWriteHooks { phase, _ in
            if phase == .staged {
                try FileManager.default.moveItem(at: f.month, to: moved)
                try FileManager.default.createDirectory(at: f.month, withIntermediateDirectories: false)
            }
        }
        await #expect(throws: (any Error).self) { try await f.writer(hooks: hooks).save(f.request("mine", binding: first)) }
        #expect(try f.entries().isEmpty)
        #expect(try String(contentsOf: moved.appendingPathComponent(first.fileURL.lastPathComponent), encoding: .utf8) == "original")
        #expect(try FileManager.default.contentsOfDirectory(atPath: moved.path) == [first.fileURL.lastPathComponent])
    }

    @Test func partialStagingFailureRemovesTemporaryBytesAndPreservesOriginal() async throws {
        let f = try await CaptureFixture.make(); defer { f.cleanup() }
        let original = try await f.save("original", with: f.writer())
        let hooks = CaptureWriteHooks { phase, _ in
            if phase == .wroteChunk { throw POSIXError(.ENOSPC) }
        }
        let text = String(repeating: "x", count: 150_000)
        await #expect(throws: POSIXError.self) {
            try await f.writer(hooks: hooks).save(f.request(text, binding: original))
        }
        #expect(try Data(contentsOf: original.fileURL) == original.baseline)
        #expect(try f.entries() == [original.fileURL.lastPathComponent])
    }

    @Test func cancellationAfterPublicationStillReturnsSuccessfulBinding() async throws {
        let f = try await CaptureFixture.make(); defer { f.cleanup() }
        let gate = ReleasePausedFolderAuthorization(base: f.service)
        let writer = CaptureFileWriter(folders: gate, now: { f.date })
        let saving = Task { @concurrent in try await writer.save(f.request("committed")) }
        await gate.waitForRelease()
        // Publication is complete, but release has not returned to the writer.
        let expectedURL = f.month.appendingPathComponent(f.naming.filename())
        #expect(try String(contentsOf: expectedURL, encoding: .utf8) == "committed")
        saving.cancel()
        await gate.resumeRelease()
        let saved = try #require(try await saving.value.savedBinding)
        #expect(saved.fileURL == expectedURL && saved.baseline == Data("committed".utf8))
    }
}

private actor ReleasePausedFolderAuthorization: FolderAuthorizing {
    let base: FolderAuthorizationService
    private var pending: CheckedContinuation<Void, Never>?
    private var observer: CheckedContinuation<Void, Never>?

    init(base: FolderAuthorizationService) { self.base = base }
    func authorizeSelection(_ url: URL) async throws -> AuthorizedFolder { try await base.authorizeSelection(url) }
    func inspect(_ folder: AuthorizedFolder) async throws -> AuthorizedFolder { try await base.inspect(folder) }
    func acquire(_ folder: AuthorizedFolder) async throws -> FolderAccess { try await base.acquire(folder) }
    func release(_ token: UUID) async {
        await withCheckedContinuation { continuation in
            pending = continuation
            observer?.resume()
            observer = nil
        }
        await base.release(token)
    }
    func waitForRelease() async {
        if pending != nil { return }
        await withCheckedContinuation { observer = $0 }
    }
    func resumeRelease() { pending?.resume(); pending = nil }
}
