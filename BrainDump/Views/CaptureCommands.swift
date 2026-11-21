import SwiftUI

struct CaptureCommands: Commands {
    let runtime: CaptureAppRuntime
    @Environment(\.openWindow) private var openWindow
    private var inNewWindow: Bool { runtime.projects?.alwaysOpenInNewWindow ?? false }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Capture") { runtime.newCapture(openWindow: openWindow) }
                .keyboardShortcut("n")
                .disabled(!runtime.canNewCapture)
            Button("New Project") { runtime.showNewProject(openWindow: openWindow) }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(!runtime.canShowNewProject)
            Button("Open Project") { runtime.showOpenProject(openWindow: openWindow) }
                .keyboardShortcut("o")
                .disabled(!runtime.canShowProjectForms)
            Menu("Open Recent") {
                ForEach(runtime.projects?.recentProjects ?? []) { project in
                    Button(project.name) { runtime.openProjectFromMenu(project.id, openWindow: openWindow) }
                        .disabled(!runtime.canOpenProject(project.id, inNewWindow: inNewWindow))
                }
                Divider()
                Button("Clear Menu") { runtime.clearRecent(openWindow: openWindow) }
                    .disabled(runtime.projects?.recentIDs.isEmpty != false || runtime.isBusy)
            }
        }
        CommandGroup(replacing: .saveItem) {
            Button("Close") { runtime.nativeCommands.perform(.closeWindow) }
                .keyboardShortcut("w")
                .disabled(!runtime.nativeCommands.status(.closeWindow).isEnabled)
            Button("Save") { if let target = runtime.targetEditorID { runtime.save(target) } }
                .keyboardShortcut("s")
                .disabled(!runtime.canSave)
            Divider()
            Button("Project Settings…") { runtime.showProjectSettings(openWindow: openWindow) }
                .disabled(runtime.projects == nil || runtime.isBusy)
        }
        CommandMenu("Projects") {
            ProjectSelectionItems(entries: runtime.projectEntries, canSelect: {
                runtime.canOpenProject($0, inNewWindow: inNewWindow)
            }) { runtime.openProjectFromMenu($0, openWindow: openWindow) }
            Divider()
            Toggle("Always Open in New Window", isOn: Binding(
                get: { inNewWindow }, set: { runtime.setAlwaysOpenInNewWindow($0, openWindow: openWindow) }
            ))
            .disabled(runtime.projects == nil || runtime.isBusy)
        }
        // Remove singleton-scene shortcuts that bypass draft/origin initialization.
        // The native list of already-open windows and standard window actions remain.
        CommandGroup(replacing: .singleWindowList) {}
        CommandGroup(replacing: .help) {
            Button("BrainDump Help") { openWindow(id: "help") }
        }
    }
}
