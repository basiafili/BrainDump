import XCTest

nonisolated final class AccessibilityUITests: BrainDumpUITestCase {
    @MainActor
    private func audit(_ window: String, scenario: String = "two", dark: Bool = false) throws {
        let s = try launch(scenario, dark: dark)
        switch window {
        case "new": if scenario != "empty" { s.showNew() }; s.wait(s.new)
        case "open": s.wait(s.editor); s.showOpen()
        case "settings": s.wait(s.editor); s.showSettings()
        case "help": s.wait(s.editor); s.showHelp(); s.wait(s.help.webViews.firstMatch)
        default: s.wait(s.editor)
        }
        // Audit one window at a time to isolate its accessibility hierarchy.
        if window != "editor" && s.editors.count > 0 {
            let editor = s.currentEditor()
            editor.buttons["_XCUI:CloseWindow"].click()
            s.gone(editor)
        }
        let target: XCUIElement
        switch window {
        case "new": target = s.new
        case "open": target = s.open
        case "settings": target = s.settings
        case "help": target = s.help
        default: target = s.editor
        }
        // Raise the intended window before taking its accessibility snapshot.
        s.activate(target)
        // Contrast is excluded by the user's acceptance decision. All remaining
        // supported categories fail on findings and retain diagnostic evidence.
        try auditApplication(s.app)
        if window == "open" {
            let scroll = s.open.scrollViews["open.projectScrollArea"]
            s.wait(scroll)
            XCTAssertEqual(scroll.label, "Available projects")
        }
    }

    @MainActor
    private func auditApplication(_ app: XCUIApplication) throws {
        let previous = continueAfterFailure
        continueAfterFailure = true
        defer { continueAfterFailure = previous }
        try app.performAccessibilityAudit(for: .all.subtracting(.contrast)) { issue in
            XCTContext.runActivity(named: issue.compactDescription) { activity in
                let detail = "Audit type: \(issue.auditType.rawValue)\n\(issue.detailedDescription)\nElement: \(issue.element?.debugDescription ?? "No associated element")\n\n\(app.windows.allElementsBoundByIndex.map(\.debugDescription).joined(separator: "\n\n"))"
                let attachment = XCTAttachment(string: detail)
                attachment.name = "Accessibility issue and app hierarchy"
                attachment.lifetime = .keepAlways
                activity.add(attachment)
            }
            return false // Record every finding; this handler only adds evidence.
        }
    }

    @MainActor func testNewProjectLightAccessibility() throws { try audit("new", scenario: "empty") }
    @MainActor func testNewProjectDarkAccessibility() throws { try audit("new", scenario: "empty", dark: true) }
    @MainActor func testOpenProjectLightAccessibility() throws { try audit("open") }
    @MainActor func testOpenProjectDarkAccessibility() throws { try audit("open", dark: true) }
    @MainActor func testEditorLightAccessibility() throws { try audit("editor") }
    @MainActor func testEditorDarkAccessibility() throws { try audit("editor", dark: true) }
    @MainActor func testSettingsLightAccessibility() throws { try audit("settings") }
    @MainActor func testSettingsDarkAccessibility() throws { try audit("settings", dark: true) }
    @MainActor func testHelpLightAccessibility() throws { try audit("help") }
    @MainActor func testHelpDarkAccessibility() throws { try audit("help", dark: true) }


    @MainActor
    func testUnavailableProjectExplanationAndSettingsAccessibility() throws {
        let s = try launch("unavailable")
        s.wait(s.open)
        try auditApplication(s.app)
        s.open.buttons["Project Settings…"].click()
        s.wait(s.settings)
        s.wait(s.settings.textFields["settings.name"])
        // Keep the recovery window available while auditing its Settings flow.
        // Background contrast isolation is unnecessary for noncontrast audits.
        s.activate(s.settings)
        try auditApplication(s.app)
        s.replace(s.settings.textFields["settings.name"], with: "")
        XCTAssertFalse(s.settings.buttons["settings.ok"].isEnabled)
        // Finish native field editing before auditing the resulting validation
        // state; the field's persistent name remains independently asserted.
        XCTAssertEqual(s.settings.textFields["settings.name"].label, "Project name")
        s.settings.textFields["settings.name"].typeKey(.tab, modifierFlags: [])
        try auditApplication(s.app)
    }

    @MainActor
    func testFolderAndRemovalDecisionAccessibility() throws {
        let s = try launch()
        s.wait(s.editor)
        s.replace(s.text(), with: "unsaved capture")
        s.showSettings()
        s.editor.buttons["_XCUI:MinimizeWindow"].click()
        s.changeFolder("Replacement")
        s.settings.buttons["settings.ok"].click()
        s.wait(s.settings.buttons["Keep captures open"])
        try auditApplication(s.app)
        s.answerFolder("Cancel")
        s.settings.buttons["settings.remove"].click()
        s.wait(s.settings.buttons["Remove Project"])
        try auditApplication(s.app)
    }
}
