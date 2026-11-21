import Foundation
import Testing

@Suite("Shared project list")
struct ProjectListTests {
    private func project(_ name: String, _ index: Int) -> ProjectRecord {
        ProjectRecord(id: UUID(), name: name, folder: AuthorizedFolder(path: "/\(index)", identity: FolderIdentity(device: 1, inode: UInt64(index)), bookmark: Data([1])))
    }

    @Test(arguments: [0, 15, 16, 31])
    func thresholdsAndCompleteness(count: Int) {
        let input = (0..<count).map { project("\(Character(UnicodeScalar(65 + $0 % 26)!)) name \($0)", $0) }
        let output = ProjectListBuilder(locale: Locale(identifier: "en_US")).build(input)
        #expect(Set(output.flatMap(\.projects).map(\.id)) == Set(input.map(\.id)))
        #expect(output.flatMap(\.projects).count == count)
        if count <= 15 { #expect(output.allSatisfy { if case .project = $0 { return true }; return false }) }
    }

    @Test func sameInitialIsNeverSplit() {
        let input = (0..<18).map { project("Apple \($0)", $0) }
        let output = ProjectListBuilder(locale: Locale(identifier: "en_US")).build(input)
        #expect(output.count == 1)
        guard case .group(let label, let items) = output.first else { Issue.record("Expected one group"); return }
        #expect(label == "Projects starting with A")
        #expect(items.count == 18)
    }

    @Test func mixedScriptsAndFallbackLabels() {
        let names = ["Alpha", "Beta", "Delta", "Echo", "Foxtrot", "Gamma", "Hotel", "India", "Juliet", "Kilo", "Lima", "Mike", "Москва", "Питер", "北京", "深圳", "123 notes", "★ Star"]
        let input = names.enumerated().map { project($0.element, $0.offset) }
        let output = ProjectListBuilder(locale: Locale(identifier: "en_US")).build(input)
        #expect(output.flatMap(\.projects).count == input.count)
        guard case .group(let label, let items) = output.last else { Issue.record("Expected fallback group"); return }
        #expect(label == "Other projects…")
        #expect(items.map(\.name).contains("123 notes"))
        #expect(items.map(\.name).contains("★ Star"))
        #expect(output.contains { if case .group(let label, let ps) = $0 { return label.hasPrefix("Projects ") && ps.count == 2 && ps.contains { $0.name == "Москва" } }; return false })
    }

    @Test func singleOrphanStaysDirectlyVisible() {
        let input = (0..<16).map { project("Alpha \($0)", $0) } + [project("9 Notes", 100)]
        let output = ProjectListBuilder(locale: Locale(identifier: "en_US")).build(input)
        #expect(output.contains { if case .project(let p) = $0 { return p.name == "9 Notes" }; return false })
        #expect(!output.contains { if case .group(let label, _) = $0 { return label == "Other projects…" }; return false })
    }

    @Test func localizedTiesAreDeterministic() {
        let input = ["Éclair", "eclair", "Alpha", "beta"].enumerated().map { project($0.element, $0.offset) }
        let builder = ProjectListBuilder(locale: Locale(identifier: "fr_FR"))
        #expect(builder.build(input) == builder.build(input.reversed()))
        #expect(builder.build(input).flatMap(\.projects).map(\.name).prefix(2) == ["Alpha", "beta"])
    }
}
