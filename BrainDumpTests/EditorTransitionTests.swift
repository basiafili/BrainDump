import Foundation
import Testing

@Suite("Editor transitions", .timeLimit(.minutes(1)))
@MainActor
struct EditorTransitionTests {
    @Test func switchSavesOldCaptureThenReusesSessionAndUpdatesUsage() async throws {
        let f = try await CoordinatorFixture.make(); defer { f.cleanup() }
        let session = try await f.openFirst()
        let capture = session.captureID
        f.coordinator.updateText(session.id, text: "old project capture")
        #expect(await f.coordinator.switchProject(session.id, to: f.second.id) == .completed)
        #expect(f.coordinator.sessions.count == 1 && f.coordinator.sessions[session.id] === session)
        #expect(session.project.id == f.second.id && session.text.isEmpty && session.binding == nil)
        #expect(session.captureID != capture && !session.isReadOnly)
        let request = try #require(await f.writer.requests.first)
        #expect(request.text == "old project capture" && request.projectFolder == f.first.folder)
        #expect(f.projects.recentIDs == [f.second.id, f.first.id] && f.projects.lastActiveID == f.second.id)
    }

    @Test func switchSaveFailurePreservesSourceAndUsage() async throws {
        let f = try await CoordinatorFixture.make(failureIndices: [0]); defer { f.cleanup() }
        let session = try await f.openFirst()
        f.coordinator.updateText(session.id, text: "keep")
        let capture = session.captureID
        #expect(await f.coordinator.switchProject(session.id, to: f.second.id).isFailure)
        #expect(session.project.id == f.first.id && session.text == "keep" && session.binding == nil)
        #expect(session.captureID == capture && !session.isReadOnly)
        #expect(session.issue?.kind == .save)
        #expect(f.projects.recentIDs == [f.first.id] && f.projects.lastActiveID == f.first.id)
    }

    @Test func unavailableTargetDoesNotTriggerSourceSave() async throws {
        let f = try await CoordinatorFixture.make(); defer { f.cleanup() }
        let session = try await f.openFirst()
        f.coordinator.updateText(session.id, text: "keep")
        await f.folders.fail(f.second.folder.path, with: .inaccessibleFolder)
        #expect(await f.coordinator.switchProject(session.id, to: f.second.id).isFailure)
        #expect(await f.writer.requestCount == 0)
        #expect(session.project.id == f.first.id && session.text == "keep" && !session.isReadOnly)
        #expect(f.projects.recentIDs == [f.first.id])
    }

    @Test func targetIsRevalidatedAfterOldCaptureSave() async throws {
        let f = try await CoordinatorFixture.make(automatic: false); defer { f.cleanup() }
        let session = try await f.openFirst()
        let coordinator = f.coordinator, id = session.id, target = f.second.id
        coordinator.updateText(id, text: "saved but not switched")
        let switching = Task { @concurrent in await coordinator.switchProject(id, to: target) }
        await f.writer.waitForCall(1)
        await f.folders.fail(f.second.folder.path, with: .inaccessibleFolder)
        await f.writer.succeed(0)
        #expect(await switching.value.isFailure)
        #expect(session.project.id == f.first.id && session.text == "saved but not switched")
        #expect(session.binding?.baseline == Data(session.text.utf8) && !session.isReadOnly)
        #expect(f.projects.recentIDs == [f.first.id] && f.projects.lastActiveID == f.first.id)
    }

    @Test func manualSaveCompletionDoesNotEraseAnUnrelatedSwitchFailure() async throws {
        let f = try await CoordinatorFixture.make(automatic: false); defer { f.cleanup() }
        let session = try await f.openFirst()
        let coordinator = f.coordinator, id = session.id
        coordinator.updateText(id, text: "saved text")
        let saving = Task { @concurrent in await coordinator.save(id) }
        await f.writer.waitForCall(1)
        await f.folders.fail(f.second.folder.path, with: .inaccessibleFolder)
        #expect(await coordinator.switchProject(id, to: f.second.id).isFailure)
        let issue = try #require(session.issue)
        #expect(issue.kind == .project)
        await f.writer.succeed(0)
        #expect(await saving.value.savedBinding != nil)
        #expect(session.issue == issue && session.binding?.baseline == Data("saved text".utf8))
    }

    @Test func quitFailureClosesNothingAndKeepsEarlierSuccessfulSaves() async throws {
        let f = try await CoordinatorFixture.make(automatic: false); defer { f.cleanup() }
        let first = try await f.openFirst(), second = try await f.openFirst()
        let coordinator = f.coordinator
        coordinator.updateText(first.id, text: "first")
        coordinator.updateText(second.id, text: "second")
        let recent = f.projects.recentIDs, last = f.projects.lastActiveID
        let quitting = Task { @concurrent in await coordinator.prepareForAppQuit() }
        await f.writer.waitForCall(1)
        #expect(first.isReadOnly && second.isReadOnly && coordinator.isPreparingQuit)
        #expect(await coordinator.prepareForAppQuit() == .busy)
        await f.writer.succeed(0)
        await f.writer.waitForCall(2)
        #expect(coordinator.sessions.count == 2 && first.isReadOnly)
        await f.writer.fail(1)
        #expect(await quitting.value.isFailure)
        #expect(first.binding?.baseline == Data("first".utf8) && second.binding == nil)
        #expect(first.text == "first" && second.text == "second")
        #expect(!first.isReadOnly && !second.isReadOnly && !coordinator.isPreparingQuit)
        #expect(!coordinator.windowDidClose(first.id) && coordinator.sessions.count == 2)
        #expect(f.projects.recentIDs == recent && f.projects.lastActiveID == last)
    }

    @Test func successfulQuitLocksUntilNativeTerminationWithoutUsageChanges() async throws {
        let f = try await CoordinatorFixture.make(); defer { f.cleanup() }
        let first = try await f.openFirst()
        let second = try await f.coordinator.registerWindow(for: f.second.id)
        let empty = try await f.openFirst()
        f.coordinator.updateText(first.id, text: "first")
        f.coordinator.updateText(second.id, text: "second")
        let recent = f.projects.recentIDs, last = f.projects.lastActiveID
        let result = await f.coordinator.prepareForAppQuit()
        #expect(result.windowIDs == [first.id, second.id, empty.id])
        #expect(await f.writer.requestCount == 2)
        let allReadOnly = [first, second, empty].allSatisfy { $0.isReadOnly }
        #expect(f.coordinator.isPreparingQuit && allReadOnly)
        #expect(await f.coordinator.prepareForAppQuit() == .busy)
        #expect(await f.coordinator.save(first.id) == .busy)
        await #expect(throws: EditorWorkflowError.busy) { try await f.openFirst() }
        f.coordinator.activate(first.id)
        #expect(f.projects.recentIDs == recent && f.projects.lastActiveID == last)
        for session in [first, second, empty] { #expect(f.coordinator.windowDidClose(session.id)) }
        #expect(f.coordinator.sessions.isEmpty)
    }

    @Test func quitWaitsForPendingManualSaveAndThenSavesNewerText() async throws {
        let f = try await CoordinatorFixture.make(automatic: false); defer { f.cleanup() }
        let session = try await f.openFirst()
        let coordinator = f.coordinator, id = session.id
        coordinator.updateText(id, text: "A")
        let manual = Task { @concurrent in await coordinator.save(id) }
        await f.writer.waitForCall(1)
        coordinator.updateText(id, text: "B")
        let quitting = Task { @concurrent in await coordinator.prepareForAppQuit() }
        await waitUntilObserved { session.pendingSaveCount == 2 }
        #expect(!coordinator.updateText(id, text: "too late"))
        await f.writer.succeed(0)
        let firstReceipt = try #require(await manual.value.savedBinding)
        await f.writer.waitForCall(2)
        let next = await f.writer.requests[1]
        #expect(next.text == "B" && next.binding == firstReceipt)
        await f.writer.succeed(1)
        #expect(await quitting.value.windowIDs == [id])
        #expect(session.binding?.baseline == Data("B".utf8))
    }

    nonisolated enum Transition: CaseIterable, Sendable {
        case newCapture, close, quit, switchProject, removeProject, changeFolder
    }

    @Test(arguments: Transition.allCases)
    func cancellationAfterWriteAdoptsReceiptButAbortsTransition(transition: Transition) async throws {
        let f = try await CoordinatorFixture.make(automatic: false); defer { f.cleanup() }
        let session = try await f.openFirst()
        let coordinator = f.coordinator, id = session.id, target = f.second.id, projectID = f.first.id
        let capture = session.captureID, focus = session.focusRequestID
        coordinator.updateText(id, text: "committed text")
        let operation = Task { @concurrent in
            switch transition {
            case .newCapture: await coordinator.newCapture(id)
            case .close: await coordinator.prepareClose(id)
            case .quit: await coordinator.prepareForAppQuit()
            case .switchProject: await coordinator.switchProject(id, to: target)
            case .removeProject: await coordinator.removeProject(projectID)
            case .changeFolder: await coordinator.changeProjectFolder(projectID, selectedFolder: URL(fileURLWithPath: "/fixtures/new"), mode: .saveAndClose)
            }
        }
        await f.writer.waitForCall(1)
        #expect(session.isReadOnly)
        operation.cancel()
        // The writer simulates publication already having committed, despite cancellation.
        await f.writer.succeed(0)
        #expect(await operation.value == .cancelled)
        #expect(session.binding?.baseline == Data("committed text".utf8))
        #expect(session.text == "committed text" && session.captureID == capture && session.focusRequestID == focus)
        #expect(!session.isReadOnly && !coordinator.isPreparingQuit)
        #expect(coordinator.sessions[id] === session && f.projects.projects.contains(f.first))
        #expect(f.projects.recentIDs == [f.first.id] && f.projects.lastActiveID == f.first.id)
    }

    @Test(arguments: [Transition.quit, .removeProject, .changeFolder])
    func bulkTransitionCannotCloseAReplacementCapture(transition: Transition) async throws {
        let f = try await CoordinatorFixture.make(automatic: false); defer { f.cleanup() }
        let session = try await f.openFirst()
        let coordinator = f.coordinator, id = session.id, projectID = f.first.id
        coordinator.updateText(id, text: "old capture")
        let operation = Task { @concurrent in
            switch transition {
            case .quit: await coordinator.prepareForAppQuit()
            case .removeProject: await coordinator.removeProject(projectID)
            case .changeFolder: await coordinator.changeProjectFolder(projectID, selectedFolder: URL(fileURLWithPath: "/fixtures/new"), mode: .saveAndClose)
            default: EditorOperationOutcome.busy
            }
        }
        await f.writer.waitForCall(1)
        // Simulate an integration bypass of read-only ownership; the defensive
        // generation check must not close/commit against a different capture.
        session.resetCapture()
        session.acceptText("replacement capture")
        await f.writer.succeed(0)
        #expect(await operation.value.isFailure)
        #expect(session.text == "replacement capture" && session.binding == nil && session.isUnsaved)
        #expect(!session.isReadOnly && !coordinator.isPreparingQuit)
        #expect(f.projects.projects.contains(f.first) && coordinator.sessions[id] === session)
        #expect(!coordinator.windowDidClose(id))
    }
}
