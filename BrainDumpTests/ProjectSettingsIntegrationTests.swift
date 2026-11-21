import Foundation
import Testing

@Suite("Settings file preservation", .timeLimit(.minutes(1)))
@MainActor
struct ProjectSettingsIntegrationTests {
    @Test func mixedKeepOpenThenRemovalKeepsEveryFileAtItsOriginalDestination() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("BrainDumpSettingsIntegration-\(UUID().uuidString)")
        let old = root.appendingPathComponent("Old"), new = root.appendingPathComponent("New")
        for folder in [old, new] { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "BrainDumpSettingsIntegration.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let folders = FolderAuthorizationService()
        let projects = try ProjectStore(defaults: defaults, folders: folders)
        let record = try await projects.register(name: "Original", selectedFolder: old)
        let writer = CaptureFileWriter(folders: folders, now: { Date(timeIntervalSince1970: 1_700_000_000) })
        let coordinator = EditorCoordinator(projects: projects, writer: writer)
        let clean = try await coordinator.registerWindow(for: record.id)
        let dirty = try await coordinator.registerWindow(for: record.id)
        let cleared = try await coordinator.registerWindow(for: record.id)
        let unbound = try await coordinator.registerWindow(for: record.id)
        for (session, text) in [(clean, "clean baseline"), (dirty, "dirty baseline"), (cleared, "keep cleared file")] {
            coordinator.updateText(session.id, text: text)
            _ = await coordinator.save(session.id)
        }
        let cleanBinding = try #require(clean.binding), dirtyBinding = try #require(dirty.binding), clearedBinding = try #require(cleared.binding)
        coordinator.updateText(dirty.id, text: "updated bound text")
        coordinator.updateText(cleared.id, text: " \n")
        coordinator.updateText(unbound.id, text: "unbound text")
        let folder = try await projects.authorizeReplacementFolder(record.id, selectedFolder: new)
        let change = ProjectSettingsChange(projectID: record.id, name: "Renamed", folder: folder)
        #expect(await coordinator.applyProjectSettings(change, mode: .keepOpen) == .completed)
        #expect(clean.binding == cleanBinding && dirty.binding == dirtyBinding && cleared.binding == clearedBinding)
        #expect(try Data(contentsOf: dirtyBinding.fileURL) == dirtyBinding.baseline)
        #expect(await coordinator.save(cleared.id) == .empty)
        #expect(try Data(contentsOf: clearedBinding.fileURL) == clearedBinding.baseline)
        _ = await coordinator.save(dirty.id)
        _ = await coordinator.save(unbound.id)
        let newBinding = try #require(unbound.binding)
        #expect(newBinding.folder.path == new.path && dirty.binding?.fileURL == dirtyBinding.fileURL)
        let result = await coordinator.removeProject(record.id)
        #expect(result.windowIDs == [clean.id, dirty.id, cleared.id, unbound.id])
        #expect(projects.projects.isEmpty && projects.recentIDs.isEmpty && projects.lastActiveID == nil)
        #expect(try String(contentsOf: cleanBinding.fileURL, encoding: .utf8) == "clean baseline")
        #expect(try String(contentsOf: dirtyBinding.fileURL, encoding: .utf8) == "updated bound text")
        #expect(try String(contentsOf: clearedBinding.fileURL, encoding: .utf8) == "keep cleared file")
        #expect(try String(contentsOf: newBinding.fileURL, encoding: .utf8) == "unbound text")
        for session in [clean, dirty, cleared, unbound] { #expect(coordinator.windowDidClose(session.id)) }
        #expect(coordinator.sessions.isEmpty)
    }
}
