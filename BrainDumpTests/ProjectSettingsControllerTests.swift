import Foundation
import Testing

@Suite("Settings row commits and drafts", .timeLimit(.minutes(1)))
@MainActor
struct ProjectSettingsControllerTests {
    private func controller(_ f: CoordinatorFixture) -> ProjectSettingsController {
        ProjectSettingsController(projects: f.projects, coordinator: f.coordinator, selectedID: f.first.id)
    }

    private func chooseReplacement(_ controller: ProjectSettingsController) async throws {
        let choice = try #require(controller.beginFolderChoice())
        await controller.acceptFolder(URL(fileURLWithPath: "/fixtures/controller-new"), choice: choice)
    }

    @Test func validRowCommitsImmediatelyAndCancelDiscardsOnlyUnappliedDrafts() async throws {
        let f = try await CoordinatorFixture.make(); defer { f.cleanup() }
        let c = controller(f)
        c.selectedDraft?.name = "Committed first"
        #expect(f.projects.projects.first?.name == "First")
        await c.select(f.second.id)
        #expect(c.selectedID == f.second.id && f.projects.projects.first?.name == "Committed first")
        c.selectedDraft?.name = "Discard this second draft"
        c.cancel()
        #expect(c.requestsClose)
        #expect(f.projects.projects.first { $0.id == f.first.id }?.name == "Committed first")
        #expect(f.projects.projects.first { $0.id == f.second.id }?.name == "Second")
    }

    @Test func invalidRowRemainsListedAndBlocksOKAfterSwitchingToAnotherProject() async throws {
        let f = try await CoordinatorFixture.make(); defer { f.cleanup() }
        let c = controller(f)
        c.selectedDraft?.name = " "
        await c.select(f.second.id)
        #expect(c.selectedID == f.second.id && !c.canOK && c.hasInvalidDrafts)
        #expect(!c.problems(for: f.first.id).isEmpty && f.projects.projects.first?.name == "First")
        c.selectedDraft?.name = "Valid second"
        await c.select(f.first.id)
        #expect(f.projects.projects.first { $0.id == f.second.id }?.name == "Valid second")
        c.selectedDraft?.name = "Fixed first"
        #expect(c.canOK)
        await c.ok()
        #expect(c.requestsClose && f.projects.projects.first?.name == "Fixed first")
    }

    @Test func cancelledFolderDecisionMovesToBAndOKLaterAppliesAllPendingDrafts() async throws {
        let f = try await CoordinatorFixture.make(); defer { f.cleanup() }
        let session = try await f.openFirst()
        f.coordinator.updateText(session.id, text: "unsaved")
        let c = controller(f)
        c.selectedDraft?.name = "Renamed first"
        try await chooseReplacement(c)
        await c.select(f.second.id)
        #expect(c.selectedID == f.second.id && c.decision?.change.projectID == f.first.id)
        #expect(f.projects.projects.first == f.first)
        await c.resolveDecision(nil)
        #expect(c.selectedID == f.second.id && c.drafts[f.first.id]?.hasChanges == true)
        c.selectedDraft?.name = "Renamed second"
        await c.ok()
        #expect(c.decision?.change.projectID == f.first.id && !c.requestsClose)
        await c.resolveDecision(.keepOpen)
        #expect(c.requestsClose)
        #expect(f.projects.projects.first { $0.id == f.first.id }?.name == "Renamed first")
        #expect(f.projects.projects.first { $0.id == f.second.id }?.name == "Renamed second")
        #expect(session.text == "unsaved" && session.binding == nil && !session.isReadOnly)
    }

    @Test func invalidFolderBlocksNameCommitAndKeepsItsProblemAcrossRowChanges() async throws {
        let f = try await CoordinatorFixture.make(); defer { f.cleanup() }
        let c = controller(f)
        c.selectedDraft?.name = "Must not partially apply"
        let choice = try #require(c.beginFolderChoice())
        await c.acceptFolder(f.second.folder.url, choice: choice)
        await c.select(f.second.id)
        #expect(c.selectedID == f.second.id && !c.canOK)
        #expect(!c.problems(for: f.first.id).isEmpty)
        #expect(f.projects.projects.first == f.first)
        await c.select(f.first.id)
        try await chooseReplacement(c)
        await c.ok()
        #expect(c.requestsClose && f.projects.projects.first?.name == "Must not partially apply")
    }

    @Test func removalIgnoresInvalidNameAndFolderDraftsAndClearsOnlyMatchingUsage() async throws {
        let f = try await CoordinatorFixture.make(); defer { f.cleanup() }
        let session = try await f.openFirst()
        f.coordinator.updateText(session.id, text: "Save original capture")
        let c = controller(f)
        c.selectedDraft?.name = " "
        try await chooseReplacement(c)
        c.requestRemoval()
        #expect(c.removal?.name == "First" && c.removal?.folder == f.first.folder)
        await c.confirmRemoval()
        #expect(c.selectedID == nil && !f.projects.projects.contains(where: { $0.id == f.first.id }))
        #expect(f.projects.lastActiveID == nil && !f.projects.recentIDs.contains(f.first.id))
        #expect(session.binding?.folder == f.first.folder && session.project.name == "First")
        #expect(c.takeCloseIDs() == [session.id])
        #expect(f.coordinator.windowDidClose(session.id))
        #expect(f.projects.projects == [f.second])
    }

    @Test func failedRemovalPreservesAllWindowsAndDraftsForRetry() async throws {
        let f = try await CoordinatorFixture.make(failureIndices: [1]); defer { f.cleanup() }
        let first = try await f.openFirst(), second = try await f.openFirst()
        f.coordinator.updateText(first.id, text: "first")
        f.coordinator.updateText(second.id, text: "second")
        let c = controller(f)
        c.selectedDraft?.name = "Do not apply draft"
        c.requestRemoval()
        c.cancelRemoval()
        #expect(f.projects.projects.first == f.first)
        c.requestRemoval()
        await c.confirmRemoval()
        #expect(f.projects.projects.first == f.first && f.coordinator.sessions.count == 2)
        #expect(c.selectedDraft?.name == "Do not apply draft" && c.blockedIssue?.kind == .save)
        #expect(c.closeIDs.isEmpty && !first.isReadOnly && !second.isReadOnly)
        #expect(first.binding != nil && second.binding == nil)
    }

    @Test func unavailableProjectWithoutCapturesCanBeRemoved() async throws {
        let f = try await CoordinatorFixture.make(); defer { f.cleanup() }
        await f.folders.fail(f.first.folder.path, with: .movedFolder)
        await f.projects.refreshAvailability()
        let c = controller(f)
        c.requestRemoval()
        await c.confirmRemoval()
        #expect(!f.projects.projects.contains(where: { $0.id == f.first.id }))
        #expect(await f.writer.requestCount == 0 && c.closeIDs.isEmpty)
    }

    @Test func failedAutomaticRowCommitRetainsDraftAndCanRetryThroughOK() async throws {
        let f = try await CoordinatorFixture.make(failureIndices: [0]); defer { f.cleanup() }
        let session = try await f.openFirst()
        f.coordinator.updateText(session.id, text: "save before moving")
        let c = controller(f)
        c.selectedDraft?.name = "After retry"
        try await chooseReplacement(c)
        await c.select(f.second.id)
        await c.resolveDecision(.saveAndClose)
        #expect(c.selectedID == f.second.id && c.drafts[f.first.id]?.hasChanges == true)
        #expect(c.blockedIssue?.kind == .save && !c.problems(for: f.first.id).isEmpty)
        #expect(f.projects.projects.first == f.first && c.closeIDs.isEmpty && !session.isReadOnly)
        c.blockedIssue = nil
        await c.ok()
        await c.resolveDecision(.saveAndClose)
        #expect(c.requestsClose && f.projects.projects.first?.name == "After retry")
        #expect(c.takeCloseIDs() == [session.id])
        #expect(f.coordinator.windowDidClose(session.id))
    }

    @Test func laterRowCommitRevalidatesConflictsInAnEarlierCancelledDraft() async throws {
        let f = try await CoordinatorFixture.make(); defer { f.cleanup() }
        let session = try await f.openFirst()
        f.coordinator.updateText(session.id, text: "unsaved")
        let c = controller(f)
        let shared = URL(fileURLWithPath: "/fixtures/shared-pending")
        let firstChoice = try #require(c.beginFolderChoice())
        await c.acceptFolder(shared, choice: firstChoice)
        await c.select(f.second.id)
        await c.resolveDecision(nil)
        let secondChoice = try #require(c.beginFolderChoice())
        await c.acceptFolder(shared, choice: secondChoice)
        await c.select(f.first.id) // B commits; A's retained choice now conflicts.
        #expect(f.projects.projects.first { $0.id == f.second.id }?.folder.path == shared.path)
        #expect(c.hasInvalidDrafts && !c.canOK && !c.problems(for: f.first.id).isEmpty)
        #expect(session.project == f.first && session.text == "unsaved")
    }

    @Test func approvedClosesReachThePresentationAdapterBeforeSettingsCanClose() async throws {
        let f = try await CoordinatorFixture.make(); defer { f.cleanup() }
        let session = try await f.openFirst()
        f.coordinator.updateText(session.id, text: "save before close")
        var closed: [UUID] = []
        let c = ProjectSettingsController(projects: f.projects, coordinator: f.coordinator, selectedID: f.first.id,
            onCloseAuthorized: { ids in
                for id in ids { #expect(f.coordinator.windowDidClose(id)) }
                closed.append(contentsOf: ids)
            })
        try await chooseReplacement(c)
        await c.ok()
        await c.resolveDecision(.saveAndClose)
        #expect(c.requestsClose && closed == [session.id] && c.closeIDs.isEmpty)
        #expect(f.coordinator.sessions.isEmpty && !f.coordinator.isProjectBusy(f.first.id))
    }

    @Test func laterOKFailureKeepsEarlierProjectCommitAndCloseApplied() async throws {
        let f = try await CoordinatorFixture.make(failureIndices: [1]); defer { f.cleanup() }
        let first = try await f.openFirst()
        let second = try await f.coordinator.registerWindow(for: f.second.id)
        f.coordinator.updateText(first.id, text: "first capture")
        f.coordinator.updateText(second.id, text: "second capture")
        let c = controller(f)
        c.selectedDraft?.name = "Applied first"
        let a = try #require(c.beginFolderChoice())
        await c.acceptFolder(URL(fileURLWithPath: "/fixtures/pending-a"), choice: a)
        await c.select(f.second.id)
        await c.resolveDecision(nil)
        c.selectedDraft?.name = "Unapplied second"
        let b = try #require(c.beginFolderChoice())
        await c.acceptFolder(URL(fileURLWithPath: "/fixtures/pending-b"), choice: b)
        await c.select(f.first.id)
        await c.resolveDecision(nil)
        await c.ok()
        await c.resolveDecision(.saveAndClose)
        #expect(c.decision?.change.projectID == f.second.id)
        #expect(c.takeCloseIDs() == [first.id])
        #expect(f.coordinator.windowDidClose(first.id))
        await c.resolveDecision(.saveAndClose)
        #expect(f.projects.projects.first { $0.id == f.first.id }?.name == "Applied first")
        #expect(f.projects.projects.first { $0.id == f.second.id } == f.second)
        #expect(c.drafts[f.second.id]?.hasChanges == true && !c.requestsClose)
        #expect(c.blockedIssue?.kind == .save && c.closeIDs.isEmpty)
        #expect(f.coordinator.sessions.count == 1 && !second.isReadOnly && second.text == "second capture")
    }
}
