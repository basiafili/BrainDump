import XCTest

nonisolated final class SettingsUITests: BrainDumpUITestCase {
    @MainActor
    func testValidRowCommitsImmediatelyAndCancelDiscardsOnlyRemainingDraft() throws {
        let s = try launch()
        s.wait(s.editor)
        let alpha = s.currentEditor()
        try s.openProject("Alpha", newWindow: true)
        s.showSettings()
        try s.selectSettings("Alpha")
        s.replace(s.settings.textFields["settings.name"], with: "Renamed Alpha")
        try s.selectSettings("Beta")
        XCTAssertTrue(alpha.wait(for: \.title, toEqual: "Renamed Alpha - BrainDump - New Capture", timeout: 5))
        XCTAssertEqual(s.editors.matching(NSPredicate(format: "title BEGINSWITH %@", "Renamed Alpha -")).count, 2)
        s.replace(s.settings.textFields["settings.name"], with: "Discard Beta")
        s.settings.buttons["settings.cancel"].click()
        s.showSettings()
        try s.selectSettings("Beta")
        XCTAssertEqual(s.settings.textFields["settings.name"].value as? String, "Beta")
        try s.selectSettings("Alpha")
        XCTAssertEqual(s.settings.textFields["settings.name"].value as? String, "Renamed Alpha")
    }

    @MainActor
    func testInvalidDraftMovesSelectionAndBlocksOKUntilRepaired() throws {
        let s = try launch()
        s.wait(s.editor)
        s.showSettings()
        try s.selectSettings("Alpha")
        s.replace(s.settings.textFields["settings.name"], with: " beta ")
        try s.selectSettings("Beta")
        XCTAssertEqual(s.settings.textFields["settings.name"].value as? String, "Beta")
        XCTAssertFalse(s.settings.buttons["settings.ok"].isEnabled)
        let alphaRow = try s.row("Alpha", in: s.settings, prefix: "settings")
        XCTAssertTrue(s.accessibleText(alphaRow).contains("Draft name"))
        s.replace(s.settings.textFields["settings.name"], with: "Committed Beta")
        try s.selectSettings("Alpha")
        XCTAssertEqual(s.settings.textFields["settings.name"].value as? String, " beta ")
        s.replace(s.settings.textFields["settings.name"], with: "Alpha")
        XCTAssertTrue(s.settings.buttons["settings.ok"].wait(for: \.isEnabled, toEqual: true, timeout: 5))
        s.settings.buttons["settings.ok"].click()
        s.gone(s.settings)
        s.showSettings()
        try s.selectSettings("Beta")
        XCTAssertEqual(s.settings.textFields["settings.name"].value as? String, "Committed Beta")
    }

    @MainActor
    func testCancelledFolderDecisionRetainsWholeDraftAndOKAppliesAllDrafts() throws {
        let s = try launch()
        s.wait(s.editor)
        s.replace(s.text(), with: "alpha pending")
        s.showSettings()
        s.replace(s.settings.textFields["settings.name"], with: "Renamed Alpha")
        s.changeFolder("Replacement")
        try s.selectSettings("Beta")
        s.answerFolder("Cancel")
        XCTAssertEqual(s.settings.textFields["settings.name"].value as? String, "Beta")
        XCTAssertTrue(s.editor.title.hasPrefix("Alpha -"))
        s.replace(s.settings.textFields["settings.name"], with: "Renamed Beta")
        s.settings.buttons["settings.ok"].click()
        s.answerFolder("Keep captures open")
        s.gone(s.settings)
        XCTAssertTrue(s.editor.title.hasPrefix("Renamed Alpha -"))
        s.save()
        XCTAssertEqual(try s.contents(in: "Replacement"), ["alpha pending"])
        XCTAssertTrue(try s.markdown(in: "Alpha").isEmpty)
        s.showSettings()
        try s.selectSettings("Beta")
        XCTAssertEqual(s.settings.textFields["settings.name"].value as? String, "Renamed Beta")
    }

    @MainActor
    private func mixedCaptures(_ s: UITestSession) throws -> (XCUIElement, XCUIElement, XCUIElement, XCUIElement) {
        s.wait(s.editor)
        let clean = s.currentEditor()
        s.replace(s.text(in: clean), with: "clean baseline")
        s.save(in: clean)
        try s.openProject("Alpha", newWindow: true)
        let dirty = s.currentEditor()
        s.replace(s.text(in: dirty), with: "dirty baseline")
        s.save(in: dirty)
        s.replace(s.text(in: dirty), with: "dirty final")
        try s.openProject("Alpha", newWindow: true)
        let cleared = s.currentEditor()
        s.replace(s.text(in: cleared), with: "cleared baseline")
        s.save(in: cleared)
        s.replace(s.text(in: cleared), with: " \n")
        try s.openProject("Alpha", newWindow: true)
        let unbound = s.currentEditor()
        s.replace(s.text(in: unbound), with: "unbound final")
        s.countEditors(4)
        return (clean, dirty, cleared, unbound)
    }

    @MainActor
    func testKeepOpenFolderChangePreservesMixedBindingsAndAllTitles() throws {
        let s = try launch()
        let (clean, dirty, cleared, unbound) = try mixedCaptures(s)
        s.showSettings()
        s.replace(s.settings.textFields["settings.name"], with: "Renamed")
        s.changeFolder("Replacement")
        s.settings.buttons["settings.ok"].click()
        s.answerFolder("Keep captures open")
        s.gone(s.settings)
        s.countEditors(4)
        for window in [clean, dirty, cleared, unbound] { XCTAssertTrue(window.title.hasPrefix("Renamed -")) }
        s.save(in: dirty)
        s.activate(cleared); cleared.typeKey("s", modifierFlags: .command)
        s.save(in: unbound)
        XCTAssertEqual(try s.contents(in: "Alpha"), ["clean baseline", "cleared baseline", "dirty final"])
        XCTAssertEqual(try s.contents(in: "Replacement"), ["unbound final"])
        s.assertText(" \n", in: cleared)
    }

    @MainActor
    func testSaveAndCloseFolderChangeSavesMixedCapturesAtOldDestinations() throws {
        let s = try launch()
        _ = try mixedCaptures(s)
        s.showSettings()
        s.changeFolder("Replacement")
        s.settings.buttons["settings.ok"].click()
        s.answerFolder("Save and close captures")
        s.gone(s.settings)
        s.countEditors(0)
        XCTAssertEqual(try s.contents(in: "Alpha"), ["clean baseline", "cleared baseline", "dirty final", "unbound final"])
        XCTAssertTrue(try s.markdown(in: "Replacement").isEmpty)
        s.command("n")
        s.wait(s.editor)
        s.replace(s.text(), with: "new destination")
        s.save()
        XCTAssertEqual(try s.contents(in: "Replacement"), ["new destination"])
    }

    @MainActor
    func testRemovalCancelAndConfirmIgnoreInvalidDraftAndKeepFiles() throws {
        let s = try launch()
        _ = try mixedCaptures(s)
        s.showSettings()
        s.replace(s.settings.textFields["settings.name"], with: "")
        s.changeFolder("Replacement")
        s.settings.buttons["settings.remove"].click()
        s.wait(s.settings.buttons["Remove Project"])
        s.answerFolder("Cancel")
        s.countEditors(4)
        XCTAssertEqual(s.settings.textFields["settings.name"].value as? String, "")
        s.settings.buttons["settings.remove"].click()
        s.settings.buttons["Remove Project"].click()
        s.countEditors(0)
        s.gone(try s.row("Alpha", in: s.settings, prefix: "settings"))
        XCTAssertEqual(try s.contents(in: "Alpha"), ["clean baseline", "cleared baseline", "dirty final", "unbound final"])
        XCTAssertTrue(try s.markdown(in: "Replacement").isEmpty)
        s.command("w")
        s.relaunch()
        s.wait(s.new)
        s.countEditors(0) // Removing last active must not guess Beta.
    }

    @MainActor
    func testFolderSaveFailurePreservesDraftMetadataAndEditorsForRetry() throws {
        let s = try launch()
        s.wait(s.editor)
        s.replace(s.text(), with: "retained capture")
        s.showSettings()
        s.replace(s.settings.textFields["settings.name"], with: "Renamed")
        s.changeFolder("Replacement")
        try FileManager.default.moveItem(at: s.root.appendingPathComponent("Alpha"), to: s.root.appendingPathComponent("AlphaMoved"))
        s.settings.buttons["settings.ok"].click()
        s.answerFolder("Save and close captures")
        s.dismissFailure()
        s.countEditors(1)
        XCTAssertTrue(s.editor.title.hasPrefix("Alpha -"))
        s.assertText("retained capture")
        XCTAssertEqual(s.settings.textFields["settings.name"].value as? String, "Renamed")
        try FileManager.default.moveItem(at: s.root.appendingPathComponent("AlphaMoved"), to: s.root.appendingPathComponent("Alpha"))
        s.settings.buttons["settings.ok"].click()
        s.answerFolder("Save and close captures")
        s.gone(s.settings)
        s.countEditors(0)
        XCTAssertEqual(try s.contents(in: "Alpha"), ["retained capture"])
    }

    @MainActor
    func testUnavailableRegistrationCanBeRenamedThenRemovedWithoutFolderAccess() throws {
        let s = try launch("unavailable")
        s.wait(s.open)
        s.open.buttons["Project Settings…"].click()
        s.wait(s.settings.textFields["settings.name"])
        s.replace(s.settings.textFields["settings.name"], with: "Unavailable renamed")
        try s.selectSettings("Beta")
        try s.selectSettings("Alpha")
        XCTAssertEqual(s.settings.textFields["settings.name"].value as? String, "Unavailable renamed")
        XCTAssertFalse(s.settings.buttons["settings.reveal"].isEnabled)
        s.settings.buttons["settings.remove"].click()
        s.settings.buttons["Remove Project"].click()
        s.gone(try s.row("Alpha", in: s.settings, prefix: "settings"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: s.root.appendingPathComponent("AlphaMoved").path))
    }
    @MainActor
    func testLaterOKFailureRetainsEarlierSuccessfulProjectAndEditorClose() throws {
        let s = try launch()
        s.wait(s.editor)
        let alpha = s.currentEditor()
        s.replace(s.text(in: alpha), with: "alpha committed")
        try s.openProject("Beta", newWindow: true)
        let beta = s.currentEditor()
        s.replace(s.text(in: beta), with: "beta retained")
        s.showSettings()
        try s.selectSettings("Alpha")
        s.replace(s.settings.textFields["settings.name"], with: "Committed Alpha")
        s.changeFolder("Replacement")
        try s.selectSettings("Beta")
        s.answerFolder("Cancel")
        s.replace(s.settings.textFields["settings.name"], with: "Pending Beta")
        s.changeFolder("New")
        try s.selectSettings("Alpha")
        s.answerFolder("Cancel")
        try FileManager.default.moveItem(at: s.root.appendingPathComponent("Beta"), to: s.root.appendingPathComponent("BetaMoved"))
        s.settings.buttons["settings.ok"].click()
        s.answerFolder("Save and close captures")
        s.gone(alpha)
        s.answerFolder("Save and close captures")
        s.dismissFailure()
        s.countEditors(1)
        s.assertText("beta retained", in: beta)
        XCTAssertTrue(beta.title.hasPrefix("Beta -"))
        XCTAssertEqual(try s.contents(in: "Alpha"), ["alpha committed"])
        try s.selectSettings("Alpha")
        XCTAssertEqual(s.settings.textFields["settings.name"].value as? String, "Committed Alpha")
    }

    @MainActor
    func testCompetingFolderDraftIsRevalidatedAfterAnotherRowCommits() throws {
        let s = try launch()
        s.wait(s.editor)
        s.replace(s.text(), with: "keep A pending")
        s.showSettings()
        s.changeFolder("Replacement")
        try s.selectSettings("Beta")
        s.answerFolder("Cancel")
        s.changeFolder("Replacement")
        try s.selectSettings("Alpha") // Beta has no captures and commits now.
        XCTAssertFalse(s.settings.buttons["settings.ok"].isEnabled)
        XCTAssertTrue(try s.accessibleText(s.row("Alpha", in: s.settings, prefix: "settings")).contains("Beta"))
        s.changeFolder("New")
        XCTAssertTrue(s.settings.buttons["settings.ok"].wait(for: \.isEnabled, toEqual: true, timeout: 5))
    }

    @MainActor
    func testRemovalSaveFailureKeepsAllWindowsRegistrationAndDraft() throws {
        let s = try launch()
        _ = try mixedCaptures(s)
        s.showSettings()
        s.replace(s.settings.textFields["settings.name"], with: "Retained draft")
        try FileManager.default.moveItem(at: s.root.appendingPathComponent("Alpha"), to: s.root.appendingPathComponent("AlphaMoved"))
        s.settings.buttons["settings.remove"].click()
        s.settings.buttons["Remove Project"].click()
        s.dismissFailure()
        s.countEditors(4)
        s.wait(try s.row("Alpha", in: s.settings, prefix: "settings"))
        XCTAssertEqual(s.settings.textFields["settings.name"].value as? String, "Retained draft")
        try FileManager.default.moveItem(at: s.root.appendingPathComponent("AlphaMoved"), to: s.root.appendingPathComponent("Alpha"))
        s.settings.buttons["settings.remove"].click()
        s.settings.buttons["Remove Project"].click()
        s.countEditors(0)
        XCTAssertEqual(try s.contents(in: "Alpha"), ["clean baseline", "cleared baseline", "dirty final", "unbound final"])
    }

}
