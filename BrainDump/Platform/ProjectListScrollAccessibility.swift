import AppKit
import SwiftUI

/// SwiftUI's List label can belong to its table rather than the enclosing
/// native scroll area. Give that scroll area its own useful VoiceOver label.
struct ProjectListScrollAccessibility: NSViewRepresentable {
    func makeNSView(context: Context) -> Marker { Marker() }
    func updateNSView(_ view: Marker, context: Context) { view.labelScrollArea() }

    final class Marker: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            labelScrollArea()
        }
        func labelScrollArea() {
            // Wait for SwiftUI to install the table and scroll view hierarchy.
            Task { @MainActor [weak self] in
                guard let self, let content = self.window?.contentView else { return }
                if let scroll = self.enclosingScrollView ?? self.firstScroll(in: content) {
                    scroll.setAccessibilityLabel(String(localized: "Available projects"))
                    scroll.setAccessibilityIdentifier("open.projectScrollArea")
                }
            }
        }
        private func firstScroll(in view: NSView) -> NSScrollView? {
            if let scroll = view as? NSScrollView { return scroll }
            for child in view.subviews { if let scroll = firstScroll(in: child) { return scroll } }
            return nil
        }
    }
}
