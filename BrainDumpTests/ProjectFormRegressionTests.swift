import Foundation
import Testing

@Suite("Project form regressions", .timeLimit(.minutes(1)))
@MainActor
struct ProjectFormRegressionTests {
    @Test func successfulRegistrationCannotBecomeItsOwnDuplicateError() async throws {
        let f = try await CoordinatorFixture.make(); defer { f.cleanup() }
        let draft = NewProjectDraft(originatingEditorID: nil, explanation: nil, openInNewWindow: false)
        draft.name = "New project"
        await draft.choose(URL(fileURLWithPath: "/fixtures/new-form"), folders: f.folders, projects: f.projects)
        #expect(draft.nameValidationMessage(projects: f.projects) == nil)
        draft.isWorking = true
        let result = await f.coordinator.createProject(name: draft.name, selectedFolder: try #require(draft.selectedURL),
                                                       reusing: nil, folderPreparer: ControlledProjectFolderPreparer())
        guard case .opened = result else { Issue.record("Expected successful creation"); return }
        // The store now rejects this name for a different project, while the
        // in-flight/successful form must neither show nor announce that error.
        #expect(f.projects.nameValidationMessage(draft.name) == ProjectError.duplicateName.localizedDescription)
        #expect(draft.nameValidationMessage(projects: f.projects) == nil)
        draft.completeCreation()
        #expect(draft.didCreateProject && draft.closeRequested && !draft.isWorking)
        #expect(draft.nameValidationMessage(projects: f.projects) == nil)
        #expect(draft.creationError == nil)
    }

    @Test func actualDuplicatesAreStillRejectedInAnUnsubmittedForm() async throws {
        let f = try await CoordinatorFixture.make(); defer { f.cleanup() }
        let draft = NewProjectDraft(originatingEditorID: nil, explanation: nil, openInNewWindow: false)
        draft.name = " first "
        #expect(draft.nameValidationMessage(projects: f.projects) == ProjectError.duplicateName.localizedDescription)
        #expect(!draft.didCreateProject && !draft.closeRequested)
    }

    @Test(arguments: [ProjectWindowState.Window.newProject, .openProject])
    func projectCheckboxSurvivesRelaunchWithoutChangingGlobalPreferenceOrRegistry(window: ProjectWindowState.Window) async throws {
        let f = try await CoordinatorFixture.make(); defer { f.cleanup() }
        let state = ProjectWindowState(window: window, defaults: f.defaults, initialValue: f.projects.alwaysOpenInNewWindow)
        #expect(!state.openInNewWindow)
        #expect(state.choice(defaultingTo: true)) // A later global default, before any local choice.
        let original = f.projects.projects
        state.remember(true)
        let reopened = try ProjectStore(defaults: f.defaults, folders: f.folders)
        let nextWindow = ProjectWindowState(window: window, defaults: f.defaults, initialValue: reopened.alwaysOpenInNewWindow)
        #expect(nextWindow.openInNewWindow)
        #expect(!reopened.alwaysOpenInNewWindow)
        #expect(reopened.projects == original && reopened.recentIDs.isEmpty && reopened.lastActiveID == nil)
        // A remembered unchecked choice also takes precedence over global ON.
        nextWindow.remember(false)
        try reopened.setAlwaysOpenInNewWindow(true)
        let laterWindow = ProjectWindowState(window: window, defaults: f.defaults, initialValue: reopened.alwaysOpenInNewWindow)
        #expect(!laterWindow.openInNewWindow && reopened.alwaysOpenInNewWindow)
    }

    @Test func formCheckboxChoicesAreIndependentFromEachOtherAndGlobalPreference() async throws {
        let f = try await CoordinatorFixture.make(); defer { f.cleanup() }
        let create = ProjectWindowState(window: .newProject, defaults: f.defaults, initialValue: false)
        let open = ProjectWindowState(window: .openProject, defaults: f.defaults, initialValue: false)
        create.remember(true)
        #expect(create.openInNewWindow && !open.openInNewWindow)
        open.remember(true)
        create.remember(false)
        #expect(!create.openInNewWindow && open.openInNewWindow)
        let reopened = ProjectWindowState(window: .openProject, defaults: f.defaults, initialValue: false)
        #expect(reopened.openInNewWindow)
        #expect(!f.projects.alwaysOpenInNewWindow)
    }

    @Test func renamedFolderOffersOpenProjectRecoveryAndCanBeExplicitlyRepaired() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("BrainDumpRepair-\(UUID().uuidString)")
        let original = root.appendingPathComponent("Original"), moved = root.appendingPathComponent("Renamed")
        try FileManager.default.createDirectory(at: original, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let existing = Data("User content must stay intact".utf8)
        try existing.write(to: original.appendingPathComponent("existing.md"))
        let suite = "BrainDumpRepairTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let folders = FolderAuthorizationService()
        let projects = try ProjectStore(defaults: defaults, folders: folders)
        let project = try await projects.register(name: "Repair", selectedFolder: original)
        try projects.recordOpened(project.id)
        let recent = projects.recentIDs
        let writer = CaptureFileWriter(folders: folders)
        let coordinator = EditorCoordinator(projects: projects, writer: writer)
        try FileManager.default.moveItem(at: original, to: moved)
        guard case .openProject(let explanation) = await StartupRouter.resolve(projects: projects, coordinator: coordinator) else {
            Issue.record("Expected Open Project error, not a replacement project or New Project"); return
        }
        #expect(!explanation.isEmpty && coordinator.sessions.isEmpty)
        #expect(projects.projects.first?.folder.path == original.path)
        #expect(projects.reachableProjects.isEmpty)
        #expect(await coordinator.changeProjectFolder(project.id, selectedFolder: moved, mode: .keepOpen) == .completed)
        #expect(projects.projects.first?.id == project.id && projects.projects.first?.folder.path == moved.path)
        #expect(projects.recentIDs == recent && projects.lastActiveID == project.id)
        guard case .editor(let id) = await StartupRouter.resolve(projects: projects, coordinator: coordinator) else {
            Issue.record("Expected repaired project to reopen"); return
        }
        #expect(coordinator.sessions[id]?.project.id == project.id)
        #expect(coordinator.sessions[id]?.text.isEmpty == true)
        #expect(try Data(contentsOf: moved.appendingPathComponent("existing.md")) == existing)
    }

    @Test func nestedProjectsCanEachRepairTheirOwnRegistrationAfterParentRename() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("BrainDumpNestedRepair-\(UUID().uuidString)")
        let parent = root.appendingPathComponent("TestProject2")
        let original = parent.appendingPathComponent("TestProject3")
        let child = original.appendingPathComponent("TestProject45")
        let moved = parent.appendingPathComponent("TestProject34")
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "BrainDumpNestedRepairTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let folders = FolderAuthorizationService()
        let projects = try ProjectStore(defaults: defaults, folders: folders)
        let parentRecord = try await projects.register(name: "Parent", selectedFolder: parent)
        let renamedRecord = try await projects.register(name: "Renamed", selectedFolder: original)
        let childRecord = try await projects.register(name: "Child", selectedFolder: child)
        try projects.recordOpened(childRecord.id)
        let coordinator = EditorCoordinator(projects: projects, writer: CaptureFileWriter(folders: folders))
        try FileManager.default.moveItem(at: original, to: moved)
        #expect(await coordinator.changeProjectFolder(childRecord.id, selectedFolder: moved.appendingPathComponent("TestProject45"), mode: .keepOpen) == .completed)
        #expect(await coordinator.changeProjectFolder(renamedRecord.id, selectedFolder: moved, mode: .keepOpen) == .completed)
        #expect(projects.projects.count == 3)
        #expect(projects.projects.first(where: { $0.id == renamedRecord.id })?.folder.path == moved.path)
        #expect(projects.lastActiveID == childRecord.id && projects.recentIDs == [childRecord.id])
        // The same choice for a DIFFERENT registration must still be rejected.
        let wrongTarget = await coordinator.changeProjectFolder(parentRecord.id, selectedFolder: moved, mode: .keepOpen)
        guard case .failed(let issue) = wrongTarget else { Issue.record("Expected a genuine duplicate-folder rejection"); return }
        let conflict = ProjectFolderConflictError(projectID: renamedRecord.id, projectName: renamedRecord.name, registeredPath: moved.path)
        #expect(issue.message == conflict.localizedDescription)
        await #expect(throws: conflict) {
            try await projects.changeFolder(parentRecord.id, selectedFolder: moved)
        }
        #expect(projects.projects.first(where: { $0.id == parentRecord.id })?.folder.path == parent.path)
    }
}
