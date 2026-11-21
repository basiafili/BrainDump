import XCTest

nonisolated final class CaptureUITests: BrainDumpUITestCase {
    @MainActor
    func testSaveUpdatesExactTextAndNewCaptureResetsUndo() throws {
        let s = try launch()
        s.wait(s.editor)
        XCTAssertTrue(s.editor.title.contains("New Capture"))
        s.replace(s.text(), with: "# Markdown\n\n  exact text  ")
        s.save()
        let first = try XCTUnwrap(s.markdown(in: "Alpha").first)
        let title = s.editor.title
        XCTAssertFalse(title.contains("New Capture"))
        s.replace(s.text(), with: "updated")
        s.save()
        XCTAssertEqual(try s.markdown(in: "Alpha"), [first])
        XCTAssertEqual(try String(contentsOf: first, encoding: .utf8), "updated")
        XCTAssertEqual(s.editor.title, title)
        s.replace(s.text(), with: "saved before clear")
        s.command("n")
        s.assertText("")
        s.command("z")
        s.assertText("")
        XCTAssertTrue(s.editor.title.contains("New Capture"))
        XCTAssertEqual(try String(contentsOf: first, encoding: .utf8), "saved before clear")
    }

    @MainActor
    func testEmptySaveAndClearedBoundCapturePreserveFile() throws {
        let s = try launch()
        s.wait(s.editor)
        s.replace(s.text(), with: " \n ")
        s.command("s")
        XCTAssertTrue(try s.markdown(in: "Alpha").isEmpty)
        s.replace(s.text(), with: "keep on disk")
        s.save()
        s.replace(s.text(), with: " \n ")
        s.command("s")
        s.command("n")
        s.assertText("")
        XCTAssertEqual(try s.contents(in: "Alpha"), ["keep on disk"])
    }

    @MainActor
    func testExternalRenameDeletionAndEditCreateExpectedCopies() throws {
        let s = try launch()
        s.wait(s.editor)
        s.replace(s.text(), with: "baseline")
        s.save()
        let original = try XCTUnwrap(s.markdown(in: "Alpha").first)
        let renamed = original.deletingLastPathComponent().appendingPathComponent("renamed.md")
        try FileManager.default.moveItem(at: original, to: renamed)
        s.replace(s.text(), with: "recreated at original name")
        s.save()
        XCTAssertEqual(try String(contentsOf: renamed, encoding: .utf8), "baseline")
        XCTAssertEqual(try String(contentsOf: original, encoding: .utf8), "recreated at original name")
        try FileManager.default.removeItem(at: original)
        s.replace(s.text(), with: "recreated after deletion")
        s.save()
        XCTAssertEqual(try String(contentsOf: original, encoding: .utf8), "recreated after deletion")
        try "external content".write(to: original, atomically: true, encoding: .utf8)
        s.replace(s.text(), with: "my separate copy")
        s.save()
        XCTAssertEqual(try String(contentsOf: original, encoding: .utf8), "external content")
        XCTAssertEqual(try s.markdown(in: "Alpha").count, 3)
        s.replace(s.text(), with: "updates the copy")
        s.save()
        XCTAssertEqual(try s.markdown(in: "Alpha").count, 3)
        XCTAssertEqual(try s.contents(in: "Alpha"), ["baseline", "external content", "updates the copy"])
    }

    @MainActor
    func testManualSaveAllowsTypingWithoutLosingNewerText() throws {
        let s = try launch()
        s.wait(s.editor)
        s.replace(s.text(), with: "snapshot")
        try s.holdSaves()
        s.command("s")
        try s.waitForStagedSave()
        s.replace(s.text(), with: "newer text")
        try s.releaseSaves()
        s.assertText("newer text")
        s.assertStatus("Unsaved changes.")
        XCTAssertEqual(try s.contents(in: "Alpha"), ["snapshot"])
        s.save()
        XCTAssertEqual(try s.contents(in: "Alpha"), ["newer text"])
    }

    @MainActor
    func testCloseWaitsForSaveAndFailureRestoresEditing() throws {
        let s = try launch()
        s.wait(s.editor)
        s.replace(s.text(), with: "close only after save")
        try s.holdSaves()
        s.command("w")
        try s.waitForStagedSave()
        s.wait(s.editor)
        XCTAssertFalse(s.editor.buttons["New Capture"].isEnabled)
        let status = s.element("editor.status", in: s.editor)
        XCTAssertTrue((status.value as? String ?? status.label).contains("read-only"))
        try s.releaseSaves()
        s.countEditors(0)
        XCTAssertEqual(try s.contents(in: "Alpha"), ["close only after save"])
        s.command("n")
        s.wait(s.editor)
        s.replace(s.text(), with: "retained after failure")
        try FileManager.default.moveItem(at: s.root.appendingPathComponent("Alpha"), to: s.root.appendingPathComponent("AlphaMoved"))
        s.command("w")
        s.dismissFailure()
        s.countEditors(1)
        s.assertText("retained after failure")
        s.replace(s.text(), with: "editing restored")
        s.assertText("editing restored")
        try FileManager.default.moveItem(at: s.root.appendingPathComponent("AlphaMoved"), to: s.root.appendingPathComponent("Alpha"))
        s.command("w")
        s.countEditors(0)
    }

    @MainActor
    func testQuitFailureKeepsEveryWindowAndSuccessfulQuitDoesNotRestoreThem() throws {
        let s = try launch()
        s.wait(s.editor)
        s.replace(s.text(), with: "alpha quit")
        try s.openProject("Beta", newWindow: true)
        s.countEditors(2)
        let beta = s.editors.matching(NSPredicate(format: "title BEGINSWITH %@", "Beta -")).firstMatch
        s.replace(s.text(in: beta), with: "beta quit")
        try FileManager.default.moveItem(at: s.root.appendingPathComponent("Beta"), to: s.root.appendingPathComponent("BetaMoved"))
        s.command("q")
        s.dismissFailure()
        s.countEditors(2)
        s.assertText("beta quit", in: beta)
        try FileManager.default.moveItem(at: s.root.appendingPathComponent("BetaMoved"), to: s.root.appendingPathComponent("Beta"))
        s.command("q")
        XCTAssertTrue(s.app.wait(for: .notRunning, timeout: 10))
        XCTAssertEqual(try s.contents(in: "Alpha"), ["alpha quit"])
        XCTAssertEqual(try s.contents(in: "Beta"), ["beta quit"])
        s.app.launch()
        s.countEditors(1)
        s.assertText("")
        XCTAssertTrue(s.editor.title.hasPrefix("Beta -"))
        XCTAssertFalse(s.help.exists)
    }
    @MainActor
    func testThinkingTimeDoesNotAddHintsOrInterruptEditing() throws {
        let s = try launch()
        s.wait(s.editor)
        s.replace(s.text(), with: "Thinking")
        let hints = s.editor.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'hint' OR value CONTAINS[c] 'hint' OR label CONTAINS[c] 'idle' OR value CONTAINS[c] 'idle'"))
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "count > 0"), object: hints)
        expectation.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 10), .completed)
        // Type without clicking again: an unsolicited focus move loses this text.
        s.text().typeText(" continues")
        s.assertText("Thinking continues")
        XCTAssertFalse(s.app.alerts.firstMatch.exists)
    }

    @MainActor
    func testDirectTypingPreservesWordsMarkdownAndUndoRedo() throws {
        let s = try launch()
        s.wait(s.editor)
        let expected = "recreated after deletion -- \"quoted\" 2+2="
        s.text().click()
        s.text().typeText(expected)
        s.assertText(expected)
        s.command("a")
        s.text().typeKey(.delete, modifierFlags: [])
        s.assertText("")
        s.command("z")
        s.assertText(expected)
        s.command("z", modifiers: [.command, .shift])
        s.assertText("")
    }

}
