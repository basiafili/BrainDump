import AppKit
import Observation

/// Uses the native responder chain for the key window and focused text control.
/// Never selects an editor or implements a text transformation itself.
@MainActor
@Observable
final class NativeCommandState {
    nonisolated enum Action: String, CaseIterable, Sendable {
        case closeWindow = "performClose:"
        case spellingPanel = "showGuessPanel:"
        case checkSpelling = "checkSpelling:"
        case continuousSpelling = "toggleContinuousSpellChecking:"
        case grammar = "toggleGrammarChecking:"
        case correction = "toggleAutomaticSpellingCorrection:"
        case substitutionsPanel = "orderFrontSubstitutionsPanel:"
        case quotes = "toggleAutomaticQuoteSubstitution:"
        case dashes = "toggleAutomaticDashSubstitution:"
        case replacement = "toggleAutomaticTextReplacement:"
        case links = "toggleAutomaticLinkDetection:"
        case uppercase = "uppercaseWord:"
        case lowercase = "lowercaseWord:"
        case capitalize = "capitalizeWord:"
        case startSpeaking = "startSpeaking:"
        case stopSpeaking = "stopSpeaking:"
    }
    nonisolated struct Status: Equatable {
        var isEnabled = false
        var isOn = false
    }
    private(set) var statuses: [Action: Status] = [:]
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []

    func start() {
        guard observers.isEmpty else { return }
        let notifications = [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification,
                             NSWindow.didUpdateNotification, NSControl.textDidBeginEditingNotification,
                             NSControl.textDidEndEditingNotification, NSTextView.didChangeSelectionNotification]
        for name in notifications {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                // Finite UI callback hop; no long-lived task or work off actor.
                Task { @MainActor [weak self] in self?.refresh() }
            })
        }
        refresh()
    }

    func stop() {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll()
    }

    func status(_ action: Action) -> Status { statuses[action] ?? Status() }

    func perform(_ action: Action) {
        guard status(action).isEnabled else { return }
        NSApplication.shared.sendAction(NSSelectorFromString(action.rawValue), to: nil, from: nil)
        refresh()
    }

    private func refresh() {
        var next: [Action: Status] = [:]
        for action in Action.allCases {
            let selector = NSSelectorFromString(action.rawValue)
            let item = NSMenuItem(title: "", action: selector, keyEquivalent: "")
            let target = NSApplication.shared.target(forAction: selector)
            let enabled: Bool
            if let validator = target as? any NSMenuItemValidation { enabled = validator.validateMenuItem(item) }
            else if let validator = target as? any NSUserInterfaceValidations { enabled = validator.validateUserInterfaceItem(item) }
            else { enabled = target != nil }
            next[action] = Status(isEnabled: enabled, isOn: item.state == .on)
        }
        // Window updates are frequent; unchanged native state must not invalidate views.
        if statuses != next { statuses = next }
    }
}
