// Headless checks: imports Foundation/Observation only; never launches AppKit or the app.
import Foundation

@MainActor
private final class ControlledDecision: LifecycleDecisionProviding {
    private var pending: CheckedContinuation<Bool, any Error>?
    private var started: CheckedContinuation<Void, Never>?
    private(set) var requestCount = 0

    func decide() async throws -> Bool {
        requestCount += 1
        return try await withCheckedThrowingContinuation { continuation in
            precondition(pending == nil, "Overlapping decisions must be prevented")
            pending = continuation
            started?.resume()
            started = nil
        }
    }

    func waitForRequest() async {
        if pending != nil { return }
        await withCheckedContinuation { started = $0 }
    }

    func finish(allow: Bool) {
        let continuation = pending
        pending = nil
        continuation?.resume(returning: allow)
    }
}

@main
private struct Checkpoint1LifecycleChecks {
    @MainActor
    static func main() async {
        let decision = ControlledDecision()
        let coordinator = LifecycleDemoCoordinator(decisions: decision)
        guard let first = coordinator.createSession(), let second = coordinator.createSession() else {
            preconditionFailure("Sessions must be creatable before quit")
        }
        precondition(first.id != second.id)
        precondition(first.projectName == second.projectName)
        coordinator.activate(first.id)
        coordinator.activate(second.id)
        coordinator.deactivate(second.id)
        precondition(coordinator.activeEditorID == nil)
        precondition(coordinator.mostRecentlyActiveEditorID == second.id)
        precondition(coordinator.sessions[first.id] === first)
        print("PASS: stable independent sessions and activation tracking")

        first.text = "Keep this capture"
        async let rejectedClose = coordinator.prepareClose(first.id)
        await decision.waitForRequest()
        precondition(first.isReadOnly && !second.isReadOnly)
        let duplicate = await coordinator.prepareClose(first.id)
        precondition(!duplicate && decision.requestCount == 1)
        let quitDuringClose = await coordinator.prepareForAppQuit()
        precondition(!quitDuringClose)
        decision.finish(allow: false)
        let rejected = await rejectedClose
        precondition(!rejected && !first.isReadOnly)
        precondition(first.text == "Keep this capture" && coordinator.sessions.count == 2)
        print("PASS: pending close locks only its session; rejected close preserves content")

        async let rejectedQuit = coordinator.prepareForAppQuit()
        await decision.waitForRequest()
        precondition(first.isReadOnly && second.isReadOnly)
        precondition(coordinator.isPreparingQuit)
        precondition(coordinator.createSession() == nil)
        let closeDuringQuit = await coordinator.prepareClose(second.id)
        let duplicateQuit = await coordinator.prepareForAppQuit()
        precondition(!closeDuringQuit && !duplicateQuit && decision.requestCount == 2)
        decision.finish(allow: false)
        let quitRejected = await rejectedQuit
        precondition(!quitRejected && coordinator.sessions.count == 2)
        precondition(!coordinator.isPreparingQuit && !first.isReadOnly && !second.isReadOnly)
        precondition(coordinator.mostRecentlyActiveEditorID == second.id)
        print("PASS: rejected quit preserves all sessions and releases every lock")

        let cancelled = Task { @concurrent in await coordinator.prepareClose(first.id) }
        await decision.waitForRequest()
        cancelled.cancel()
        decision.finish(allow: true)
        let cancelledResult = await cancelled.value
        precondition(!cancelledResult && !first.isReadOnly && coordinator.sessions.count == 2)
        print("PASS: cancelled close releases its lock without dropping the capture")

        async let acceptedClose = coordinator.prepareClose(second.id)
        await decision.waitForRequest()
        decision.finish(allow: true)
        let closeAccepted = await acceptedClose
        precondition(closeAccepted && second.isReadOnly && coordinator.sessions.count == 2)
        // Native adapter unregisters only when the window actually reports closure.
        coordinator.windowDidClose(second.id)
        precondition(coordinator.sessions.count == 1)
        precondition(coordinator.mostRecentlyActiveEditorID == first.id)
        print("PASS: close permission does not unregister before actual window closure")

        async let acceptedQuit = coordinator.prepareForAppQuit()
        await decision.waitForRequest()
        decision.finish(allow: true)
        let quitAccepted = await acceptedQuit
        precondition(quitAccepted && coordinator.isPreparingQuit && first.isReadOnly)
        precondition(coordinator.sessions.count == 1)
        print("PASS: successful quit retains sessions until native termination")
        print("All six headless checkpoint 1 checks passed. Native UI behavior remains unverified.")
    }
}
