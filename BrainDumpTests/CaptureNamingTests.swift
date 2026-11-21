import Foundation
import Testing

@Suite("UTC capture names")
struct CaptureNamingTests {
    nonisolated struct Example: Sendable {
        let iso: String
        let folder: String
        let stem: String
    }

    @Test(arguments: [
        Example(iso: "2019-12-30T23:59:59Z", folder: "2019-12", stem: "2019-12-30_23-59-59"),
        Example(iso: "2026-11-30T23:59:59Z", folder: "2026-11", stem: "2026-11-30_23-59-59"),
        Example(iso: "2026-12-01T00:00:00Z", folder: "2026-12", stem: "2026-12-01_00-00-00"),
        Example(iso: "2027-01-01T00:00:00Z", folder: "2027-01", stem: "2027-01-01_00-00-00")
    ])
    func calendarAndMonthBoundaries(example: Example) throws {
        let date = try #require(ISO8601DateFormatter().date(from: example.iso))
        let naming = CaptureNaming(firstSavedAt: date)
        #expect(naming.monthFolder == example.folder)
        #expect(naming.timestampStem == example.stem)
        #expect(naming.filename() == example.stem + ".md")
        #expect(naming.timestampStem.unicodeScalars.allSatisfy {
            (48...57).contains($0.value) || $0 == "-" || $0 == "_"
        })
    }

    @Test(arguments: [UInt(1), 9, 10, 99, 100, 1000])
    func collisionSuffixesExpandWithoutStacking(suffix: UInt) {
        let naming = CaptureNaming(firstSavedAt: Date(timeIntervalSince1970: 0))
        let expected = suffix < 10 ? "0\(suffix)" : String(suffix)
        #expect(naming.filename(suffix: suffix) == "1970-01-01_00-00-00_\(expected).md")
    }

    @Test(arguments: ["", " \t\r\n", "\u{00A0}"])
    func whitespaceIsEmpty(text: String) {
        let folder = AuthorizedFolder(path: "/fixtures", identity: FolderIdentity(device: 1, inode: 1), bookmark: Data([1]))
        #expect(CaptureWriteRequest(text: text, projectFolder: folder, binding: nil).isEmpty)
    }

    @Test func nonemptyContentIsNotTrimmed() {
        let folder = AuthorizedFolder(path: "/fixtures", identity: FolderIdentity(device: 1, inode: 1), bookmark: Data([1]))
        let request = CaptureWriteRequest(text: "  # Żółć 🧠\n\n", projectFolder: folder, binding: nil)
        #expect(!request.isEmpty)
        #expect(request.text == "  # Żółć 🧠\n\n")
    }
}
