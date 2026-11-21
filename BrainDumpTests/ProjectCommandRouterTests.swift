import Foundation
import Testing

@Suite("Project command routing", .timeLimit(.minutes(1)))
@MainActor
struct ProjectCommandRouterTests {
    @Test func auxiliaryFocusUsesMostRecentEditorWithoutChangingUsage() async throws {
        let f = try await CoordinatorFixture.make(); defer { f.cleanup() }
        let router = ProjectCommandRouter(projects: f.projects, coordinator: f.coordinator)
        let first = try await f.openFirst()
        let second = try await f.coordinator.registerWindow(for: f.second.id)
        f.coordinator.activate(first.id)
        let recent = f.projects.recentIDs
        f.coordinator.deactivate(first.id) // Help or a project form becomes key.
        #expect(router.targetEditorID == first.id && f.coordinator.activeEditorID == nil)
        #expect(f.projects.recentIDs == recent)
        f.coordinator.updateText(first.id, text: "Save before reuse")
        f.coordinator.deactivate(first.id)
        let request = router.menuRequest(for: f.second.id)
        f.coordinator.activate(second.id)
        #expect(await router.open(request) == .reused(first.id))
        #expect(first.project.id == f.second.id && first.text.isEmpty)
        #expect(second.project.id == f.second.id && second.binding == nil)
        #expect(await f.writer.requests.first?.text == "Save before reuse")
    }

    @Test func globalOnCreatesWindowAndRequestSnapshotsPreference() async throws {
        let f = try await CoordinatorFixture.make(); defer { f.cleanup() }
        let router = ProjectCommandRouter(projects: f.projects, coordinator: f.coordinator)
        let original = try await f.openFirst()
        f.coordinator.updateText(original.id, text: "Leave this editor alone")
        try f.projects.setAlwaysOpenInNewWindow(true)
        let request = router.menuRequest(for: f.second.id)
        try f.projects.setAlwaysOpenInNewWindow(false)
        guard case .opened(let id) = await router.open(request) else { Issue.record("Expected separate window"); return }
        #expect(id != original.id && f.coordinator.sessions[id]?.project.id == f.second.id)
        #expect(original.text == "Leave this editor alone" && original.binding == nil)
        #expect(await f.writer.requestCount == 0)
    }

    @Test func explicitFormReuseIgnoresGlobalOn() async throws {
        let f = try await CoordinatorFixture.make(); defer { f.cleanup() }
        let original = try await f.openFirst()
        let router = ProjectCommandRouter(projects: f.projects, coordinator: f.coordinator)
        try f.projects.setAlwaysOpenInNewWindow(true)
        let request = ProjectOpenRequest(projectID: f.second.id, originatingEditorID: original.id, inNewWindow: false)
        #expect(await router.open(request) == .reused(original.id))
        #expect(f.coordinator.sessions.count == 1 && original.project.id == f.second.id)
    }

    @Test func noEditorCreatesOneEvenWhenGlobalOff() async throws {
        let f = try await CoordinatorFixture.make(); defer { f.cleanup() }
        let router = ProjectCommandRouter(projects: f.projects, coordinator: f.coordinator)
        #expect(router.canNewCapture && !router.canSave)
        guard case .opened(let id) = await router.open(router.menuRequest(for: f.second.id)) else {
            Issue.record("Expected new editor"); return
        }
        #expect(f.coordinator.sessions.count == 1 && f.coordinator.sessions[id]?.project.id == f.second.id)
        #expect(f.projects.lastActiveID == f.second.id && f.projects.recentIDs == [f.second.id])
    }

    @Test func closedOriginFallsBackToMostRecentSurvivingEditor() async throws {
        let f = try await CoordinatorFixture.make(); defer { f.cleanup() }
        let router = ProjectCommandRouter(projects: f.projects, coordinator: f.coordinator)
        let origin = try await f.openFirst()
        let surviving = try await f.coordinator.registerWindow(for: f.second.id)
        f.coordinator.activate(surviving.id)
        let request = ProjectOpenRequest(projectID: f.first.id, originatingEditorID: origin.id, inNewWindow: false)
        #expect(await f.coordinator.prepareClose(origin.id).windowIDs == [origin.id])
        #expect(f.coordinator.windowDidClose(origin.id))
        #expect(await router.open(request) == .reused(surviving.id))
        #expect(surviving.project.id == f.first.id)
    }

    @Test func closedOriginWithNoSurvivorsCreatesWindow() async throws {
        let f = try await CoordinatorFixture.make(); defer { f.cleanup() }
        let router = ProjectCommandRouter(projects: f.projects, coordinator: f.coordinator)
        let origin = try await f.openFirst()
        let request = ProjectOpenRequest(projectID: f.second.id, originatingEditorID: origin.id, inNewWindow: false)
        #expect(await f.coordinator.prepareClose(origin.id).windowIDs == [origin.id])
        #expect(f.coordinator.windowDidClose(origin.id))
        guard case .opened(let id) = await router.open(request) else { Issue.record("Expected new editor"); return }
        #expect(id != origin.id && f.coordinator.sessions[id]?.project.id == f.second.id)
    }

    @Test func failedSavePreservesTextBindingProjectAndUsage() async throws {
        let f = try await CoordinatorFixture.make(failureIndices: [0]); defer { f.cleanup() }
        let router = ProjectCommandRouter(projects: f.projects, coordinator: f.coordinator)
        let session = try await f.openFirst()
        f.coordinator.updateText(session.id, text: "Do not discard")
        let recent = f.projects.recentIDs, active = f.projects.lastActiveID
        guard case .failed(let issue) = await router.open(router.menuRequest(for: f.second.id)) else {
            Issue.record("Expected save failure"); return
        }
        #expect(issue.kind == .save)
        #expect(session.text == "Do not discard" && session.project == f.first && session.binding == nil)
        #expect(!session.isReadOnly && f.projects.recentIDs == recent && f.projects.lastActiveID == active)
    }

    @Test func staleReachabilityIsRecheckedBeforeAnySave() async throws {
        let f = try await CoordinatorFixture.make(); defer { f.cleanup() }
        let router = ProjectCommandRouter(projects: f.projects, coordinator: f.coordinator)
        let session = try await f.openFirst()
        f.coordinator.updateText(session.id, text: "Keep draft")
        #expect(router.canOpen(f.second.id, inNewWindow: false))
        await f.folders.fail(f.second.folder.path, with: .movedFolder)
        guard case .failed = await router.open(router.menuRequest(for: f.second.id)) else {
            Issue.record("Expected access failure"); return
        }
        #expect(await f.writer.requestCount == 0)
        #expect(session.project == f.first && session.text == "Keep draft")
        #expect(!router.canOpen(f.second.id, inNewWindow: false))
    }

    @Test func unavailableMenuProjectWithNoEditorsDoesNotOpenAnAlternative() async throws {
        let f = try await CoordinatorFixture.make(); defer { f.cleanup() }
        let router = ProjectCommandRouter(projects: f.projects, coordinator: f.coordinator)
        try f.projects.recordOpened(f.first.id)
        let request = router.menuRequest(for: f.second.id)
        await f.folders.fail(f.second.folder.path, with: .inaccessibleFolder)
        guard case .failed(let issue) = await router.open(request) else {
            Issue.record("Expected inline-presentable project failure"); return
        }
        #expect(issue.kind == .project && issue.sessionID == nil)
        #expect(f.coordinator.sessions.isEmpty)
        #expect(f.projects.lastActiveID == f.first.id && f.projects.recentIDs == [f.first.id])
    }

    @Test func routeCannotRetargetOrOverlapWhileSaving() async throws {
        let f = try await CoordinatorFixture.make(automatic: false); defer { f.cleanup() }
        let router = ProjectCommandRouter(projects: f.projects, coordinator: f.coordinator)
        let first = try await f.openFirst()
        let second = try await f.coordinator.registerWindow(for: f.second.id)
        f.coordinator.updateText(first.id, text: "Snapshot")
        let request = router.menuRequest(for: f.second.id)
        let task = Task { await router.open(request) }
        await f.writer.waitForCall(1)
        #expect(!router.canNewCapture && !router.canSave)
        #expect(!router.canOpen(f.second.id, inNewWindow: false))
        #expect(router.canOpen(f.second.id, inNewWindow: true))
        #expect(await router.open(request) == .busy)
        f.coordinator.activate(second.id)
        await f.writer.succeed(0)
        #expect(await task.value == .reused(first.id))
        #expect(first.project.id == f.second.id && second.binding == nil)
    }

    @Test func recentFilteringAndClearNeverGuessOrUnregisterProjects() async throws {
        let f = try await CoordinatorFixture.make(); defer { f.cleanup() }
        try f.projects.recordOpened(f.first.id)
        try f.projects.recordOpened(f.second.id)
        await f.folders.fail(f.second.folder.path, with: .inaccessibleFolder)
        await f.projects.refreshAvailability()
        #expect(f.projects.recentIDs == [f.second.id, f.first.id])
        #expect(f.projects.recentProjects == [f.first])
        let active = f.projects.lastActiveID
        try f.projects.clearRecent()
        #expect(f.projects.recentIDs.isEmpty && f.projects.projects.count == 2)
        #expect(f.projects.lastActiveID == active)
    }
}
