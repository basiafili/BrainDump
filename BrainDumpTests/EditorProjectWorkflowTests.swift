import Foundation
import Testing

@Suite("Editor project workflows", .timeLimit(.minutes(1)))
@MainActor
struct EditorProjectWorkflowTests {
    @Test func removalFailureLeavesRegistrationAndEveryWindowIntact() async throws {
        let f = try await CoordinatorFixture.make(automatic: false); defer { f.cleanup() }
        let first = try await f.openFirst(), second = try await f.openFirst()
        let unrelated = try await f.coordinator.registerWindow(for: f.second.id)
        let coordinator = f.coordinator, projectID = f.first.id
        coordinator.updateText(first.id, text: "first")
        coordinator.updateText(second.id, text: "second")
        let removing = Task { @concurrent in await coordinator.removeProject(projectID) }
        await f.writer.waitForCall(1)
        #expect(first.isReadOnly && second.isReadOnly && !unrelated.isReadOnly)
        #expect(coordinator.isProjectBusy(projectID) && !coordinator.isProjectBusy(f.second.id))
        #expect(coordinator.updateText(unrelated.id, text: "other window remains usable"))
        #expect(coordinator.renameProject(projectID, to: "Blocked") == .busy)
        await #expect(throws: EditorWorkflowError.busy) { try await f.openFirst() }
        await f.writer.succeed(0)
        await f.writer.waitForCall(2); await f.writer.fail(1)
        #expect(await removing.value.isFailure)
        #expect(f.projects.projects.contains(f.first) && coordinator.sessions.count == 3)
        #expect(!first.isReadOnly && !second.isReadOnly)
        #expect(!coordinator.isProjectBusy(projectID))
        #expect(first.binding?.baseline == Data("first".utf8) && second.binding == nil)
        #expect(!coordinator.windowDidClose(first.id))
    }

    @Test func removalCommitsOnlyAfterSavesAndSuppressesAutomaticReplacementActivation() async throws {
        let f = try await CoordinatorFixture.make(); defer { f.cleanup() }
        let first = try await f.openFirst(), empty = try await f.openFirst()
        let other = try await f.coordinator.registerWindow(for: f.second.id)
        f.coordinator.updateText(first.id, text: "first")
        #expect(f.projects.lastActiveID == f.first.id)
        let result = await f.coordinator.removeProject(f.first.id)
        #expect(result.windowIDs == [first.id, empty.id])
        #expect(await f.writer.requestCount == 1)
        #expect(!f.projects.projects.contains(where: { $0.id == f.first.id }))
        #expect(f.projects.lastActiveID == nil && !f.projects.recentIDs.contains(f.first.id))
        #expect(first.isReadOnly && empty.isReadOnly && !other.isReadOnly)
        f.coordinator.activate(other.id) // Native focus change caused by internal closes.
        #expect(f.projects.lastActiveID == nil)
        f.coordinator.activate(other.id, userInitiated: true)
        #expect(f.projects.lastActiveID == f.second.id)
        #expect(f.coordinator.windowDidClose(first.id) && f.coordinator.windowDidClose(empty.id))
        #expect(f.coordinator.sessions.count == 1)
    }

    @Test func keepOpenFolderChangePreservesBindingsAndUsesNewFolderForUnboundCapture() async throws {
        let f = try await CoordinatorFixture.make(); defer { f.cleanup() }
        let bound = try await f.openFirst(), unbound = try await f.openFirst()
        f.coordinator.updateText(bound.id, text: "saved")
        let original = try #require(await f.coordinator.save(bound.id).savedBinding)
        f.coordinator.updateText(bound.id, text: "edited bound")
        f.coordinator.updateText(unbound.id, text: "unbound")
        let recent = f.projects.recentIDs, last = f.projects.lastActiveID
        let newURL = URL(fileURLWithPath: "/fixtures/repaired")
        #expect(await f.coordinator.changeProjectFolder(f.first.id, selectedFolder: newURL, mode: .keepOpen) == .completed)
        #expect(bound.binding == original && bound.text == "edited bound" && unbound.text == "unbound")
        #expect(bound.project.folder.path == newURL.path && unbound.project.folder.path == newURL.path)
        #expect(!bound.isReadOnly && !unbound.isReadOnly && f.coordinator.sessions.count == 2)
        #expect(await f.writer.requestCount == 1)
        #expect(f.projects.recentIDs == recent && f.projects.lastActiveID == last)
        _ = await f.coordinator.save(bound.id)
        _ = await f.coordinator.save(unbound.id)
        let requests = await f.writer.requests
        #expect(requests[1].binding == original && requests[1].projectFolder.path == newURL.path)
        #expect(bound.binding?.folder == original.folder)
        #expect(requests[2].binding == nil && requests[2].projectFolder.path == newURL.path)
        #expect(unbound.binding?.folder.path == newURL.path)
    }

    @Test func saveAndClosePreservesClearedBoundFileAndSavesOthersToOldFolder() async throws {
        let f = try await CoordinatorFixture.make(); defer { f.cleanup() }
        let cleared = try await f.openFirst(), dirty = try await f.openFirst(), empty = try await f.openFirst()
        f.coordinator.updateText(cleared.id, text: "old baseline")
        let old = try #require(await f.coordinator.save(cleared.id).savedBinding)
        f.coordinator.updateText(cleared.id, text: " \n")
        f.coordinator.updateText(dirty.id, text: "save at old folder")
        let newURL = URL(fileURLWithPath: "/fixtures/new")
        let result = await f.coordinator.changeProjectFolder(f.first.id, selectedFolder: newURL, mode: .saveAndClose)
        #expect(result.windowIDs == [cleared.id, dirty.id, empty.id])
        #expect(await f.writer.requestCount == 2)
        #expect(cleared.binding == old && cleared.isUnsaved)
        #expect(dirty.binding?.folder == f.first.folder)
        #expect(f.projects.projects.first(where: { $0.id == f.first.id })?.folder.path == newURL.path)
        let allReadOnly = [cleared, dirty, empty].allSatisfy { $0.isReadOnly }
        #expect(allReadOnly)
        await #expect(throws: EditorWorkflowError.busy) { try await f.openFirst() }
        for session in [cleared, dirty, empty] { #expect(f.coordinator.windowDidClose(session.id)) }
        #expect(!f.coordinator.isProjectBusy(f.first.id))
        let reopened = try await f.openFirst()
        #expect(reopened.project.folder.path == newURL.path)
    }

    @Test func invalidFolderAfterSuccessfulSaveDoesNotCloseOrChangeRegistration() async throws {
        let f = try await CoordinatorFixture.make(); defer { f.cleanup() }
        let session = try await f.openFirst()
        f.coordinator.updateText(session.id, text: "saved safely")
        let recent = f.projects.recentIDs, last = f.projects.lastActiveID
        let result = await f.coordinator.changeProjectFolder(f.first.id, selectedFolder: f.second.folder.url, mode: .saveAndClose)
        #expect(result.isFailure)
        #expect(f.projects.projects.first(where: { $0.id == f.first.id }) == f.first)
        #expect(session.binding?.baseline == Data("saved safely".utf8) && !session.isReadOnly)
        #expect(!f.coordinator.windowDidClose(session.id))
        #expect(f.projects.recentIDs == recent && f.projects.lastActiveID == last)
    }

    @Test func committedRenameUpdatesEveryTitleWithoutChangingCaptureOrUsage() async throws {
        let f = try await CoordinatorFixture.make(); defer { f.cleanup() }
        let first = try await f.openFirst(), second = try await f.openFirst()
        f.coordinator.updateText(first.id, text: "saved")
        let binding = try #require(await f.coordinator.save(first.id).savedBinding)
        let generation = first.captureID, recent = f.projects.recentIDs, last = f.projects.lastActiveID
        #expect(f.coordinator.renameProject(f.first.id, to: "Renamed") == .completed)
        #expect(first.title.hasPrefix("Renamed - BrainDump - ") && second.title == "Renamed - BrainDump - New Capture")
        #expect(first.binding == binding && first.captureID == generation)
        #expect(f.projects.recentIDs == recent && f.projects.lastActiveID == last)
        #expect(f.coordinator.renameProject(f.first.id, to: f.second.name).isFailure)
        #expect(first.project.name == "Renamed")
    }
}
