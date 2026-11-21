import Foundation
import Testing

@Suite("Folder repair target identity", .timeLimit(.minutes(1)))
@MainActor
struct ProjectFolderDraftTests {
    @Test func pickerResultCannotAttachToAnotherSelectedProject() throws {
        let first = UUID(), second = UUID()
        let draft = ProjectFolderDraft(projectID: first)
        let request = try #require(draft.beginChoice())
        draft.select(second)
        #expect(!draft.accept(URL(fileURLWithPath: "/fixtures/renamed"), for: request))
        #expect(draft.projectID == second && draft.change == nil)
    }

    @Test func repeatedSelectionPreservesDraftAndStalePickerCannotReplaceIt() throws {
        let projectID = UUID()
        let draft = ProjectFolderDraft(projectID: projectID)
        let old = try #require(draft.beginChoice())
        let current = try #require(draft.beginChoice())
        let folder = URL(fileURLWithPath: "/fixtures/selected")
        #expect(!draft.accept(URL(fileURLWithPath: "/fixtures/stale"), for: old))
        #expect(draft.accept(folder, for: current))
        draft.select(projectID)
        #expect(draft.change == ProjectFolderDraft.Change(projectID: projectID, folder: folder))
        let cancelled = try #require(draft.beginChoice())
        draft.cancel(cancelled)
        #expect(!draft.accept(URL(fileURLWithPath: "/fixtures/cancelled"), for: cancelled))
        #expect(draft.change?.folder == folder)
    }

    @Test func submittedFolderRepairKeepsItsOriginalTarget() async throws {
        let f = try await CoordinatorFixture.make(); defer { f.cleanup() }
        let draft = ProjectFolderDraft(projectID: f.first.id)
        let request = try #require(draft.beginChoice())
        let replacement = URL(fileURLWithPath: "/fixtures/renamed-parent")
        #expect(draft.accept(replacement, for: request))
        let submitted = try #require(draft.change)
        draft.select(f.second.id)
        #expect(draft.change == nil)
        #expect(await f.coordinator.changeProjectFolder(submitted.projectID, selectedFolder: submitted.folder, mode: .keepOpen) == .completed)
        #expect(f.projects.projects.first(where: { $0.id == f.first.id })?.folder.path == replacement.path)
        #expect(f.projects.projects.first(where: { $0.id == f.second.id }) == f.second)
    }
}
