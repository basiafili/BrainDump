#if DEBUG
import Foundation
import AppKit

/// Opt-in, Debug-only fixtures. Never falls back to the user's preferences.
/// UUID-scoped temporary files are authorized through a native folder panel.
@MainActor
final class UITestConfiguration {
    let token: UUID
    let scenario: String
    let defaults: UserDefaults
    let root: URL
    var cleanupRequested: Bool { ProcessInfo.processInfo.arguments.contains("--ui-cleanup") }
    private var rootAccess: URL?

    init(token: UUID, scenario: String, defaults: UserDefaults, root: URL) {
        self.token = token; self.scenario = scenario; self.defaults = defaults; self.root = root
    }

    static func fromLaunch() -> Self? {
        let environment = ProcessInfo.processInfo.environment
        guard ProcessInfo.processInfo.arguments.contains("--ui-testing") else { return nil }
        guard let raw = environment["BRAINDUMP_UI_TEST_ID"], let token = UUID(uuidString: raw) else {
            preconditionFailure("UI tests require a UUID-scoped isolated configuration")
        }
        let suite = "BrainDump.UITests.\(token.uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { preconditionFailure("Cannot create isolated UI-test preferences") }
        if ProcessInfo.processInfo.arguments.contains("--ui-cleanup") { defaults.removePersistentDomain(forName: suite) }
        guard let path = environment["BRAINDUMP_UI_ROOT"],
              URL(fileURLWithPath: path).lastPathComponent == token.uuidString else {
            preconditionFailure("UI tests require a UUID-scoped fixture root")
        }
        return Self(token: token, scenario: environment["BRAINDUMP_UI_SCENARIO"] ?? "empty", defaults: defaults,
                    root: URL(fileURLWithPath: path, isDirectory: true))
    }

    var writeHooks: CaptureWriteHooks {
        let root = root
        return CaptureWriteHooks { phase, _ in
            guard phase == .staged, FileManager.default.fileExists(atPath: root.appendingPathComponent("hold-saves").path) else { return }
            try Data().write(to: root.appendingPathComponent("save-staged"), options: .atomic)
            let deadline = Date().addingTimeInterval(30)
            // This runs on the writer actor, never on the UI actor. A bounded
            // file gate makes UI snapshot/read-only assertions deterministic.
            while FileManager.default.fileExists(atPath: root.appendingPathComponent("hold-saves").path) {
                guard Date() < deadline else { throw CocoaError(.fileWriteUnknown) }
                Thread.sleep(forTimeInterval: 0.02)
            }
        }
    }

    func prepare(projects: ProjectStore) async throws {
        NSApplication.shared.appearance = NSAppearance(named: ProcessInfo.processInfo.environment["BRAINDUMP_UI_APPEARANCE"] == "dark" ? .darkAqua : .aqua)
        // The runner owns the disposable root. Acquire real sandbox access via
        // the native panel once, and retain a bookmark for relaunch tests.
        if let data = defaults.data(forKey: "uiTestRootBookmark") {
            var stale = false
            let url = try URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI], bookmarkDataIsStale: &stale)
            guard url.standardizedFileURL.resolvingSymlinksInPath() == root.standardizedFileURL.resolvingSymlinksInPath() else { throw CocoaError(.fileReadNoPermission) }
            _ = url.startAccessingSecurityScopedResource()
            rootAccess = url
        } else {
            let panel = NSOpenPanel()
            panel.title = "Authorize UI Test Fixtures"
            panel.message = "Select the disposable XCTest fixture folder."
            panel.prompt = "Authorize Fixtures"
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.directoryURL = root
            guard await panel.begin() == .OK, let url = panel.url,
                  url.standardizedFileURL.resolvingSymlinksInPath() == root.standardizedFileURL.resolvingSymlinksInPath() else { throw CocoaError(.userCancelled) }
            _ = url.startAccessingSecurityScopedResource()
            rootAccess = url
            defaults.set(try url.bookmarkData(options: .withSecurityScope), forKey: "uiTestRootBookmark")
        }
        let manager = FileManager.default
        let marker = root.appendingPathComponent("ready.json")
        guard !manager.fileExists(atPath: marker.path) else { return }
        let names = ["Alpha", "Beta", "Replacement", "New", "Parent/Child", "Parent/ChildRenamed", "Parent/Child/Leaf"]
        for name in names { try manager.createDirectory(at: root.appendingPathComponent(name), withIntermediateDirectories: true) }
        // Relaunch retains test registry/window preferences and files.
        var ids: [String: String] = [:]
        if scenario != "empty" {
            let registrations = scenario == "nested" ? ["Parent", "Parent/Child", "Parent/Child/Leaf"] : ["Alpha", "Beta"]
            for name in registrations {
                let project = try await projects.register(name: name, selectedFolder: root.appendingPathComponent(name))
                ids[name] = project.id.uuidString
                if ids.count == 1 { try projects.recordOpened(project.id) }
            }
            if scenario == "many" {
                for index in 0..<35 {
                    let name = String(format: "Project %02d", index)
                    let folder = root.appendingPathComponent(name)
                    try manager.createDirectory(at: folder, withIntermediateDirectories: true)
                    let project = try await projects.register(name: name, selectedFolder: folder)
                    ids[name] = project.id.uuidString
                }
            }
            if scenario == "unavailable" { try manager.moveItem(at: root.appendingPathComponent("Alpha"), to: root.appendingPathComponent("AlphaMoved")) }
        }
        try JSONSerialization.data(withJSONObject: ids, options: [.sortedKeys]).write(to: marker, options: .atomic)
    }
}
#endif
