import Foundation
import Testing

@Suite("Atomic project settings", .timeLimit(.minutes(1)))
@MainActor
struct ProjectSettingsTransactionTests {
    private func replacement(_ f: CoordinatorFixture) async throws -> AuthorizedFolder {
        try await f.projects.authorizeReplacementFolder(f.first.id, selectedFolder: URL(fileURLWithPath: "/fixtures/replacement"))
    }

    @Test func nameAndFolderCommitTogetherAndUpdateEveryTitle() async throws {
        let f = try await CoordinatorFixture.make(); defer { f.cleanup() }
        let first = try await f.openFirst(), second = try await f.openFirst()
        f.coordinator.updateText(first.id, text: "original")
        let binding = try #require(await f.coordinator.save(first.id).savedBinding)
        let recent = f.projects.recentIDs, active = f.projects.lastActiveID
        let change = ProjectSettingsChange(projectID: f.first.id, name: "  New name  ", folder: try await replacement(f))
        #expect(await f.coordinator.applyProjectSettings(change, mode: .keepOpen) == .completed)
        let updated = try #require(f.projects.projects.first { $0.id == f.first.id })
        #expect(updated.name == "New name" && updated.folder.path == "/fixtures/replacement")
        #expect(first.project == updated && second.project == updated)
        #expect(first.binding == binding && first.text == "original")
        #expect(first.title.hasPrefix("New name - BrainDump - ") && second.title == "New name - BrainDump - New Capture")
        #expect(f.projects.recentIDs == recent && f.projects.lastActiveID == active)
        let reopened = try ProjectStore(defaults: f.defaults, folders: f.folders)
        #expect(reopened.projects.first { $0.id == f.first.id } == updated)
    }

    @Test func invalidNameOrFolderDoesNotSaveOrPartiallyRename() async throws {
        let f = try await CoordinatorFixture.make(); defer { f.cleanup() }
        let session = try await f.openFirst()
        f.coordinator.updateText(session.id, text: "Keep this")
        let duplicate = ProjectSettingsChange(projectID: f.first.id, name: "New name", folder: f.second.folder)
        #expect(await f.coordinator.applyProjectSettings(duplicate, mode: .saveAndClose).isFailure)
        let invalidName = ProjectSettingsChange(projectID: f.first.id, name: " ", folder: try await replacement(f))
        #expect(await f.coordinator.applyProjectSettings(invalidName, mode: .saveAndClose).isFailure)
        #expect(f.projects.projects.first { $0.id == f.first.id } == f.first)
        #expect(session.project == f.first && session.text == "Keep this" && session.binding == nil)
        #expect(await f.writer.requestCount == 0)
        #expect(!session.isReadOnly && !f.coordinator.isProjectBusy(f.first.id))
    }

    @Test func laterSaveFailureKeepsAllMetadataAndWindowsButEarlierWriteStaysSaved() async throws {
        let f = try await CoordinatorFixture.make(failureIndices: [1]); defer { f.cleanup() }
        let first = try await f.openFirst(), second = try await f.openFirst()
        f.coordinator.updateText(first.id, text: "first")
        f.coordinator.updateText(second.id, text: "second")
        let change = ProjectSettingsChange(projectID: f.first.id, name: "New name", folder: try await replacement(f))
        #expect(await f.coordinator.applyProjectSettings(change, mode: .saveAndClose).isFailure)
        #expect(f.projects.projects.first { $0.id == f.first.id } == f.first)
        #expect(first.binding?.baseline == Data("first".utf8) && second.binding == nil)
        #expect(first.project == f.first && second.project == f.first)
        #expect(!first.isReadOnly && !second.isReadOnly && f.coordinator.sessions.count == 2)
    }

    @Test(arguments: [true, false]) func postSaveRevalidationOrCancellationCannotCommitMetadata(cancel: Bool) async throws {
        let f = try await CoordinatorFixture.make(automatic: false); defer { f.cleanup() }
        let session = try await f.openFirst()
        f.coordinator.updateText(session.id, text: "Committed old-folder write")
        let folder = try await replacement(f)
        let change = ProjectSettingsChange(projectID: f.first.id, name: "New name", folder: folder)
        let task = Task { await f.coordinator.applyProjectSettings(change, mode: .saveAndClose) }
        await f.writer.waitForCall(1)
        #expect(session.isReadOnly && session.project == f.first)
        if cancel { task.cancel() }
        else { await f.folders.fail(folder.path, with: .movedFolder) }
        await f.writer.succeed(0)
        let result = await task.value
        if cancel { #expect(result == .cancelled) } else { #expect(result.isFailure) }
        #expect(f.projects.projects.first { $0.id == f.first.id } == f.first)
        #expect(session.binding != nil && !session.isReadOnly && session.project == f.first)
    }

    @Test func mixedCaptureStatesSaveAtOldDestinationsBeforeAtomicClosePermission() async throws {
        let f = try await CoordinatorFixture.make(); defer { f.cleanup() }
        let clean = try await f.openFirst(), dirty = try await f.openFirst(), cleared = try await f.openFirst(), unbound = try await f.openFirst()
        for session in [clean, dirty, cleared] {
            f.coordinator.updateText(session.id, text: "baseline \(session.id)")
            _ = await f.coordinator.save(session.id)
        }
        let cleanBinding = try #require(clean.binding), clearedBinding = try #require(cleared.binding)
        f.coordinator.updateText(dirty.id, text: "dirty bound")
        f.coordinator.updateText(cleared.id, text: " \n ")
        f.coordinator.updateText(unbound.id, text: "new unbound")
        let change = ProjectSettingsChange(projectID: f.first.id, name: "Moved", folder: try await replacement(f))
        #expect(await f.coordinator.applyProjectSettings(change, mode: .saveAndClose).windowIDs == [clean.id, dirty.id, cleared.id, unbound.id])
        #expect(clean.binding?.fileURL == cleanBinding.fileURL && cleared.binding == clearedBinding)
        for session in [clean, dirty, cleared, unbound] {
            #expect(session.binding?.folder == f.first.folder)
            #expect(session.isReadOnly && session.project.name == "Moved")
        }
        let requests = await f.writer.requests
        #expect(requests.count == 6) // Three initial saves, then clean/dirty/unbound. Cleared is no-op.
        #expect(requests.suffix(3).allSatisfy { $0.projectFolder == f.first.folder })
        for session in [clean, dirty, cleared, unbound] { #expect(f.coordinator.windowDidClose(session.id)) }
        #expect(!f.coordinator.isProjectBusy(f.first.id))
    }

    @Test func unavailableProjectCanBeRenamedWithoutFolderInspection() async throws {
        let f = try await CoordinatorFixture.make(); defer { f.cleanup() }
        await f.folders.fail(f.first.folder.path, with: .inaccessibleFolder)
        await f.projects.refreshAvailability()
        let change = ProjectSettingsChange(projectID: f.first.id, name: "Unavailable but renamed", folder: nil)
        #expect(await f.coordinator.applyProjectSettings(change, mode: .keepOpen) == .completed)
        #expect(f.projects.projects.first { $0.id == f.first.id }?.name == change.name)
        #expect(f.projects.availability[f.first.id]?.isAvailable == false)
        #expect(await f.writer.requestCount == 0)
    }

    @Test func competingNameCommitDuringSaveCannotPartiallyApplySettings() async throws {
        let f = try await CoordinatorFixture.make(automatic: false); defer { f.cleanup() }
        let session = try await f.openFirst()
        f.coordinator.updateText(session.id, text: "saved before conflict")
        let change = ProjectSettingsChange(projectID: f.first.id, name: "Contested", folder: try await replacement(f))
        let task = Task { await f.coordinator.applyProjectSettings(change, mode: .saveAndClose) }
        await f.writer.waitForCall(1)
        try f.projects.rename(f.second.id, to: "Contested")
        await f.writer.succeed(0)
        #expect(await task.value.isFailure)
        #expect(f.projects.projects.first { $0.id == f.first.id } == f.first)
        #expect(session.binding != nil && session.project == f.first && !session.isReadOnly)
        #expect(!f.coordinator.isProjectBusy(f.first.id))
    }

    @Test func keepOpenWaitsForPendingFirstSaveWithoutStartingAnExtraWrite() async throws {
        let f = try await CoordinatorFixture.make(automatic: false); defer { f.cleanup() }
        let session = try await f.openFirst()
        f.coordinator.updateText(session.id, text: "snapshot")
        let saving = Task { await f.coordinator.save(session.id) }
        await f.writer.waitForCall(1)
        let change = ProjectSettingsChange(projectID: f.first.id, name: "After pending save", folder: try await replacement(f))
        let editing = Task { await f.coordinator.applyProjectSettings(change, mode: .keepOpen) }
        await waitUntilObserved { f.coordinator.isProjectBusy(f.first.id) }
        #expect(session.project == f.first && !session.isReadOnly)
        f.coordinator.updateText(session.id, text: "newer text")
        await f.writer.succeed(0)
        #expect(await saving.value.savedBinding?.folder == f.first.folder)
        #expect(await editing.value == .completed)
        #expect(session.binding?.folder == f.first.folder && session.project.folder.path == "/fixtures/replacement")
        #expect(session.text == "newer text" && session.isUnsaved)
        #expect(await f.writer.requestCount == 1)
    }
}
