import SwiftUI

struct OpenProjectView: View {
    let runtime: CaptureAppRuntime
    @Environment(\.openWindow) private var openWindow
    @State private var selection: UUID?
    @State private var openInNewWindow: Bool
    @State private var isWorking = false
    @State private var error: String?
    @State private var failedProjectID: UUID?
    @State private var closeRequested = false
    @AccessibilityFocusState(for: .voiceOver) private var errorFocused: Bool
    private var displayedError: String? { error ?? runtime.openProjectExplanation }
    private var selectedProjectIsAvailable: Bool {
        runtime.projects?.reachableProjects.contains(where: { $0.id == selection }) == true
    }
    private var canOpenSelection: Bool {
        guard let selection, selectedProjectIsAvailable else { return false }
        return runtime.canOpenProject(selection, origin: runtime.openProjectOriginID, inNewWindow: openInNewWindow)
    }

    init(runtime: CaptureAppRuntime) {
        self.runtime = runtime
        // Seed once per form request; availability refreshes must not reset a
        // choice made while this window is open.
        self.openInNewWindow = runtime.openProjectWindowState.choice(defaultingTo: runtime.projects?.alwaysOpenInNewWindow ?? false)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let displayedError { InlineMessage(message: displayedError).accessibilityFocused($errorFocused) }
            if let projects = runtime.projects {
                List(selection: $selection) {
                    ForEach(ProjectListBuilder().build(projects.reachableProjects).flatMap(\.projects)) { project in
                        VStack(alignment: .leading) {
                            Text(project.name)
                            Text(project.folder.path).font(.callout).foregroundStyle(.primary)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("open.project.\(project.id.uuidString)")
                        .accessibilityAction { selection = project.id }
                        .contentShape(Rectangle())
                        .tag(project.id)
                    }
                }
                .contextMenu(forSelectionType: UUID.self) { _ in
                    EmptyView()
                } primaryAction: { ids in
                    guard ids.count == 1, let id = ids.first else { return }
                    selection = id
                    openProject(id)
                }
                .accessibilityLabel("Available projects")
                .accessibilityIdentifier("open.projectList")
                .background(ProjectListScrollAccessibility())
                if projects.reachableProjects.isEmpty { Text("No available projects. Choose New Project to register a folder.") }
                Toggle("Open in new window", isOn: $openInNewWindow)
                    .toggleStyle(.checkbox)
                    .accessibilityIdentifier("open.openInNewWindow")
                if displayedError != nil || projects.projects.contains(where: { projects.availability[$0.id]?.isAvailable != true }) {
                    Button("Project Settings…") { runtime.showProjectSettings(openWindow: openWindow, projectID: failedProjectID ?? runtime.openProjectFailureID ?? selection) }
                }
                HStack {
                    Button("New Project") {
                        runtime.showNewProject(openWindow: openWindow, originatingEditorID: runtime.openProjectOriginID)
                        closeRequested = true
                    }
                    Spacer()
                    Button("Cancel") { closeRequested = true }.keyboardShortcut(.cancelAction)
                    Button("Open") { openSelected() }.accessibilityIdentifier("open.open").keyboardShortcut(.defaultAction)
                        .disabled(!canOpenSelection || isWorking)
                }
            }
        }
        .padding()
        .frame(minWidth: 500, minHeight: 350)
        .disabled(isWorking || closeRequested)
        .background(AuxiliaryWindowAttachment(isBusy: isWorking, closeRequested: closeRequested, canClose: { !isWorking },
                                              onClose: { runtime.openProjectIsVisible = false }))
        .onAppear { runtime.openProjectIsVisible = true; errorFocused = displayedError != nil }
        .onChange(of: displayedError) { if displayedError != nil { errorFocused = true } }
        .onChange(of: openInNewWindow) { runtime.openProjectWindowState.remember(openInNewWindow) }
        .onChange(of: runtime.projects?.availability) {
            if let id = failedProjectID, runtime.projects?.availability[id]?.isAvailable == true {
                error = nil
                failedProjectID = nil
            }
        }
        .task {
            await runtime.projects?.refreshAvailability()
        }
    }

    private func openSelected() {
        guard let selection else { return }
        openProject(selection)
    }

    private func openProject(_ projectID: UUID) {
        guard !isWorking, !closeRequested,
              runtime.projects?.reachableProjects.contains(where: { $0.id == projectID }) == true,
              runtime.canOpenProject(projectID, origin: runtime.openProjectOriginID, inNewWindow: openInNewWindow) else { return }
        isWorking = true
        runtime.isOpeningProject = true
        let origin = runtime.openProjectOriginID
        Task {
            defer { isWorking = false; runtime.isOpeningProject = false }
            switch await runtime.openProject(projectID, origin: origin, inNewWindow: openInNewWindow) {
            case .opened(let id), .reused(let id):
                isWorking = false
                runtime.isOpeningProject = false
                openWindow(id: "editor", value: id)
                runtime.registry?.activate(id)
                closeRequested = true
            case .failed(let issue): failedProjectID = projectID; error = issue.message
            case .busy: error = EditorWorkflowError.busy.localizedDescription
            case .cancelled: break
            }
        }
    }
}
