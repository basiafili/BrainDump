import Foundation
import Observation

@MainActor
protocol LifecycleDecisionProviding {
    func decide() async throws -> Bool
}

/// Temporary checkpoint fixture, replaced by the common save workflow later.
@MainActor
@Observable
final class LifecycleDecisionProvider: LifecycleDecisionProviding {
    enum Outcome: String, CaseIterable, Identifiable {
        case allow = "Allow"
        case reject = "Reject"
        case delayedAllow = "Wait two seconds, then allow"
        case delayedReject = "Wait two seconds, then reject"

        var id: Self { self }
    }

    var outcome: Outcome = .allow

    func decide() async throws -> Bool {
        let requestedOutcome = outcome
        if requestedOutcome == .delayedAllow || requestedOutcome == .delayedReject {
            // Sleep suspends; no filesystem work or blocking occurs on the main actor.
            try await Task.sleep(for: .seconds(2))
        }
        try Task.checkCancellation()
        return requestedOutcome == .allow || requestedOutcome == .delayedAllow
    }
}
