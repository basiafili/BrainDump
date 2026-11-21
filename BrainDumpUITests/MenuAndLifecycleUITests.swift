import XCTest
import AppKit

nonisolated final class MenuAndLifecycleUITests: BrainDumpUITestCase {
    @MainActor
    func testCommandWClosesOnlyAuxiliaryWindowAndAppRemainsUsableWithNoWindows() throws {
        let s = try launch()
        s.wait(s.editor)
        s.replace(s.text(), with: "editor stays")
        s.showSettings(); s.command("w"); s.gone(s.settings)
        s.countEditors(1)
        s.assertText("editor stays")
        s.showHelp(); s.command("w"); s.gone(s.help)
        s.countEditors(1)
        s.command("w"); s.countEditors(0)
        XCTAssertNotEqual(s.app.state, .notRunning)
        s.showNew(); s.wait(s.new)
    }

    @MainActor
    func testMenusOmitFormatFindAndTabsAndToolbarFitsMinimumWidth() throws {
        let s = try launch()
        s.wait(s.editor)
        XCTAssertGreaterThanOrEqual(s.editor.frame.width, 1340)
        for title in ["New Capture", "New Project", "Open Project", "Save", "Cut", "Copy", "Paste"] {
            XCTAssertTrue(s.editor.toolbars.buttons[title].isHittable, "Toolbar action hidden: \(title)")
        }
        XCTAssertFalse(s.app.menuBars.menuBarItems["Format"].exists)
        s.app.menuBars.menuBarItems["Edit"].click()
        XCTAssertFalse(s.app.menuItems["Find…"].exists)
        XCTAssertFalse(s.app.menuItems["Replace…"].exists)
        s.app.typeKey(.escape, modifierFlags: [])
        s.app.menuBars.menuBarItems["File"].click()
        XCTAssertFalse(s.app.menuBars.menuBarItems["File"].menuItems["New Window"].exists)
        s.app.typeKey(.escape, modifierFlags: [])
        s.app.menuBars.menuBarItems["Window"].click()
        for label in ["New Project", "Open Project", "Project Settings", "BrainDump Help"] {
            XCTAssertFalse(s.app.menuBars.menuBarItems["Window"].menuItems[label].exists, "Implicit scene creation bypasses routing: \(label)")
        }
        for label in ["Merge All Windows", "Show Tab Bar", "Show All Tabs", "Move Tab to New Window"] { XCTAssertFalse(s.app.menuItems[label].exists) }
        s.app.typeKey(.escape, modifierFlags: [])
    }

    @MainActor
    func testNativeEditingAndUndoTargetFormFieldInsteadOfEditor() throws {
        let s = try launch()
        s.wait(s.editor)
        s.replace(s.text(), with: "untouched editor")
        s.showNew()
        let field = s.new.textFields["new.name"]
        let originalClipboard = UITestClipboardSnapshot()
        s.replace(field, with: "Native field")
        s.command("a"); s.command("x")
        let cutChange = NSPasteboard.general.changeCount
        defer { originalClipboard.restore(ifUnchangedSince: cutChange) }
        XCTAssertEqual(field.value as? String, "")
        s.command("v")
        XCTAssertEqual(field.value as? String, "Native field")
        s.command("z")
        XCTAssertEqual(field.value as? String, "")
        s.command("z", modifiers: [.command, .shift])
        XCTAssertEqual(field.value as? String, "Native field")
        s.new.buttons["new.cancel"].click()
        s.assertText("untouched editor")
    }

    @MainActor
    func testGlobalPreferencePersistsButToolbarSwitcherAlwaysReusesItsEditor() throws {
        let s = try launch()
        s.wait(s.editor)
        s.replace(s.text(), with: "saved before menu reuse")
        s.menu("Projects", item: "Beta")
        s.countEditors(1)
        s.assertText("")
        XCTAssertTrue(s.editor.title.hasPrefix("Beta -"))
        XCTAssertEqual(try s.contents(in: "Alpha"), ["saved before menu reuse"])
        s.menu("Projects", item: "Always Open in New Window")
        s.menu("Projects", item: "Alpha")
        s.countEditors(2)
        let target = s.currentEditor()
        s.replace(s.text(in: target), with: "switcher reuse")
        let switcher = s.element("editor.projectSwitcher", in: target)
        switcher.click()
        switcher.menuItems["Beta"].click()
        s.countEditors(2)
        s.assertText("", in: target)
        XCTAssertTrue(target.title.hasPrefix("Beta -"))
        s.relaunch()
        s.countEditors(1)
        s.menu("Projects", item: "Alpha")
        s.countEditors(2)
        // Per-form memory remains independent of this persisted global toggle.
    }

    @MainActor
    func testHelpPreservesMostRecentEditorForCommandsAndClearingRecentsKeepsLastActive() throws {
        let s = try launch()
        s.wait(s.editor)
        let alpha = s.currentEditor()
        try s.openProject("Beta", newWindow: true)
        let beta = s.currentEditor()
        s.replace(s.text(in: beta), with: "beta unchanged")
        s.activate(alpha)
        s.replace(s.text(in: alpha), with: "save from Help")
        s.showHelp()
        s.command("s")
        s.assertStatus("Capture saved.", in: alpha)
        s.command("n")
        s.assertText("", in: alpha)
        s.assertText("beta unchanged", in: beta)
        s.app.menuBars.menuBarItems["File"].click()
        let recent = s.app.menuBars.menuBarItems["File"].menuItems["Open Recent"]
        recent.hover()
        recent.menuItems["Clear Menu"].click()
        s.relaunch()
        s.countEditors(1)
        XCTAssertTrue(s.editor.title.hasPrefix("Alpha -"))
        s.app.menuBars.menuBarItems["File"].click()
        recent.hover()
        XCTAssertFalse(recent.menuItems["Alpha"].exists)
        XCTAssertFalse(recent.menuItems["Beta"].exists)
        s.app.typeKey(.escape, modifierFlags: [])
        s.app.typeKey(.escape, modifierFlags: [])
        s.showSettings()
        s.wait(try s.row("Alpha", in: s.settings, prefix: "settings"))
        s.wait(try s.row("Beta", in: s.settings, prefix: "settings"))
    }

    @MainActor
    func testProjectGroupingLabelsAndOpenListKeepFullNames() throws {
        let s = try launch("many")
        s.wait(s.editor)
        s.app.menuBars.menuBarItems["Projects"].click()
        let grouped = s.app.menuBars.menuBarItems["Projects"].menuItems.matching(NSPredicate(format: "label BEGINSWITH %@ OR title BEGINSWITH %@", "Projects ", "Projects "))
        XCTAssertGreaterThan(grouped.count, 0)
        s.app.typeKey(.escape, modifierFlags: [])
        s.showOpen()
        let scroll = s.open.scrollViews["open.projectScrollArea"]
        s.wait(scroll)
        XCTAssertEqual(scroll.label, "Available projects")
        let first = try s.row("Project 00", in: s.open, prefix: "open")
        s.wait(first)
        XCTAssertTrue(s.accessibleText(first).contains("Project 00"))
        XCTAssertTrue(s.accessibleText(first).contains(s.root.path))
    }

    @MainActor
    func testOriginFallbackAfterOriginalEditorCloses() throws {
        let s = try launch()
        s.wait(s.editor)
        let alpha = s.currentEditor()
        try s.openProject("Beta", newWindow: true)
        let beta = s.currentEditor()
        s.activate(alpha); s.showOpen()
        s.activate(alpha); alpha.typeKey("w", modifierFlags: .command)
        s.gone(alpha)
        s.activate(s.open)
        s.setNewWindow(false, in: s.open, id: "open.openInNewWindow")
        try s.row("Alpha", in: s.open, prefix: "open").click()
        s.open.buttons["open.open"].click()
        s.gone(s.open)
        s.countEditors(1)
        XCTAssertTrue(beta.title.hasPrefix("Alpha -"))
    }

    @MainActor
    func testRevealUsesCommittedFolderWithoutApplyingSettingsDraft() throws {
        let s = try launch()
        s.wait(s.editor)
        s.showSettings()
        s.changeFolder("Replacement")
        s.replace(s.settings.textFields["settings.name"], with: "Unapplied")
        s.settings.buttons["settings.reveal"].click()
        let finder = XCUIApplication(bundleIdentifier: "com.apple.finder")
        XCTAssertTrue(finder.wait(for: .runningForeground, timeout: 8))
        let window = finder.windows[s.token.uuidString]
        addTeardownBlock { await MainActor.run { if window.exists { window.buttons["_XCUI:CloseWindow"].click() } } }
        s.wait(window)
        let selected = window.descendants(matching: .any).matching(NSPredicate(format: "selected == YES"))
        s.wait(selected.firstMatch)
        let selectedDescriptions = selected.allElementsBoundByIndex.map(\.debugDescription).joined(separator: "\n")
        XCTAssertTrue(selectedDescriptions.contains("Alpha"), "Finder selected the wrong folder: \(selectedDescriptions)")
        window.typeKey("w", modifierFlags: .command)
        s.app.activate()
        s.settings.buttons["settings.cancel"].click()
        s.showSettings()
        XCTAssertEqual(s.settings.textFields["settings.name"].value as? String, "Alpha")
    }

    @MainActor
    func testHelpHeadingsLocalLinksAndNoRestoration() throws {
        let s = try launch()
        s.wait(s.editor)
        s.showHelp()
        s.wait(s.help.webViews.firstMatch)
        for heading in ["BrainDump Help", "Capture and save", "Projects and windows", "Files and conflicts", "Folder access and repair"] {
            s.wait(s.help.staticTexts[heading].firstMatch)
        }
        let link = s.help.links.firstMatch
        s.wait(link)
        link.click()
        s.wait(s.help.webViews.firstMatch)
        s.relaunch()
        s.countEditors(1)
        XCTAssertFalse(s.help.exists)
        s.assertText("")
    }
}
