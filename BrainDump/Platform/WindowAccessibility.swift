import AppKit

/// Keep decorative titlebar views from appearing as additional controls. The
/// native zoom/full-screen button retains its role, label, and action; its
/// internal image groups have no independent behavior.
@MainActor
enum WindowAccessibility {
    private static let configuredZoomButtons = NSHashTable<NSButton>.weakObjects()
    static func configure(_ window: NSWindow) {
        #if DEBUG
        // Pixel audits must not capture a window partway through its opening
        // transform while accessibility already reports its final coordinates.
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") { window.animationBehavior = .none }
        #endif
        if let zoom = window.standardWindowButton(.zoomButton) {
            if !configuredZoomButtons.contains(zoom) || zoom.accessibilityChildren()?.isEmpty == false {
                zoom.setAccessibilityChildren([])
                configuredZoomButtons.add(zoom)
            }
        }
    }
}
