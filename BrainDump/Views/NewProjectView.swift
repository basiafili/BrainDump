import SwiftUI
import UniformTypeIdentifiers

struct NewProjectView: View {
    let runtime: CaptureAppRuntime
    @Bindable var draft: NewProjectDraft
    @Environment(\.openWindow) private var openWindow
    @State private var choosingFolder = false
    @FocusState private var nameFocused: Bool
    private enum ErrorTarget: Hashable { case explanation, name, folder, creation }
    @AccessibilityFocusState(for: .voiceOver) private var focusedError: ErrorTarget?

    private var nameError: String? { draft.nameValidationMessage(projects: runtime.projects) }
    private var canCreate: Bool {
        runtime.projects != nil && nameError == nil && draft.selectedFolder != nil && !draft.isWorking && !runtime.isBusy
            && runtime.coordinator?.isCreatingProject != true
            && !draft.didCreateProject && !draft.closeRequested
    }

    var body: some View {
        Form {
            if let explanation = draft.explanation { InlineMessage(message: explanation).accessibilityFocused($focusedError, equals: .explanation) }
            TextField("Project name", text: $draft.name)
                .accessibilityIdentifier("new.name")
                .focused($nameFocused)
                .disabled(runtime.projects == nil)
            if let nameError { InlineMessage(message: nameError).accessibilityFocused($focusedError, equals: .name) }
            Button("Choose Folder…", systemImage: "folder") { choosingFolder = true }
                .accessibilityIdentifier("new.chooseFolder")
                .disabled(runtime.projects == nil)
            Text(draft.selectedFolder?.path ?? String(localized: "No folder selected."))
                .textSelection(.enabled)
                .accessibilityLabel("Project folder: \(draft.selectedFolder?.path ?? String(localized: "No folder selected"))")
            if let error = draft.folderError { InlineMessage(message: error).accessibilityFocused($focusedError, equals: .folder) }
            Toggle("Open in new window", isOn: $draft.openInNewWindow)
                .toggleStyle(.checkbox)
                .accessibilityIdentifier("new.openInNewWindow")
                .disabled(runtime.projects == nil)
            if let error = draft.creationError { InlineMessage(message: error).accessibilityFocused($focusedError, equals: .creation) }
            if draft.isWorking { ProgressView("Preparing project…") }
            HStack {
                Spacer()
                Button("Cancel") { draft.closeRequested = true }
                    .accessibilityIdentifier("new.cancel")
                    .keyboardShortcut(.cancelAction)
                    .disabled(draft.isWorking)
                Button("Create") { runtime.createProject(draft, openWindow: openWindow) }
                    .accessibilityIdentifier("new.create")
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canCreate)
            }
        }
        .formStyle(.columns)
        .defaultFocus($nameFocused, true)
        .padding()
        .frame(minWidth: 480, idealWidth: 550, minHeight: 350)
        .disabled(draft.isWorking || draft.closeRequested)
        .background(AuxiliaryWindowAttachment(isBusy: draft.isWorking, closeRequested: draft.closeRequested, canClose: { !draft.isWorking },
                                              onClose: { runtime.newProjectIsVisible = false }))
        .onAppear {
            runtime.newProjectIsVisible = true
            if draft.explanation != nil { focusedError = .explanation }
        }
        .onChange(of: draft.creationError) { if draft.creationError != nil { focusedError = .creation } }
        .onChange(of: draft.folderError) { if draft.folderError != nil { focusedError = .folder } }
        .onChange(of: draft.openInNewWindow) { runtime.newProjectWindowState.remember(draft.openInNewWindow) }
        .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { result in
            switch result {
            case .success(let url):
                guard let projects = runtime.projects else { return }
                Task { await draft.choose(url, folders: runtime.folders, projects: projects) }
            case .failure(let error): draft.selectionFailed(error)
            }
        }
    }
}
