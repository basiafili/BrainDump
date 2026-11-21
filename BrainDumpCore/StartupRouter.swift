import Foundation

nonisolated enum CaptureDestination: Equatable, Sendable {
    case editor(UUID)
    case newProject(explanation: String?)
    case openProject(explanation: String)
}

@MainActor
enum StartupRouter {
    /// Startup is not an explicit project-open command: preserve MRU ordering.
    static func resolve(projects: ProjectStore, coordinator: EditorCoordinator, recordUsage: Bool = false) async -> CaptureDestination {
        guard let id = projects.lastActiveID else { return .newProject(explanation: nil) }
        do {
            let session = try await coordinator.registerWindow(for: id, recordUsage: recordUsage)
            return .editor(session.id)
        } catch {
            return .openProject(explanation: String(localized: "The last active project could not be opened. \(error.localizedDescription)"))
        }
    }
}
