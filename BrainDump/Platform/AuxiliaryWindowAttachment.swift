import AppKit
import SwiftUI

/// Keep a submitted form present until its transaction returns; native titlebar
/// closure must not bypass the same busy guard as Cancel.
struct AuxiliaryWindowAttachment: NSViewRepresentable {
    var isBusy = false
    var closeRequested = false
    var canClose: @MainActor () -> Bool = { true }
    var onClose: @MainActor () -> Void = {}
    func makeNSView(context: Context) -> AttachmentView { AttachmentView() }
    func updateNSView(_ view: AttachmentView, context: Context) {
        view.isBusy = isBusy
        view.closeRequested = closeRequested
        view.canClose = canClose
        view.onClose = onClose
        view.configure()
    }

    final class AttachmentView: NSView {
        var isBusy = false
        var closeRequested = false
        private var closeTask: Task<Void, Never>?
        var canClose: @MainActor () -> Bool = { true }
        var onClose: @MainActor () -> Void = {}
        private var adapter: Delegate?
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); configure() }
        func configure() {
            guard let window else { return }
            WindowAccessibility.configure(window, contentLabel: window.title)
            window.isRestorable = false
            window.tabbingMode = .disallowed
            if adapter == nil {
                let original = (window.delegate as? Delegate)?.original ?? window.delegate
                let adapter = Delegate(original: original)
                self.adapter = adapter
                window.delegate = adapter
            }
            adapter?.canClose = canClose
            adapter?.onClose = onClose
            window.standardWindowButton(.closeButton)?.isEnabled = !isBusy
            if closeRequested, closeTask == nil {
                // Run after the SwiftUI update, using this exact native window.
                // A committed transaction must not be blocked by stale button
                // enabled state or the old form's should-close callback.
                closeTask = Task { @MainActor [weak window] in
                    window?.close()
                }
            }
        }
    }

    final class Delegate: NSObject, NSWindowDelegate {
        weak var original: (any NSWindowDelegate)?
        var canClose: @MainActor () -> Bool = { true }
        var onClose: @MainActor () -> Void = {}
        init(original: (any NSWindowDelegate)?) { self.original = original }
        func windowShouldClose(_ sender: NSWindow) -> Bool {
            canClose() && (original?.windowShouldClose?(sender) ?? true)
        }
        // Native closure owns visibility. SwiftUI onDisappear can also run
        // when a hidden scene's identified content is replaced, even though
        // its window remains open; treating that as closure discards drafts.
        func windowWillClose(_ notification: Notification) { original?.windowWillClose?(notification); onClose() }
        func windowDidBecomeKey(_ notification: Notification) { original?.windowDidBecomeKey?(notification) }
        func windowDidResignKey(_ notification: Notification) { original?.windowDidResignKey?(notification) }
        func windowDidBecomeMain(_ notification: Notification) { original?.windowDidBecomeMain?(notification) }
        func windowDidResignMain(_ notification: Notification) { original?.windowDidResignMain?(notification) }
        func windowDidMove(_ notification: Notification) { original?.windowDidMove?(notification) }
        func windowDidResize(_ notification: Notification) { original?.windowDidResize?(notification) }
        func windowWillStartLiveResize(_ notification: Notification) { original?.windowWillStartLiveResize?(notification) }
        func windowDidEndLiveResize(_ notification: Notification) { original?.windowDidEndLiveResize?(notification) }
    }
}
