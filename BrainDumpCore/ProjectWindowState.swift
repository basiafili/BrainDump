import Foundation

/// Form memory is independent of the global project-opening preference.
@MainActor
final class ProjectWindowState {
    nonisolated enum Window: String, Sendable {
        case newProject = "newProjectWindow"
        case openProject = "openProjectWindow"
    }
    private let defaults: UserDefaults
    private let fallback: Bool
    private let key: String

    init(window: Window, defaults: UserDefaults = .standard, initialValue: Bool) {
        self.defaults = defaults
        fallback = initialValue
        key = window.rawValue + ".openInNewWindow"
    }

    var openInNewWindow: Bool {
        choice(defaultingTo: fallback)
    }

    func choice(defaultingTo value: Bool) -> Bool {
        defaults.object(forKey: key) == nil ? value : defaults.bool(forKey: key)
    }

    func remember(_ value: Bool) { defaults.set(value, forKey: key) }
}
