import Foundation
import Testing

@Suite("Editor save workflows", .timeLimit(.minutes(1)))
@MainActor
struct EditorSaveWorkflowTests {
    @Test func registrationUsesStableIndependentSessionIdentity() async throws {
        let f = try await CoordinatorFixture.make(); defer { f.cleanup() }
        let first = try await f.openFirst()
        let second = try await f.openFirst()
        #expect(first.id != second.id && first.project.id == second.project.id)
        #expect(f.coordinator.sessions[first.id] === first)
        #expect(first.title == "First - BrainDump - New Capture")
        #expect(f.projects.recentIDs == [f.first.id])
        #expect(f.projects.lastActiveID == f.first.id)
        await f.folders.fail(f.second.folder.path, with: .inaccessibleFolder)
        await #expect(throws: ProjectError.inaccessibleFolder) { try await f.coordinator.registerWindow(for: f.second.id) }
        #expect(f.coordinator.sessions.count == 2 && f.projects.lastActiveID == f.first.id)
    }

    @Test func typingDuringManualSavePreservesNewerEdits() async throws {
        let f = try await CoordinatorFixture.make(automatic: false); defer { f.cleanup() }
        let session = try await f.openFirst()
        let coordinator = f.coordinator, id = session.id
        coordinator.updateText(id, text: "snapshot")
        let saving = Task { @concurrent in await coordinator.save(id) }
        await f.writer.waitForCall(1)
        #expect(session.isSaving && !session.isReadOnly)
        #expect(coordinator.updateText(id, text: "newer text"))
        await f.writer.succeed(0)
        let receipt = try #require(await saving.value.savedBinding)
        #expect(receipt.baseline == Data("snapshot".utf8))
        #expect(session.binding == receipt && session.text == "newer text")
        #expect(session.isUnsaved && !session.isSaving)
    }

    @Test func queuedSavesFreezeTextButUseFreshBindings() async throws {
        let f = try await CoordinatorFixture.make(automatic: false); defer { f.cleanup() }
        let session = try await f.openFirst()
        let coordinator = f.coordinator, id = session.id
        coordinator.updateText(id, text: "A")
        let first = Task { @concurrent in await coordinator.save(id) }
        await f.writer.waitForCall(1)
        coordinator.updateText(id, text: "B")
        let second = Task { @concurrent in await coordinator.save(id) }
        await waitUntilObserved { session.pendingSaveCount == 2 }
        coordinator.updateText(id, text: "C")
        #expect(await f.writer.requestCount == 1)
        await f.writer.succeed(0)
        let firstReceipt = try #require(await first.value.savedBinding)
        await f.writer.waitForCall(2)
        let request = await f.writer.requests[1]
        #expect(request.text == "B" && request.binding == firstReceipt)
        await f.writer.succeed(1)
        let secondReceipt = try #require(await second.value.savedBinding)
        #expect(secondReceipt.fileURL == firstReceipt.fileURL)
        #expect(session.binding?.baseline == Data("B".utf8) && session.text == "C")
        #expect(session.isUnsaved && session.pendingSaveCount == 0)
    }

    @Test func newCaptureWaitsForManualSaveThenSavesLatestLockedText() async throws {
        let f = try await CoordinatorFixture.make(automatic: false); defer { f.cleanup() }
        let session = try await f.openFirst()
        let coordinator = f.coordinator, id = session.id
        let oldCaptureID = session.captureID, oldFocusID = session.focusRequestID
        coordinator.updateText(id, text: "A")
        let saving = Task { @concurrent in await coordinator.save(id) }
        await f.writer.waitForCall(1)
        coordinator.updateText(id, text: "B")
        let resetting = Task { @concurrent in await coordinator.newCapture(id) }
        await waitUntilObserved { session.pendingSaveCount == 2 }
        #expect(session.isReadOnly && !coordinator.updateText(id, text: "must not enter"))
        #expect(await coordinator.save(id) == .busy)
        #expect(await coordinator.prepareClose(id) == .busy)
        await f.writer.succeed(0)
        let prior = try #require(await saving.value.savedBinding)
        await f.writer.waitForCall(2)
        let request = await f.writer.requests[1]
        #expect(request.text == "B" && request.binding == prior)
        await f.writer.succeed(1)
        #expect(await resetting.value == .completed)
        #expect(session.text.isEmpty && session.binding == nil && !session.isReadOnly)
        #expect(session.captureID != oldCaptureID && session.focusRequestID != oldFocusID)
    }

    @Test func failedResetPreservesTextBindingIdentityAndRetry() async throws {
        let f = try await CoordinatorFixture.make(failureIndices: [1]); defer { f.cleanup() }
        let session = try await f.openFirst()
        f.coordinator.updateText(session.id, text: "saved")
        let original = try #require(await f.coordinator.save(session.id).savedBinding)
        f.coordinator.updateText(session.id, text: "edited")
        let generation = session.captureID, focus = session.focusRequestID
        #expect(await f.coordinator.newCapture(session.id).isFailure)
        #expect(session.text == "edited" && session.binding == original)
        #expect(session.captureID == generation && session.focusRequestID == focus && !session.isReadOnly)
        #expect(session.issue?.kind == .save)
        #expect(await f.coordinator.save(session.id).savedBinding != nil)
        #expect(session.issue == nil && !session.isUnsaved)
    }

    @Test func clearedBoundSaveDoesNotEraseBaselineAndEmptyCloseIsAllowed() async throws {
        let f = try await CoordinatorFixture.make(); defer { f.cleanup() }
        let session = try await f.openFirst()
        f.coordinator.updateText(session.id, text: "saved")
        let binding = try #require(await f.coordinator.save(session.id).savedBinding)
        f.coordinator.updateText(session.id, text: " \n")
        #expect(session.isEmpty && session.isUnsaved)
        #expect(await f.coordinator.save(session.id) == .empty)
        #expect(session.binding == binding && session.isUnsaved)
        #expect(await f.writer.requestCount == 1)
        #expect(await f.coordinator.prepareClose(session.id) == .closeWindows([session.id]))
        #expect(session.isReadOnly && f.coordinator.sessions[session.id] === session)
        #expect(await f.writer.requestCount == 1)
        #expect(f.coordinator.windowDidClose(session.id))
        #expect(f.coordinator.sessions.isEmpty)
    }

    @Test func unsolicitedClosureCannotDiscardSession() async throws {
        let f = try await CoordinatorFixture.make(); defer { f.cleanup() }
        let session = try await f.openFirst()
        f.coordinator.updateText(session.id, text: "keep")
        #expect(!f.coordinator.windowDidClose(session.id))
        #expect(f.coordinator.sessions[session.id] === session && session.text == "keep")
        #expect(f.coordinator.lastIssue?.kind == .state)
        #expect(await f.coordinator.prepareClose(session.id).succeeded)
        #expect(f.coordinator.windowDidClose(session.id))
        #expect(await f.coordinator.save(session.id) == .missingSession)
        let replacement = try await f.openFirst()
        #expect(replacement.id != session.id && replacement.binding == nil)
    }

    @Test func cancellingQueuedSaveDoesNotCancelItsPredecessor() async throws {
        let f = try await CoordinatorFixture.make(automatic: false); defer { f.cleanup() }
        let session = try await f.openFirst()
        let coordinator = f.coordinator, id = session.id
        coordinator.updateText(id, text: "A")
        let first = Task { @concurrent in await coordinator.save(id) }
        await f.writer.waitForCall(1)
        coordinator.updateText(id, text: "B")
        let second = Task { @concurrent in await coordinator.save(id) }
        await waitUntilObserved { session.pendingSaveCount == 2 }
        second.cancel()
        await f.writer.succeed(0)
        #expect(await first.value.savedBinding != nil)
        #expect(await second.value == .cancelled)
        #expect(await f.writer.requestCount == 1)
        #expect(session.binding?.baseline == Data("A".utf8) && session.text == "B")
        #expect(session.isUnsaved && !session.isSaving)
    }

    @Test func copyReceiptUpdatesBindingWithoutChangingTitleTimestamp() async throws {
        let f = try await CoordinatorFixture.make(automatic: false); defer { f.cleanup() }
        let session = try await f.openFirst()
        let coordinator = f.coordinator, id = session.id
        coordinator.updateText(id, text: "first")
        let first = Task { @concurrent in await coordinator.save(id) }
        await f.writer.waitForCall(1); await f.writer.succeed(0)
        let original = try #require(await first.value.savedBinding)
        let title = session.title
        coordinator.updateText(id, text: "second")
        let second = Task { @concurrent in await coordinator.save(id) }
        await f.writer.waitForCall(2); await f.writer.succeed(1, asCopy: true)
        let copy = try #require(await second.value.savedBinding)
        #expect(copy.fileURL != original.fileURL && session.binding == copy)
        #expect(session.title == title)
        #expect(!title.contains(CaptureNaming(firstSavedAt: copy.firstSavedAt).timestampStem))
    }

    @Test(arguments: [false, true])
    func lateCompletionCannotContaminateAReplacementCapture(fails: Bool) async throws {
        let f = try await CoordinatorFixture.make(automatic: false); defer { f.cleanup() }
        let session = try await f.openFirst()
        let coordinator = f.coordinator, id = session.id
        coordinator.updateText(id, text: "old capture")
        let saving = Task { @concurrent in await coordinator.save(id) }
        await f.writer.waitForCall(1)
        // Defensive integration boundary: simulate a capture replacement outside
        // the normal transition path, which would otherwise wait for this save.
        session.resetCapture()
        coordinator.updateText(id, text: "replacement capture")
        let newCaptureID = session.captureID
        if fails { await f.writer.fail(0) } else { await f.writer.succeed(0) }
        let result = await saving.value
        if fails { #expect(result.isFailure) } else { #expect(result.savedBinding != nil) }
        #expect(session.captureID == newCaptureID && session.text == "replacement capture")
        #expect(session.binding == nil && session.issue == nil && coordinator.lastIssue == nil)
        #expect(session.isUnsaved && !session.isSaving)
    }

    @Test func cancelledManualSaveStillReportsItsCompletedWrite() async throws {
        let f = try await CoordinatorFixture.make(automatic: false); defer { f.cleanup() }
        let session = try await f.openFirst()
        let coordinator = f.coordinator, id = session.id
        coordinator.updateText(id, text: "committed")
        let saving = Task { @concurrent in await coordinator.save(id) }
        await f.writer.waitForCall(1)
        saving.cancel()
        await f.writer.succeed(0)
        let receipt = try #require(await saving.value.savedBinding)
        #expect(session.binding == receipt && !session.isUnsaved && !session.isSaving)
    }
}
