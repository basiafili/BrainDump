import SwiftUI

struct ProjectSelectionItems: View {
    let entries: [ProjectListEntry]
    var canSelect: (UUID) -> Bool = { _ in true }
    let select: (UUID) -> Void

    var body: some View {
        ForEach(entries, id: \.projects.first?.id) { entry in
            switch entry {
            case .project(let project): Button(project.name) { select(project.id) }
                    .disabled(!canSelect(project.id))
            case .group(let label, let projects):
                Menu(label) {
                    ForEach(projects) { project in
                        Button(project.name) { select(project.id) }
                            .disabled(!canSelect(project.id))
                    }
                }
            }
        }
    }
}
