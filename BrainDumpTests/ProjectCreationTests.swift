import Foundation
import Testing

actor ControlledProjectFolderPreparer: ProjectFolderPreparing {
    let fails: Bool
    private(set) var folders: [AuthorizedFolder] = []
    init(fails: Bool = false) { self.fails = fails }
    func ensureCurrentMonthFolder(in folder: AuthorizedFolder) throws {
        folders.append(folder)
        if fails { throw InjectedSaveError.failed }
    }
}

actor PausedProjectFolderPreparer: ProjectFolderPreparing {
    private var continuation: CheckedContinuation<Void, Never>?
    private var observer: CheckedContinuation<Void, Never>?
    func ensureCurrentMonthFolder(in folder: AuthorizedFolder) async {
        await withCheckedContinuation {
            continuation = $0
            observer?.resume()
            observer = nil
        }
    }
    func waitForCall() async {
        if continuation != nil { return }
        await withCheckedContinuation { observer = $0 }
    }
    func finish() { continuation?.resume(); continuation = nil }
}

@Suite("Create-and-open transaction", .timeLimit(.minutes(1)))
@MainActor
struct ProjectCreationTests {
    @Test func createAndReuseCommitsTogetherAfterSaving() async throws {
        let f = try await CoordinatorFixture.make(automatic: false); defer { f.cleanup() }
        let session = try await f.openFirst()
        f.coordinator.updateText(session.id, text: "Old capture")
        let month = ControlledProjectFolderPreparer()
        let operation = Task { await f.coordinator.createProject(name: "  New project  ", selectedFolder: URL(fileURLWithPath: "/fixtures/new"), reusing: session.id, folderPreparer: month) }
        await f.writer.waitForCall(1)
        #expect(session.isReadOnly && f.coordinator.isCreatingProject)
        #expect(f.projects.projects.count == 2)
        #expect(await month.folders.isEmpty)
        #expect(await f.coordinator.prepareForAppQuit() == .busy)
        await f.writer.succeed(0)
        #expect(await operation.value == .opened(session.id))
        let project = try #require(f.projects.projects.last)
        #expect(project.name == "New project")
        #expect(f.projects.lastActiveID == project.id && f.projects.recentIDs.first == project.id)
        #expect(session.project == project && session.text.isEmpty && session.binding == nil)
        #expect(!session.isReadOnly && !f.coordinator.isCreatingProject)
        #expect(await month.folders == [project.folder])
    }

    @Test(arguments: [true, false]) func failurePreservesRegistryAndOldCapture(saveFails: Bool) async throws {
        let f = try await CoordinatorFixture.make(failureIndices: saveFails ? [0] : []); defer { f.cleanup() }
        let session = try await f.openFirst()
        f.coordinator.updateText(session.id, text: "Keep this")
        let projects = f.projects.projects, recent = f.projects.recentIDs, active = f.projects.lastActiveID
        let capture = session.captureID
        let result = await f.coordinator.createProject(name: "New", selectedFolder: URL(fileURLWithPath: "/fixtures/new"), reusing: session.id, folderPreparer: ControlledProjectFolderPreparer(fails: !saveFails))
        guard case .failed = result else { Issue.record("Expected failure"); return }
        #expect(f.projects.projects == projects && f.projects.recentIDs == recent && f.projects.lastActiveID == active)
        #expect(session.project == f.first && session.text == "Keep this" && session.captureID == capture)
        #expect(!session.isReadOnly && !f.coordinator.isCreatingProject)
        #expect((session.binding == nil) == saveFails)
    }

    @Test func duplicateRejectedBeforeOldCaptureIsSaved() async throws {
        let f = try await CoordinatorFixture.make(); defer { f.cleanup() }
        let session = try await f.openFirst()
        f.coordinator.updateText(session.id, text: "Still editing")
        let result = await f.coordinator.createProject(name: "first", selectedFolder: URL(fileURLWithPath: "/fixtures/new"), reusing: session.id, folderPreparer: ControlledProjectFolderPreparer())
        guard case .failed = result else { Issue.record("Expected duplicate rejection"); return }
        #expect(await f.writer.requestCount == 0)
        #expect(session.text == "Still editing" && !session.isReadOnly)
    }

    @Test func concurrentRegistrationInvalidatesDraftWithoutDiscardingSavedText() async throws {
        let f = try await CoordinatorFixture.make(automatic: false); defer { f.cleanup() }
        let session = try await f.openFirst()
        f.coordinator.updateText(session.id, text: "Keep capture")
        let operation = Task { await f.coordinator.createProject(name: "New", selectedFolder: URL(fileURLWithPath: "/fixtures/new"), reusing: session.id, folderPreparer: ControlledProjectFolderPreparer()) }
        await f.writer.waitForCall(1)
        let competing = try await f.projects.register(name: "NEW", selectedFolder: URL(fileURLWithPath: "/fixtures/other"))
        await f.writer.succeed(0)
        guard case .failed = await operation.value else { Issue.record("Expected commit conflict"); return }
        #expect(f.projects.projects.count == 3 && f.projects.projects.last == competing)
        #expect(f.projects.lastActiveID == f.first.id)
        #expect(session.project == f.first && session.text == "Keep capture" && session.binding != nil)
    }

    @Test func newWindowCreationLeavesOtherEditorsUntouched() async throws {
        let f = try await CoordinatorFixture.make(); defer { f.cleanup() }
        let original = try await f.openFirst()
        f.coordinator.updateText(original.id, text: "Stay here")
        let result = await f.coordinator.createProject(name: "New", selectedFolder: URL(fileURLWithPath: "/fixtures/new"), reusing: nil, folderPreparer: ControlledProjectFolderPreparer())
        guard case .opened(let id) = result else { Issue.record("Expected new session"); return }
        #expect(id != original.id && f.coordinator.sessions.count == 2)
        #expect(original.project == f.first && original.text == "Stay here" && original.binding == nil)
    }

    @Test func changedSelectionIdentityIsRejectedBeforeSaving() async throws {
        let f = try await CoordinatorFixture.make(); defer { f.cleanup() }
        let session = try await f.openFirst()
        f.coordinator.updateText(session.id, text: "Keep this capture")
        let url = URL(fileURLWithPath: "/fixtures/selection")
        let selected = try await f.folders.authorizeSelection(url)
        let other = try await f.folders.authorizeSelection(URL(fileURLWithPath: "/fixtures/other"))
        await f.folders.alias(url.path, to: other)
        let result = await f.coordinator.createProject(name: "New", selectedFolder: url, expectedFolder: selected,
                                                       reusing: session.id, folderPreparer: ControlledProjectFolderPreparer())
        guard case .failed(let issue) = result else { Issue.record("Expected stale selection rejection"); return }
        #expect(issue.message == ProjectError.selectionChanged.localizedDescription)
        #expect(await f.writer.requestCount == 0)
        #expect(f.projects.projects == [f.first, f.second])
        #expect(session.text == "Keep this capture" && session.project == f.first && session.binding == nil)
        #expect(!session.isReadOnly)
    }

    @Test(arguments: [true, false]) func cancelledOrMovedFolderCannotCommitAfterOldCaptureSaved(cancel: Bool) async throws {
        let f = try await CoordinatorFixture.make(); defer { f.cleanup() }
        let session = try await f.openFirst()
        f.coordinator.updateText(session.id, text: "Old text is kept")
        let month = PausedProjectFolderPreparer()
        let operation = Task { await f.coordinator.createProject(name: "New", selectedFolder: URL(fileURLWithPath: "/fixtures/new"), reusing: session.id, folderPreparer: month) }
        await month.waitForCall()
        let binding = try #require(session.binding)
        #expect(binding.baseline == Data("Old text is kept".utf8))
        if cancel { operation.cancel() }
        else { await f.folders.fail("/fixtures/new", with: .movedFolder) }
        await month.finish()
        let result = await operation.value
        if cancel { #expect(result == .cancelled) }
        else { guard case .failed = result else { Issue.record("Expected unavailable folder failure"); return } }
        #expect(f.projects.projects == [f.first, f.second])
        #expect(f.projects.lastActiveID == f.first.id && f.projects.recentIDs == [f.first.id])
        #expect(session.text == "Old text is kept" && session.project == f.first && session.binding == binding)
        #expect(!session.isReadOnly && !f.coordinator.isCreatingProject)
    }

    @Test func realCreateMonthAndRelaunchCaptureLoop() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("BrainDumpCreation-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "BrainDumpCreationTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let folders = FolderAuthorizationService()
        let projects = try ProjectStore(defaults: defaults, folders: folders)
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let writer = CaptureFileWriter(folders: folders, now: { date })
        let coordinator = EditorCoordinator(projects: projects, writer: writer)
        let result = await coordinator.createProject(name: "Notes", selectedFolder: root, reusing: nil, folderPreparer: writer)
        guard case .opened(let id) = result else { Issue.record("Expected created project"); return }
        let month = root.appendingPathComponent(CaptureNaming(firstSavedAt: date).monthFolder)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path) == [month.lastPathComponent])
        #expect(try FileManager.default.contentsOfDirectory(atPath: month.path).isEmpty)
        let session = try #require(coordinator.sessions[id])
        coordinator.updateText(id, text: "# Exact Markdown\n\n-- \"quotes\"\n")
        let binding = try #require(await coordinator.save(id).savedBinding)
        let title = session.title
        coordinator.updateText(id, text: "\n  ")
        #expect(await coordinator.save(id) == .empty)
        #expect(session.title == title)
        #expect(try Data(contentsOf: binding.fileURL) == binding.baseline)
        #expect(await coordinator.newCapture(id) == .completed)
        #expect(await coordinator.prepareClose(id).windowIDs == [id])
        #expect(coordinator.windowDidClose(id))
        let reopened = try ProjectStore(defaults: defaults, folders: folders)
        let nextCoordinator = EditorCoordinator(projects: reopened, writer: writer)
        let destination = await StartupRouter.resolve(projects: reopened, coordinator: nextCoordinator)
        guard case .editor(let nextID) = destination else { Issue.record("Expected persistent last active"); return }
        let next = try #require(nextCoordinator.sessions[nextID])
        #expect(next.text.isEmpty && next.binding == nil && next.project.name == "Notes")
        #expect(try Data(contentsOf: binding.fileURL) == binding.baseline)
    }

    @Test func startupUsesOnlyLastActiveAndPreservesMRU() async throws {
        let f = try await CoordinatorFixture.make(); defer { f.cleanup() }
        try f.projects.recordOpened(f.first.id)
        try f.projects.recordOpened(f.second.id)
        try f.projects.recordEditorActivated(f.first.id)
        let recent = f.projects.recentIDs
        let route = await StartupRouter.resolve(projects: f.projects, coordinator: f.coordinator)
        guard case .editor(let id) = route else { Issue.record("Expected last active"); return }
        #expect(f.coordinator.sessions[id]?.project == f.first)
        #expect(f.projects.recentIDs == recent)
        await f.folders.fail(f.first.folder.path, with: .movedFolder)
        let failed = await StartupRouter.resolve(projects: f.projects, coordinator: f.coordinator)
        guard case .openProject(let reason) = failed else { Issue.record("Must offer project recovery without guessing MRU fallback"); return }
        #expect(reason.contains(ProjectError.movedFolder.localizedDescription))
        #expect(f.coordinator.sessions.count == 1 && f.projects.projects.count == 2)
        #expect(f.projects.recentIDs == recent && f.projects.lastActiveID == f.first.id)
    }

    @Test func explicitNewCaptureWithoutEditorsDoesUpdateMRU() async throws {
        let f = try await CoordinatorFixture.make(); defer { f.cleanup() }
        try f.projects.recordOpened(f.first.id)
        try f.projects.recordOpened(f.second.id)
        try f.projects.recordEditorActivated(f.first.id)
        guard case .editor = await StartupRouter.resolve(projects: f.projects, coordinator: f.coordinator, recordUsage: true) else {
            Issue.record("Expected last active editor"); return
        }
        #expect(f.projects.recentIDs == [f.first.id, f.second.id])
    }

    @Test func noLastActiveNeverGuessesRegisteredProject() async throws {
        let f = try await CoordinatorFixture.make(); defer { f.cleanup() }
        #expect(await StartupRouter.resolve(projects: f.projects, coordinator: f.coordinator) == .newProject(explanation: nil))
        #expect(f.coordinator.sessions.isEmpty)
    }

    @Test func internalFailurePresentationPreservesLastActiveUntilUserEdits() async throws {
        let f = try await CoordinatorFixture.make(failureIndices: [0]); defer { f.cleanup() }
        let first = try await f.openFirst()
        f.coordinator.updateText(first.id, text: "Cannot save")
        let second = try await f.coordinator.registerWindow(for: f.second.id)
        f.coordinator.activate(second.id)
        let recent = f.projects.recentIDs
        #expect(await f.coordinator.prepareForAppQuit().isFailure)
        f.coordinator.activate(first.id, recordUsage: false)
        #expect(f.coordinator.activeEditorID == first.id)
        #expect(f.projects.lastActiveID == f.second.id && f.projects.recentIDs == recent)
        f.coordinator.updateText(first.id, text: "Try again")
        #expect(f.projects.lastActiveID == f.first.id && f.projects.recentIDs == recent)
    }
}
