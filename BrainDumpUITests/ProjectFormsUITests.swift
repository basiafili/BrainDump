import XCTest

nonisolated final class ProjectFormsUITests: BrainDumpUITestCase {
    @MainActor
    func testFirstProjectCreationInExistingFolderClosesFormWithoutDuplicateError() throws {
        let s = try launch("empty")
        s.wait(s.new)
        s.countEditors(0)
        XCTAssertFalse(s.new.buttons["new.create"].isEnabled)
        s.replace(s.new.textFields["new.name"], with: "First Project")
        s.chooseFolder("New", from: s.new.buttons["new.chooseFolder"])
        s.setNewWindow(true, in: s.new, id: "new.openInNewWindow")
        s.new.buttons["new.create"].click()
        s.gone(s.new)
        s.countEditors(1)
        XCTAssertFalse(s.app.alerts.firstMatch.exists)
        XCTAssertTrue(s.editor.title.hasPrefix("First Project -"))
        s.replace(s.text(), with: "created successfully")
        s.save()
        XCTAssertEqual(try s.contents(in: "New"), ["created successfully"])
        s.showNew()
        XCTAssertEqual(s.new.checkBoxes["new.openInNewWindow"].value as? Int, 1)
        s.new.buttons["new.cancel"].click()
        s.relaunch()
        s.countEditors(1)
        XCTAssertTrue(s.editor.title.hasPrefix("First Project -"))
        s.showNew()
        XCTAssertEqual(s.new.checkBoxes["new.openInNewWindow"].value as? Int, 1)
    }

    @MainActor
    func testNameAndFolderValidationAndNewFormCancel() throws {
        let s = try launch()
        s.wait(s.editor)
        s.showNew()
        s.replace(s.new.textFields["new.name"], with: " alpha ")
        XCTAssertFalse(s.new.buttons["new.create"].isEnabled)
        s.replace(s.new.textFields["new.name"], with: "Unique")
        s.chooseFolder("Alpha", from: s.new.buttons["new.chooseFolder"],
                       expectingError: "This folder is already registered as a project.")
        XCTAssertFalse(s.new.buttons["new.create"].isEnabled)
        s.chooseFolder("New", from: s.new.buttons["new.chooseFolder"])
        XCTAssertTrue(s.new.buttons["new.create"].wait(for: \.isEnabled, toEqual: true, timeout: 5))
        s.new.buttons["new.cancel"].click()
        s.showSettings()
        XCTAssertFalse(s.settings.staticTexts["Unique"].exists)
        s.settings.buttons["settings.cancel"].click()
        s.countEditors(1)
    }

    @MainActor
    func testOpenDoubleClickAndBothFormCheckboxesRememberIndependently() throws {
        let s = try launch()
        s.wait(s.editor)
        try s.openProject("Beta", newWindow: true, doubleClick: true)
        s.countEditors(2)
        s.showOpen()
        XCTAssertEqual(s.open.checkBoxes["open.openInNewWindow"].value as? Int, 1)
        s.command("w")
        s.gone(s.open)
        s.countEditors(2)
        s.showNew()
        s.setNewWindow(false, in: s.new, id: "new.openInNewWindow")
        s.new.buttons["new.cancel"].click()
        s.relaunch()
        s.countEditors(1)
        s.showOpen()
        XCTAssertEqual(s.open.checkBoxes["open.openInNewWindow"].value as? Int, 1)
        s.command("w")
        s.showNew()
        XCTAssertEqual(s.new.checkBoxes["new.openInNewWindow"].value as? Int, 0)
    }

    @MainActor
    func testUnavailableLastActiveOpensActionableOpenWindowAndRepairClearsError() throws {
        let s = try launch("unavailable")
        s.wait(s.open)
        s.countEditors(0)
        XCTAssertFalse(try s.row("Alpha", in: s.open, prefix: "open").exists)
        XCTAssertTrue(try s.row("Beta", in: s.open, prefix: "open").exists)
        XCTAssertFalse(s.app.alerts.firstMatch.exists)
        s.open.buttons["Project Settings…"].click()
        s.wait(s.settings)
        XCTAssertEqual(s.settings.textFields["settings.name"].value as? String, "Alpha")
        XCTAssertFalse(s.settings.buttons["settings.reveal"].isEnabled)
        s.changeFolder("AlphaMoved")
        s.settings.buttons["settings.ok"].click()
        s.gone(s.settings)
        s.wait(try s.row("Alpha", in: s.open, prefix: "open"))
        s.relaunch()
        s.countEditors(1)
        XCTAssertTrue(s.editor.title.hasPrefix("Alpha -"))
    }

    @MainActor
    func testNestedRenamedRegistrationRepairsItselfWithoutFolderInUseError() throws {
        let s = try launch("nested")
        s.wait(s.editor)
        let old = s.root.appendingPathComponent("Parent/Child")
        let renamed = s.root.appendingPathComponent("Parent/ActualRenamed")
        try FileManager.default.moveItem(at: old, to: renamed)
        s.showSettings()
        try s.selectSettings("Parent/Child")
        s.changeFolder("Parent/ActualRenamed")
        s.settings.buttons["settings.ok"].click()
        s.gone(s.settings)
        s.showSettings()
        try s.selectSettings("Parent/Child")
        XCTAssertTrue(s.settings.staticTexts.matching(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", renamed.path, renamed.path)).count > 0)
        XCTAssertTrue(s.settings.buttons["settings.reveal"].wait(for: \.isEnabled, toEqual: true, timeout: 5))
    }

    @MainActor
    func testNewProjectOriginSurvivesOpenToNewAndAnotherEditorActivation() throws {
        let s = try launch()
        s.wait(s.editor)
        let alpha = s.currentEditor()
        s.replace(s.text(in: alpha), with: "original target")
        try s.openProject("Beta", newWindow: true)
        s.countEditors(2)
        let beta = s.editors.matching(NSPredicate(format: "title BEGINSWITH %@", "Beta -")).firstMatch
        s.activate(alpha)
        s.showOpen()
        s.open.buttons["New Project"].click()
        s.gone(s.open)
        s.wait(s.new)
        s.replace(s.new.textFields["new.name"], with: "Third")
        s.activate(beta)
        s.activate(s.new)
        XCTAssertEqual(s.new.textFields["new.name"].value as? String, "Third", "Raising New Project must retain its draft")
        s.chooseFolder("New", from: s.new.buttons["new.chooseFolder"])
        s.setNewWindow(false, in: s.new, id: "new.openInNewWindow")
        s.new.buttons["new.create"].click()
        s.gone(s.new)
        s.countEditors(2)
        XCTAssertEqual(try s.contents(in: "Alpha"), ["original target"])
        XCTAssertTrue(beta.exists)
        XCTAssertTrue(s.editors.matching(NSPredicate(format: "title BEGINSWITH %@", "Third -")).firstMatch.exists)
    }
}
