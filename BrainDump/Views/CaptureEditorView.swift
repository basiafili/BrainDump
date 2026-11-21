import AppKit
import SwiftUI

struct CaptureEditorView: View {
    let session: EditorSession
    let runtime: CaptureAppRuntime
    @Environment(\.openWindow) private var openWindow

    private var canAct: Bool { runtime.canUseEditor(session.id) }
    private var status: String {
        if session.isReadOnly { return String(localized: "Saving before leaving this capture. Editing is temporarily read-only.") }
        if session.isSaving { return String(localized: "Saving a snapshot. You can keep typing.") }
        if session.isEmpty {
            return session.binding == nil ? String(localized: "Empty capture. Nothing to save.")
                : String(localized: "Empty capture. The previously saved file is kept.")
        }
        return session.isUnsaved ? String(localized: "Unsaved changes.") : String(localized: "Capture saved.")
    }

    var body: some View {
        if let coordinator = runtime.coordinator, let registry = runtime.registry {
            VStack(alignment: .leading, spacing: 0) {
                CaptureTextEditor(session: session, coordinator: coordinator)
                    .id(session.captureID)
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text(status).accessibilityIdentifier("editor.status").accessibilityLabel("Save status: \(status)")
                    if let issue = session.issue { InlineMessage(message: issue.message) }
                }
                .font(.callout)
                .padding(8)
            }
            .frame(minWidth: 1340, minHeight: 360)
            .navigationTitle(session.title)
            .background(WindowAttachment(registry: registry, sessionID: session.id))
            .toolbar { toolbar }
            .labelStyle(.titleAndIcon)
            .task(id: session.isReadOnly) {
                guard session.isReadOnly else { return }
                do { try await Task.sleep(for: .seconds(2)) }
                catch { return }
                guard session.isReadOnly else { return }
                AccessibilityAnnouncement.post(status)
            }
            .alert("Unable to Complete Action", isPresented: Binding(
                get: { runtime.blockingIssue != nil && runtime.blockingEditorID == session.id },
                set: { if !$0 { runtime.blockingIssue = nil } }
            )) {
                Button("OK", role: .cancel) { runtime.blockingIssue = nil }
            } message: {
                Text(runtime.blockingIssue?.message ?? "")
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            Button("New Capture", systemImage: "square.and.pencil") { runtime.newCapture(in: session.id, openWindow: openWindow) }
                .disabled(!canAct)
            Button("New Project", systemImage: "folder.badge.plus") { runtime.showNewProject(openWindow: openWindow) }
                .disabled(!canAct)
            Button("Open Project", systemImage: "folder") { runtime.showOpenProject(openWindow: openWindow) }
                .disabled(!canAct)
            Button("Save", systemImage: "square.and.arrow.down") { runtime.save(session.id) }
                .disabled(!canAct)
            Spacer()
            Button("Cut", systemImage: "scissors") { NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil) }
                .disabled(session.isReadOnly)
            Button("Copy", systemImage: "doc.on.doc") { NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil) }
            Button("Paste", systemImage: "clipboard") { NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil) }
                .disabled(session.isReadOnly)
        }
        ToolbarItem(id: "project-switcher") {
            ProjectSwitcher(title: session.project.name, entries: runtime.projectEntries, enabled: canAct,
                            canSelect: { runtime.canOpenProject($0, origin: session.id, inNewWindow: false) },
                            select: { runtime.switchProject($0, in: session.id) })
                .fixedSize()
        }
    }
}
