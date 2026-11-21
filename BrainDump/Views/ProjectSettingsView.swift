import SwiftUI
import UniformTypeIdentifiers

struct ProjectSettingsView: View {
    let runtime: CaptureAppRuntime
    @State private var controller: ProjectSettingsController?

    init(runtime: CaptureAppRuntime) {
        self.runtime = runtime
        if let projects = runtime.projects, let coordinator = runtime.coordinator, let registry = runtime.registry {
            // Seed the backing storage explicitly: Optional State otherwise has
            // an implicit nil seed before this initializer assigns its value.
            _controller = State(initialValue: ProjectSettingsController(projects: projects, coordinator: coordinator, selectedID: runtime.settingsProjectID,
                onCloseAuthorized: { [weak registry] ids in registry?.closeAuthorizedWindows(ids) },
                onApplied: { [weak runtime] id in
                    guard let runtime else { return }
                    if runtime.projects?.availability[id]?.isAvailable == true || runtime.projects?.projects.contains(where: { $0.id == id }) == false {
                        runtime.projectFolderRepaired(id)
                    }
                }))
        } else { _controller = State(initialValue: nil) }
    }

    var body: some View {
        if let controller { ProjectSettingsContent(runtime: runtime, controller: controller) }
        else { InlineMessage(message: runtime.initializationError ?? String(localized: "Project Settings could not be opened.")).padding() }
    }
}

private struct ProjectSettingsContent: View {
    let runtime: CaptureAppRuntime
    @Bindable var controller: ProjectSettingsController
    @State private var choosingFolder = false
    @State private var folderChoice: ProjectFolderDraft.Choice?
    @State private var revealing = false
    @State private var showingDecision = false
    @State private var answeredDecision = false
    @State private var showingRemoval = false
    @State private var answeredRemoval = false
    @AccessibilityFocusState(for: .voiceOver) private var errorFocused: Bool

    private var busy: Bool { controller.isBusy || choosingFolder || revealing }
    private var progressText: String? {
        if revealing { return String(localized: "Revealing registered folder…") }
        switch controller.activity {
        case .checkingFolder: return String(localized: "Checking selected folder…")
        case .applyingChanges: return String(localized: "Applying project changes…")
        case .removingProject: return String(localized: "Saving captures before removing project…")
        case nil: return nil
        }
    }

    var body: some View {
        dialogContent
        .alert("Unable to Save Captures", isPresented: Binding(get: { controller.blockedIssue != nil }, set: { if !$0 { controller.blockedIssue = nil } })) {
            Button("OK", role: .cancel) { controller.blockedIssue = nil }
        } message: { Text(controller.blockedIssue?.message ?? "") }
    }

    private var dialogContent: some View {
        lifecycleContent
        .onChange(of: controller.decision?.id) {
            answeredDecision = false
            showingDecision = controller.decision != nil
        }
        .onChange(of: showingDecision) {
            if !showingDecision && !answeredDecision && controller.decision != nil { Task { await controller.resolveDecision(nil) } }
        }
        .confirmationDialog("Change Project Folder", isPresented: $showingDecision, titleVisibility: .visible, presenting: controller.decision) { _ in
            Button("Keep captures open") { answeredDecision = true; Task { await controller.resolveDecision(.keepOpen) } }
            Button("Save and close captures") { answeredDecision = true; Task { await controller.resolveDecision(.saveAndClose) } }
            Button("Cancel", role: .cancel) { answeredDecision = true; Task { await controller.resolveDecision(nil) } }
        } message: { decision in
            Text("“\(decision.projectName)” has unsaved captures. Keep them open, or save them at their old locations and close them before applying the name and folder changes. Cancel retains this project's draft.")
        }
        .onChange(of: controller.removal?.id) {
            answeredRemoval = false
            showingRemoval = controller.removal != nil
        }
        .onChange(of: showingRemoval) { if !showingRemoval && !answeredRemoval { controller.cancelRemoval() } }
        .confirmationDialog("Remove Project", isPresented: $showingRemoval, titleVisibility: .visible, presenting: controller.removal) { _ in
            Button("Remove Project", role: .destructive) { answeredRemoval = true; Task { await controller.confirmRemoval() } }
            Button("Cancel", role: .cancel) { answeredRemoval = true; controller.cancelRemoval() }
        } message: { project in
            Text("Remove “\(project.name)” from BrainDump? Its non-empty captures will be saved before its editors close. Unapplied name and folder drafts are ignored. Project folders and capture files are kept.")
        }
    }

    private var lifecycleContent: some View {
        layout
        .padding()
        .frame(minWidth: 600, minHeight: 520)
        .disabled(busy || controller.requestsClose)
        .background(AuxiliaryWindowAttachment(isBusy: busy, closeRequested: controller.requestsClose, canClose: { !busy },
                                              onClose: { runtime.projectSettingsIsVisible = false }))
        .onAppear { runtime.projectSettingsIsVisible = true }
        .onChange(of: controller.error) { if controller.error != nil { errorFocused = true } }
        .task { await runtime.projects?.refreshAvailability() }
        .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { result in
            guard let folderChoice else { return }
            switch result {
            case .success(let url): Task { await controller.acceptFolder(url, choice: folderChoice) }
            case .failure(let error): controller.cancelFolderChoice(folderChoice); controller.error = error.localizedDescription
            }
        }
    }

    private var layout: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let projects = runtime.projects {
                List(selection: Binding(get: { controller.selectedID }, set: { id in Task { await controller.select(id) } })) {
                    ForEach(ProjectListBuilder().build(projects.projects).flatMap(\.projects)) { project in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(project.name)
                            Text(project.folder.path).font(.callout)
                            Text(projects.availability[project.id]?.explanation ?? String(localized: "Checking folder access…")).font(.callout)
                            if controller.drafts[project.id]?.hasChanges == true { Text("Unapplied changes").font(.callout) }
                            if let draft = controller.drafts[project.id], draft.name != project.name {
                                Text(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                     ? String(localized: "Draft name is empty.") : String(localized: "Draft name: \(draft.name)")).font(.callout)
                            }
                            let problems = controller.problems(for: project.id)
                            if !problems.isEmpty { Text(problems.joined(separator: " ")).font(.callout) }
                        }
                        .tag(project.id)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("settings.project.\(project.id.uuidString)")
                        .accessibilityAction { Task { await controller.select(project.id) } }
                    }
                }
                .accessibilityLabel("Registered projects, folder access, and draft problems")
                if let draft = controller.selectedDraft,
                   let project = projects.projects.first(where: { $0.id == controller.selectedID }) {
                    ProjectSettingsInspector(draft: draft, project: project, projects: projects, chooseFolder: {
                        folderChoice = controller.beginFolderChoice()
                        choosingFolder = folderChoice != nil
                    }, reveal: {
                        revealing = true
                        Task { controller.error = await runtime.revealProject(project.id); revealing = false }
                    }, remove: { controller.requestRemoval() })
                    .id(project.id)
                }
            }
            Text("Valid changes are applied when you select another project. Cancel discards only changes that have not been applied.")
                .font(.callout).fixedSize(horizontal: false, vertical: true)
            if let error = controller.error { InlineMessage(message: error).accessibilityFocused($errorFocused) }
            if let progressText { ProgressView(progressText) }
            HStack {
                Spacer()
                Button("Cancel") { controller.cancel() }.accessibilityIdentifier("settings.cancel").keyboardShortcut(.cancelAction)
                Button("OK") { Task { await controller.ok() } }.accessibilityIdentifier("settings.ok")
                    .keyboardShortcut(.defaultAction).disabled(!controller.canOK)
            }
        }
    }
}

private struct ProjectSettingsInspector: View {
    @Bindable var draft: ProjectSettingsDraft
    let project: ProjectRecord
    let projects: ProjectStore
    let chooseFolder: () -> Void
    let reveal: () -> Void
    let remove: () -> Void
    @AccessibilityFocusState(for: .voiceOver) private var folderErrorFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Project: \(project.name)").font(.headline)
            LabeledContent("Project name") {
                TextField("Project name", text: $draft.name)
                    .accessibilityLabel("Project name")
                    .accessibilityIdentifier("settings.name")
            }
            if let error = projects.nameValidationMessage(draft.name, excluding: project.id) { InlineMessage(message: error) }
            Text("Registered folder: \(project.folder.path)").textSelection(.enabled)
            HStack {
                Button("Change Folder…", systemImage: "folder", action: chooseFolder)
                    .accessibilityIdentifier("settings.changeFolder")
                    .accessibilityLabel("Change folder for \(project.name)")
                Button("Reveal in Finder", systemImage: "magnifyingglass", action: reveal)
                    .accessibilityIdentifier("settings.reveal")
                    .disabled(projects.availability[project.id]?.isAvailable != true)
                Button("Remove Project…", systemImage: "trash", action: remove)
                    .accessibilityIdentifier("settings.remove")
            }
            .labelStyle(.titleAndIcon)
            if let selected = draft.folderChoice.change {
                Text("Selected folder: \(draft.authorizedFolder?.path ?? selected.folder.path)").textSelection(.enabled)
            }
            if let error = draft.folderError { InlineMessage(message: error).accessibilityFocused($folderErrorFocused) }
        }
        .onChange(of: draft.folderError) { if draft.folderError != nil { folderErrorFocused = true } }
    }
}
