import Foundation
import Testing

@Suite("Editor coordinator integration", .timeLimit(.minutes(1)))
@MainActor
struct EditorCoordinatorIntegrationTests {
    @Test func realWriterSavesCopiesAndClosesThroughTheSameWorkflow() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("BrainDumpCoordinatorIntegration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "BrainDumpCoordinatorTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let folders = FolderAuthorizationService()
        let projects = try ProjectStore(defaults: defaults, folders: folders)
        let project = try await projects.register(name: "Real", selectedFolder: root)
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let writer = CaptureFileWriter(folders: folders, now: { timestamp })
        let coordinator = EditorCoordinator(projects: projects, writer: writer)
        let session = try await coordinator.registerWindow(for: project.id)
        coordinator.updateText(session.id, text: "first")
        let original = try #require(await coordinator.save(session.id).savedBinding)
        #expect(try String(contentsOf: original.fileURL, encoding: .utf8) == "first")
        try Data("external edit".utf8).write(to: original.fileURL, options: .atomic)
        coordinator.updateText(session.id, text: "my edits")
        #expect(await coordinator.newCapture(session.id) == .completed)
        let naming = CaptureNaming(firstSavedAt: timestamp)
        let copy = original.fileURL.deletingLastPathComponent().appendingPathComponent(naming.filename(suffix: 1))
        #expect(try String(contentsOf: original.fileURL, encoding: .utf8) == "external edit")
        #expect(try String(contentsOf: copy, encoding: .utf8) == "my edits")
        #expect(session.text.isEmpty && session.binding == nil)
        coordinator.updateText(session.id, text: "next capture")
        let recent = projects.recentIDs, last = projects.lastActiveID
        #expect(await coordinator.prepareClose(session.id).windowIDs == [session.id])
        let closedBinding = try #require(session.binding)
        #expect(closedBinding.fileURL.lastPathComponent == naming.filename(suffix: 2))
        #expect(try String(contentsOf: closedBinding.fileURL, encoding: .utf8) == "next capture")
        #expect(coordinator.windowDidClose(session.id))
        #expect(projects.recentIDs == recent && projects.lastActiveID == last)
    }

    @Test func titleUsesLocaleAndLocalTimeWithoutRawFilenameStem() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let formatter = CaptureTitleFormatter()
        let utc = try #require(TimeZone(secondsFromGMT: 0))
        let shifted = try #require(TimeZone(secondsFromGMT: 3600))
        let english = formatter.title(projectName: "Project", firstSavedAt: date, locale: Locale(identifier: "en_US"), timeZone: utc)
        let local = formatter.title(projectName: "Project", firstSavedAt: date, locale: Locale(identifier: "en_US"), timeZone: shifted)
        let polish = formatter.title(projectName: "Project", firstSavedAt: date, locale: Locale(identifier: "pl_PL"), timeZone: utc)
        #expect(english != local && english != polish)
        #expect(english.hasPrefix("Project - BrainDump - "))
        #expect(!english.contains(CaptureNaming(firstSavedAt: date).timestampStem))
        #expect(formatter.title(projectName: "Project", firstSavedAt: nil, locale: Locale(identifier: "en_US")) == "Project - BrainDump - New Capture")
    }
}
