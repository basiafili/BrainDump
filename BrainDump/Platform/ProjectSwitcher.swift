import AppKit
import SwiftUI

/// The SDK's SwiftUI Menu/Picker toolbar controls fail the macOS action audit.
/// Keep presentation in SwiftUI and bridge only native menu activation, with an
/// explicit accessibility press action that opens the same real menu as a click.
struct ProjectSwitcher: NSViewRepresentable {
    let title: String
    let entries: [ProjectListEntry]
    let enabled: Bool
    let canSelect: (UUID) -> Bool
    let select: (UUID) -> Void
    struct Configuration: Equatable {
        let title: String
        let entries: [ProjectListEntry]
        let enabled: Bool
        let enabledIDs: Set<UUID>
    }

    func makeCoordinator() -> Adapter { Adapter(select: select) }
    func makeNSView(context: Context) -> Popup {
        let button = Popup(frame: .zero, pullsDown: true)
        button.setAccessibilityIdentifier("editor.projectSwitcher")
        button.setContentHuggingPriority(.required, for: .horizontal)
        return button
    }
    func updateNSView(_ button: Popup, context: Context) {
        context.coordinator.select = select
        let configuration = Configuration(title: title, entries: entries, enabled: enabled,
                                          enabledIDs: Set(entries.flatMap(\.projects).filter { canSelect($0.id) }.map(\.id)))
        // Editor typing must not rebuild an unchanged native menu or toolbar.
        guard button.configuration != configuration else { return }
        button.configuration = configuration
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(NSMenuItem(title: title, action: nil, keyEquivalent: ""))
        for entry in entries {
            switch entry {
            case .project(let project): menu.addItem(item(project, adapter: context.coordinator))
            case .group(let label, let projects):
                let group = NSMenuItem(title: label, action: nil, keyEquivalent: "")
                let submenu = NSMenu(title: label)
                submenu.autoenablesItems = false
                for project in projects { submenu.addItem(item(project, adapter: context.coordinator)) }
                group.submenu = submenu
                menu.addItem(group)
            }
        }
        button.menu = menu
        button.isEnabled = enabled
        button.setAccessibilityLabel(String(localized: "Project: \(title)"))
        button.invalidateIntrinsicContentSize()
        button.scheduleToolbarLabelUpdate()
    }
    private func item(_ project: ProjectRecord, adapter: Adapter) -> NSMenuItem {
        let item = NSMenuItem(title: project.name, action: #selector(Adapter.choose(_:)), keyEquivalent: "")
        item.target = adapter
        item.representedObject = project.id.uuidString
        item.isEnabled = canSelect(project.id)
        return item
    }
    final class Popup: NSPopUpButton {
        var configuration: Configuration?
        private var toolbarLabelUpdatePending = false
        override func accessibilityPerformPress() -> Bool {
            guard isEnabled else { return false }
            performClick(nil)
            return true
        }
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); scheduleToolbarLabelUpdate() }
        func scheduleToolbarLabelUpdate() {
            guard !toolbarLabelUpdatePending else { return }
            toolbarLabelUpdatePending = true
            // AppKit attaches this popup while laying out its toolbar viewers.
            // Changing an item's label synchronously from that attachment
            // reenters NSToolbarItemViewer and raises an exception on macOS 15.
            // Wait for the current layout stack to return, including updates
            // requested by SwiftUI while it is reconciling the toolbar.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.toolbarLabelUpdatePending = false
                self.updateToolbarLabel()
            }
        }
        private func updateToolbarLabel() {
            guard let item = window?.toolbar?.items.first(where: { $0.itemIdentifier.rawValue.contains("project-switcher") }) else { return }
            let label = String(localized: "Project")
            if item.label != label { item.label = label }
            if item.paletteLabel != label { item.paletteLabel = label }
        }
    }
    final class Adapter: NSObject {
        var select: (UUID) -> Void
        init(select: @escaping (UUID) -> Void) { self.select = select }
        @objc func choose(_ sender: NSMenuItem) {
            guard let raw = sender.representedObject as? String, let id = UUID(uuidString: raw) else { return }
            select(id)
        }
    }
}
