import SwiftUI

@main
struct BrainDumpApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var runtime = CaptureAppRuntime()
    @Environment(\.openWindow) private var openWindow
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup("Capture", id: "editor", for: UUID.self) { $sessionID in
            if let sessionID, let session = runtime.coordinator?.sessions[sessionID] {
                CaptureEditorView(session: session, runtime: runtime)
            }
        }
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        .defaultSize(width: 1340, height: 700)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.expanded)
        .commands {
            CaptureCommands(runtime: runtime)
            NativeTextCommands(state: runtime.nativeCommands)
        }
        .onChange(of: scenePhase, initial: true) {
            appDelegate.runtime = runtime
            // No scene is initially presented, so waiting for an active window
            // would deadlock startup. The runtime accepts this callback once.
            runtime.start(openWindow: openWindow)
        }

        Window("New Project", id: "new-project") {
            NewProjectView(runtime: runtime, draft: runtime.newProjectDraft)
                .id(runtime.newProjectDraft.id)
        }
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        .windowResizability(.contentSize)
        .commandsRemoved()

        Window("Open Project", id: "open-project") {
            OpenProjectView(runtime: runtime).id(runtime.openProjectRequestID)
        }
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        .defaultSize(width: 550, height: 400)
        .commandsRemoved()

        Window("Project Settings", id: "project-settings") {
            ProjectSettingsView(runtime: runtime).id(runtime.settingsRequestID)
        }
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        .defaultSize(width: 650, height: 500)
        .commandsRemoved()

        Window("BrainDump Help", id: "help") { HelpView() }
            .defaultLaunchBehavior(.suppressed)
            .restorationBehavior(.disabled)
            .defaultSize(width: 720, height: 600)
            .commandsRemoved()
    }
}
