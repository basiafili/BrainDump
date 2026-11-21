import SwiftUI
import Observation
import AppKit

/// Presentation routing and finite UI callback tasks. Saving and registry
/// transactions remain in the UI-independent coordinator.
@MainActor
@Observable
final class CaptureAppRuntime {
    let folders: FolderAuthorizationService
    let writer: CaptureFileWriter
    let projects: ProjectStore?
    let coordinator: EditorCoordinator?
    let router: ProjectCommandRouter?
    let registry: WindowLifecycleRegistry?
    let initializationError: String?
    let newProjectWindowState: ProjectWindowState
    let openProjectWindowState: ProjectWindowState
    let nativeCommands = NativeCommandState()
    private(set) var newProjectDraft: NewProjectDraft
    private(set) var openProjectRequestID = UUID()
    private(set) var openProjectOriginID: UUID?
    private(set) var openProjectExplanation: String?
    private(set) var openProjectFailureID: UUID?
    private(set) var settingsRequestID = UUID()
    private(set) var settingsProjectID: UUID?
    var projectSettingsIsVisible = false
    var isOpeningProject = false
    var newProjectIsVisible = false
    var openProjectIsVisible = false
    var blockingIssue: EditorWorkflowIssue?
    private(set) var blockingEditorID: UUID?
    @ObservationIgnored private var startupTask: Task<Void, Never>?
    @ObservationIgnored private var didStart = false
    @ObservationIgnored private var tasks: [UUID: Task<Void, Never>] = [:]
    #if DEBUG
    @ObservationIgnored private let uiTestConfiguration: UITestConfiguration?
    #endif

    init() {
        #if DEBUG
        let uiTestConfiguration = UITestConfiguration.fromLaunch()
        self.uiTestConfiguration = uiTestConfiguration
        let defaults = uiTestConfiguration?.defaults ?? .standard
        #else
        let defaults = UserDefaults.standard
        #endif
        let folders = FolderAuthorizationService()
        #if DEBUG
        let writer = CaptureFileWriter(folders: folders, hooks: uiTestConfiguration?.writeHooks ?? CaptureWriteHooks())
        #else
        let writer = CaptureFileWriter(folders: folders)
        #endif
        self.folders = folders
        self.writer = writer
        do {
            let projects = try ProjectStore(defaults: defaults, folders: folders)
            let coordinator = EditorCoordinator(projects: projects, writer: writer)
            self.projects = projects
            self.coordinator = coordinator
            router = ProjectCommandRouter(projects: projects, coordinator: coordinator)
            registry = WindowLifecycleRegistry(coordinator: coordinator)
            initializationError = nil
        } catch {
            projects = nil
            coordinator = nil
            router = nil
            registry = nil
            initializationError = error.localizedDescription
        }
        let windowState = ProjectWindowState(window: .newProject, defaults: defaults, initialValue: projects?.alwaysOpenInNewWindow ?? false)
        newProjectWindowState = windowState
        openProjectWindowState = ProjectWindowState(window: .openProject, defaults: defaults, initialValue: projects?.alwaysOpenInNewWindow ?? false)
        newProjectDraft = NewProjectDraft(originatingEditorID: nil, explanation: initializationError,
                                          openInNewWindow: windowState.openInNewWindow)
        registry?.onFailure = { [weak self] issue in self?.presentBlocked(issue) }
        registry?.recordsUsageForActivation = { [weak self] id in
            // Raising a save-failure sheet is internal presentation, not user
            // project use. In particular, failed quit must preserve last active.
            self?.blockingIssue == nil || self?.blockingEditorID != id
        }
    }

    var targetEditorID: UUID? { router?.targetEditorID }
    var isBusy: Bool { coordinator?.isPreparingQuit == true }
    var canNewCapture: Bool { router?.canNewCapture ?? false }
    var canSave: Bool { router?.canSave ?? false }
    var canShowNewProject: Bool { !isBusy && (targetEditorID.map(canUseEditor) ?? true) }
    var canShowProjectForms: Bool { projects != nil && canShowNewProject }
    var projectEntries: [ProjectListEntry] { ProjectListBuilder().build(projects?.reachableProjects ?? []) }

    func canUseEditor(_ id: UUID) -> Bool { router?.canUseEditor(id) ?? false }

    func canOpenProject(_ id: UUID, origin: UUID? = nil, inNewWindow: Bool) -> Bool {
        router?.canOpen(id, inNewWindow: inNewWindow, origin: origin) ?? false
    }

    func start(openWindow: OpenWindowAction) {
        guard !didStart else { return }
        didStart = true
        nativeCommands.start()
        startupTask = Task { [weak self] in
            guard let self else { return }
            defer { self.startupTask = nil }
            guard let projects = self.projects, let coordinator = self.coordinator else {
                self.showNewProject(openWindow: openWindow, explanation: self.initializationError)
                return
            }
            #if DEBUG
            if self.uiTestConfiguration?.cleanupRequested == true { return }
            do { try await self.uiTestConfiguration?.prepare(projects: projects) }
            catch { self.showNewProject(openWindow: openWindow, explanation: "UI-test fixture failed: \(error.localizedDescription)"); return }
            #endif
            let destination = await StartupRouter.resolve(projects: projects, coordinator: coordinator)
            self.present(destination, openWindow: openWindow)
            await projects.refreshAvailability()
        }
    }

    func showNewProject(openWindow: OpenWindowAction, explanation: String? = nil, originatingEditorID: UUID? = nil) {
        guard !newProjectIsVisible, !newProjectDraft.isWorking else { openWindow(id: "new-project"); return }
        newProjectDraft = NewProjectDraft(originatingEditorID: router?.targetEditorID(retaining: originatingEditorID), explanation: explanation ?? initializationError,
                                          openInNewWindow: newProjectWindowState.choice(defaultingTo: projects?.alwaysOpenInNewWindow ?? false))
        newProjectIsVisible = true
        openWindow(id: "new-project")
    }

    func createProject(_ draft: NewProjectDraft, openWindow: OpenWindowAction) {
        guard let coordinator, let url = draft.selectedURL, !draft.isWorking, !draft.didCreateProject, !draft.closeRequested else { return }
        draft.isWorking = true
        draft.creationError = nil
        // Retain the origin while it exists; only fall back if it already closed.
        let origin = router?.targetEditorID(retaining: draft.originatingEditorID)
        let reuse = draft.openInNewWindow ? nil : origin
        let expectedFolder = draft.selectedFolder
        run {
            defer { draft.isWorking = false }
            let result = await coordinator.createProject(name: draft.name, selectedFolder: url, expectedFolder: expectedFolder,
                                                         reusing: reuse, folderPreparer: self.writer)
            switch result {
            case .opened(let id):
                draft.completeCreation()
                openWindow(id: "editor", value: id)
                self.registry?.activate(id)
            case .failed(let issue): draft.creationError = issue.message
            case .busy: draft.creationError = EditorWorkflowError.busy.localizedDescription
            case .cancelled: break
            }
        }
    }

    func showOpenProject(openWindow: OpenWindowAction, explanation: String? = nil, failedProjectID: UUID? = nil,
                         originatingEditorID: UUID? = nil) {
        if let explanation { openProjectExplanation = explanation; openProjectFailureID = failedProjectID }
        guard !openProjectIsVisible, !isOpeningProject else { openWindow(id: "open-project"); return }
        openProjectExplanation = explanation
        openProjectFailureID = failedProjectID
        openProjectOriginID = router?.targetEditorID(retaining: originatingEditorID)
        openProjectRequestID = UUID()
        openProjectIsVisible = true
        openWindow(id: "open-project")
    }

    func showProjectSettings(openWindow: OpenWindowAction, projectID: UUID? = nil) {
        guard !projectSettingsIsVisible else { openWindow(id: "project-settings"); return }
        settingsProjectID = projectID ?? projects?.lastActiveID
        settingsRequestID = UUID()
        projectSettingsIsVisible = true
        openWindow(id: "project-settings")
    }

    func projectFolderRepaired(_ projectID: UUID) {
        if projects?.lastActiveID == projectID || openProjectFailureID == projectID {
            openProjectExplanation = nil
            openProjectFailureID = nil
        }
    }

    func revealProject(_ projectID: UUID) async -> String? {
        guard let projects else { return initializationError }
        do {
            let project = try await projects.revalidate(projectID)
            let access = try await folders.acquire(project.folder)
            // User-invoked native action on the committed registration, never a
            // draft folder. Finder manages its own access after this handoff.
            NSWorkspace.shared.activateFileViewerSelecting([access.folder.url])
            await folders.release(access.token)
            return nil
        } catch { return error.localizedDescription }
    }

    func newCapture(in requestedID: UUID? = nil, openWindow: OpenWindowAction) {
        guard let coordinator, let projects, !isBusy else { return }
        let target = requestedID ?? targetEditorID
        run {
            if let target {
                let result = await coordinator.newCapture(target)
                self.handle(result)
                if result.succeeded { self.registry?.activate(target) }
            } else {
                self.present(await StartupRouter.resolve(projects: projects, coordinator: coordinator, recordUsage: true), openWindow: openWindow)
            }
        }
    }

    func save(_ id: UUID) {
        guard let coordinator else { return }
        run {
            switch await coordinator.save(id) {
            case .saved:
                let message = coordinator.sessions[id]?.isUnsaved == true
                    ? String(localized: "Snapshot saved. Newer changes remain unsaved.")
                    : String(localized: "Capture saved.")
                AccessibilityAnnouncement.post(message)
            case .empty: AccessibilityAnnouncement.post(String(localized: "Empty capture. No file was changed."))
            case .failed(let issue): self.presentBlocked(issue)
            default: break
            }
        }
    }

    func switchProject(_ projectID: UUID, in sessionID: UUID) {
        guard let coordinator else { return }
        run { self.handle(await coordinator.switchProject(sessionID, to: projectID)) }
    }

    func openProject(_ projectID: UUID, origin: UUID?, inNewWindow: Bool) async -> ProjectPresentationOutcome {
        guard let router else { return .busy }
        return await router.open(ProjectOpenRequest(projectID: projectID, originatingEditorID: origin, inNewWindow: inNewWindow))
    }

    func openProjectFromMenu(_ id: UUID, openWindow: OpenWindowAction) {
        guard let router else { return }
        let request = router.menuRequest(for: id)
        run {
            switch await router.open(request) {
            case .opened(let id), .reused(let id):
                openWindow(id: "editor", value: id)
                self.registry?.activate(id)
            case .failed(let issue):
                if issue.kind == .project || self.coordinator?.sessions.isEmpty != false {
                    self.showOpenProject(openWindow: openWindow, explanation: issue.message, failedProjectID: id,
                                         originatingEditorID: request.originatingEditorID)
                } else { self.presentBlocked(issue) }
            default: break
            }
        }
    }

    func setAlwaysOpenInNewWindow(_ enabled: Bool, openWindow: OpenWindowAction) {
        do { try projects?.setAlwaysOpenInNewWindow(enabled) }
        catch { presentCommandError(error, openWindow: openWindow) }
    }

    func clearRecent(openWindow: OpenWindowAction) {
        do { try projects?.clearRecent() }
        catch { presentCommandError(error, openWindow: openWindow) }
    }

    private func presentCommandError(_ error: any Error, openWindow: OpenWindowAction) {
        if coordinator?.sessions.isEmpty != false {
            showOpenProject(openWindow: openWindow, explanation: error.localizedDescription)
        } else {
            presentBlocked(EditorWorkflowIssue(kind: .project, sessionID: targetEditorID, message: error.localizedDescription))
        }
    }

    func presentBlocked(_ issue: EditorWorkflowIssue) {
        guard blockingIssue == nil else { return }
        blockingEditorID = issue.sessionID ?? targetEditorID ?? coordinator?.sessions.keys.first
        blockingIssue = issue
        if let id = blockingEditorID { registry?.activate(id) }
        AccessibilityAnnouncement.post(issue.message)
    }

    private func handle(_ outcome: EditorOperationOutcome) {
        if case .failed(let issue) = outcome { presentBlocked(issue) }
    }

    private func present(_ destination: CaptureDestination, openWindow: OpenWindowAction) {
        switch destination {
        case .editor(let id): openWindow(id: "editor", value: id)
        case .newProject(let explanation): showNewProject(openWindow: openWindow, explanation: explanation)
        case .openProject(let explanation): showOpenProject(openWindow: openWindow, explanation: explanation, failedProjectID: projects?.lastActiveID)
        }
    }

    private func run(_ operation: @escaping @MainActor () async -> Void) {
        let id = UUID()
        tasks[id] = Task { [weak self] in
            defer { self?.tasks.removeValue(forKey: id) }
            await operation()
        }
    }
}
