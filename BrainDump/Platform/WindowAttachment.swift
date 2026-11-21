import AppKit
import SwiftUI

/// Captures the actual enclosing window without relying on global window ordering.
struct WindowAttachment: NSViewRepresentable {
    let registry: WindowLifecycleRegistry
    let sessionID: UUID?

    func makeNSView(context: Context) -> AttachmentView {
        let view = AttachmentView()
        view.registry = registry
        view.sessionID = sessionID
        return view
    }

    func updateNSView(_ view: AttachmentView, context: Context) {
        view.registry = registry
        view.sessionID = sessionID
        view.configureWindow()
    }

    final class AttachmentView: NSView {
        weak var registry: WindowLifecycleRegistry?
        var sessionID: UUID?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            configureWindow()
        }

        func configureWindow() {
            guard let window else { return }
            window.isRestorable = false
            window.tabbingMode = .disallowed
            if let sessionID { registry?.attach(window, sessionID: sessionID) }
        }
    }
}
