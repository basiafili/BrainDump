import AppKit
import SwiftUI

/// TextEditor does not expose Markdown substitutions or a per-capture native
/// undo manager on macOS 15. Keep only those native editing concerns here.
struct CaptureTextEditor: NSViewRepresentable {
    let session: EditorSession
    let coordinator: EditorCoordinator

    func makeCoordinator() -> Adapter { Adapter(session: session, coordinator: coordinator) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = CaptureScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        let text = CaptureTextView()
        text.delegate = context.coordinator
        text.isRichText = false
        text.importsGraphics = false
        text.allowsUndo = true
        text.isAutomaticQuoteSubstitutionEnabled = false
        text.isAutomaticDashSubstitutionEnabled = false
        text.isAutomaticTextReplacementEnabled = false
        text.isAutomaticLinkDetectionEnabled = false
        text.isAutomaticDataDetectionEnabled = false
        text.isAutomaticSpellingCorrectionEnabled = false
        text.isAutomaticTextCompletionEnabled = false
        text.inlinePredictionType = .no
        text.mathExpressionCompletionType = .no
        text.isContinuousSpellCheckingEnabled = true
        text.usesFindBar = false
        text.isIncrementalSearchingEnabled = false
        text.font = .monospacedSystemFont(ofSize: NSFont.preferredFont(forTextStyle: .body).pointSize, weight: .regular)
        text.textColor = .textColor
        text.backgroundColor = .textBackgroundColor
        text.textContainerInset = NSSize(width: 16, height: 16)
        text.isVerticallyResizable = true
        text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]
        text.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        text.textContainer?.widthTracksTextView = true
        text.textContainer?.containerSize = NSSize(width: scroll.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        text.setAccessibilityLabel(String(localized: "Capture text"))
        text.setAccessibilityIdentifier("editor.text")
        scroll.setAccessibilityLabel(String(localized: "Capture text area"))
        scroll.setAccessibilityIdentifier("editor.scroll")
        scroll.documentView = text
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let text = scroll.documentView as? CaptureTextView else { return }
        text.isEditable = !session.isReadOnly
        if text.string != session.text { text.string = session.text }
        if text.focusRequestID != session.focusRequestID {
            text.focusRequestID = session.focusRequestID
            text.needsEditorFocus = true
            text.focusIfNeeded()
        }
    }

    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Adapter) {
        guard let text = scroll.documentView as? CaptureTextView else { return }
        text.delegate = nil
        text.undoManager?.removeAllActions()
    }

    final class Adapter: NSObject, NSTextViewDelegate {
        let session: EditorSession
        let coordinator: EditorCoordinator
        init(session: EditorSession, coordinator: EditorCoordinator) {
            self.session = session
            self.coordinator = coordinator
        }
        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            if !coordinator.updateText(session.id, text: view.string) { view.string = session.text }
        }
        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            !session.isReadOnly
        }
    }

    final class CaptureTextView: NSTextView {
        private let captureUndoManager = UndoManager()
        var focusRequestID: UUID?
        var needsEditorFocus = false
        override var undoManager: UndoManager? { captureUndoManager }
        @objc func undo(_ sender: Any?) {
            guard isEditable, captureUndoManager.canUndo else { return }
            captureUndoManager.undo()
        }
        @objc func redo(_ sender: Any?) {
            guard isEditable, captureUndoManager.canRedo else { return }
            captureUndoManager.redo()
        }
        override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
            if item.action == #selector(undo(_:)) { return isEditable && captureUndoManager.canUndo }
            if item.action == #selector(redo(_:)) { return isEditable && captureUndoManager.canRedo }
            return super.validateUserInterfaceItem(item)
        }
        override func paste(_ sender: Any?) { super.pasteAsPlainText(sender) }
        override func performFindPanelAction(_ sender: Any?) { /* Capture app has no Find/Replace workflow. */ }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            focusIfNeeded()
        }
        func focusIfNeeded() {
            guard needsEditorFocus, let window else { return }
            if window.makeFirstResponder(self) { needsEditorFocus = false }
        }
    }

    final class CaptureScrollView: NSScrollView {
        override func tile() {
            super.tile()
            guard let text = documentView as? NSTextView else { return }
            text.minSize = NSSize(width: 0, height: contentSize.height)
            text.setFrameSize(NSSize(width: contentSize.width, height: max(text.frame.height, contentSize.height)))
        }
    }
}
