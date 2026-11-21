import Foundation
import Observation

/// Temporary in-memory checkpoint-1 demo; production EditorSession is in BrainDumpCore.
@MainActor
@Observable
final class LifecycleDemoSession: Identifiable {
    let id: UUID
    let projectName: String
    var text = ""
    var isReadOnly = false

    init(id: UUID = UUID(), projectName: String) {
        self.id = id
        self.projectName = projectName
    }
}
