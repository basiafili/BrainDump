import XCTest
import AppKit

/// UI-only drivers plus disk assertions against UUID-scoped sandbox fixtures.
/// No controller calls, hidden action menus, AppleScript, or computer-use APIs.
@MainActor
final class UITestSession {
    static let bundleID = "org.example.BrainDump"
    let app = XCUIApplication(bundleIdentifier: bundleID)
    let token = UUID()
    let root: URL
    private(set) var ids: [String: String] = [:]
    private var didFinish = false

    init(scenario: String, dark: Bool = false) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("BrainDumpUITests/\(token.uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        app.launchArguments = ["--ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-AppleInterfaceStyle", dark ? "Dark" : "Light"]
        app.launchEnvironment = ["BRAINDUMP_UI_TEST_ID": token.uuidString, "BRAINDUMP_UI_SCENARIO": scenario, "BRAINDUMP_UI_ROOT": root.path, "BRAINDUMP_UI_APPEARANCE": dark ? "dark" : "light"]
    }

    private func showAuthorizationPanel() {
        if app.state != .notRunning { app.terminate() }
        app.launch()
        app.activate()
        wait(app.buttons["Authorize Fixtures"])
    }

    func start() throws {
        showAuthorizationPanel()
        let ready = root.appendingPathComponent("ready.json")
        do {
            let authorize = app.buttons["Authorize Fixtures"]
            wait(authorize)
            authorize.click()
            try waitForFile(ready)
            ids = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: ready))
        } catch {
            finish()
            throw error
        }
    }

    func finish() {
        guard !didFinish else { return }
        didFinish = true
        if app.state != .notRunning { app.terminate() }
        // Clear the app-owned UUID suite through Debug bootstrap, without
        // touching standard preferences or accessing another container's files.
        app.launchArguments += ["--ui-cleanup"]
        app.launch()
        app.terminate()
        try? FileManager.default.removeItem(at: root)
    }

    var editors: XCUIElementQuery { app.windows.matching(NSPredicate(format: "title CONTAINS %@", " - BrainDump - ")) }
    var editor: XCUIElement { editors.firstMatch }
    var settings: XCUIElement { app.windows["Project Settings"] }
    var open: XCUIElement { app.windows["Open Project"] }
    var new: XCUIElement { app.windows["New Project"] }
    var help: XCUIElement { app.windows["BrainDump Help"] }

    func element(_ id: String, in window: XCUIElement) -> XCUIElement { window.descendants(matching: .any).matching(identifier: id).firstMatch }
    func accessibleText(_ element: XCUIElement) -> String {
        [element.label, element.value as? String ?? ""].joined(separator: " ")
    }
    func button(_ id: String, in window: XCUIElement) -> XCUIElement { window.buttons[id] }
    func currentEditor() -> XCUIElement {
        wait(editor)
        return app.windows.matching(identifier: editor.identifier).firstMatch
    }
    func text(in window: XCUIElement? = nil) -> XCUIElement { (window ?? editor).textViews["editor.text"] }

    func wait(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let found = element.exists || element.waitForExistence(timeout: 8)
        if !found { attachWindows("Missing UI element") }
        XCTAssertTrue(found, "Missing \(element)", file: file, line: line)
    }
    func gone(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let disappeared = !element.exists || element.waitForNonExistence(timeout: 8)
        if !disappeared { attachWindows("Window did not close") }
        XCTAssertTrue(disappeared, "Still visible \(element)", file: file, line: line)
    }
    private func attachWindows(_ name: String) {
        XCTContext.runActivity(named: name) { activity in
            let attachment = XCTAttachment(string: app.windows.allElementsBoundByIndex.map(\.debugDescription).joined(separator: "\n\n"))
            attachment.name = name
            attachment.lifetime = .keepAlways
            activity.add(attachment)
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.lifetime = .keepAlways
            activity.add(screenshot)
        }
    }
    func countEditors(_ count: Int, file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate(format: "count == %d", count)
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: editors)], timeout: 8), .completed, file: file, line: line)
    }
    func replace(_ element: XCUIElement, with value: String) {
        app.activate()
        wait(element)
        element.click()
        element.typeKey("a", modifierFlags: .command)
        if value.isEmpty { element.typeKey(.delete, modifierFlags: []) }
        // Scenario setup uses native Paste; the dedicated direct-typing test
        // separately verifies keystrokes, predictions, deletion, Undo and Redo.
        else { paste(value, into: element) }
        let input = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [input], timeout: 5), .completed, "UI text entry did not produce the requested fixture text")
    }
    func assertText(_ expected: String, in window: XCUIElement? = nil, file: StaticString = #filePath, line: UInt = #line) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", expected), object: text(in: window))
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed,
                       "Expected \(String(reflecting: expected)); actual \(String(describing: text(in: window).value))", file: file, line: line)
    }
    func activate(_ window: XCUIElement) {
        app.activate()
        // Single auxiliary scenes are absent from the native Window list.
        // Their existing public commands raise the same form without reseeding it.
        switch window.identifier {
        case "new-project": showNew(); return
        case "open-project": showOpen(); return
        case "project-settings": showSettings(); return
        case "help": showHelp(); return
        default: break
        }
        // A titlebar coordinate can hit an overlapping editor instead of the
        // requested window. The native Window menu raises obscured windows.
        let menu = app.menuBars.menuBarItems["Window"]
        menu.click()
        let entries = menu.menuItems.matching(NSPredicate(format: "title == %@ OR label == %@", window.title, window.title))
        if entries.count == 1 {
            entries.firstMatch.click()
        } else {
            app.typeKey(.escape, modifierFlags: [])
            window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0)).withOffset(CGVector(dx: 0, dy: 12)).click()
        }
    }
    func command(_ key: String, modifiers: XCUIElement.KeyModifierFlags = .command) { app.activate(); app.typeKey(key, modifierFlags: modifiers) }
    func menu(_ name: String, item: String) {
        app.activate()
        let menu = app.menuBars.menuBarItems[name]
        menu.click()
        menu.menuItems[item].click()
    }
    func showSettings() { menu("File", item: "Project Settings…"); wait(settings); wait(settings.textFields["settings.name"]) }
    func showOpen() { command("o"); wait(open) }
    func showNew() { command("n", modifiers: [.command, .shift]); wait(new) }
    func showHelp() { menu("Help", item: "BrainDump Help"); wait(help) }
    func row(_ name: String, in window: XCUIElement, prefix: String) throws -> XCUIElement {
        let id = try XCTUnwrap(ids[name], "No fixture registration \(name)")
        return element("\(prefix).project.\(id)", in: window)
    }
    func selectSettings(_ name: String) throws { let row = try row(name, in: settings, prefix: "settings"); wait(row); row.click() }
    func setNewWindow(_ value: Bool, in window: XCUIElement, id: String) {
        let checkbox = window.checkBoxes[id]
        wait(checkbox)
        if (checkbox.value as? Int == 1) != value { checkbox.click() }
        XCTAssertEqual(checkbox.value as? Int, value ? 1 : 0)
        XCTAssertEqual(checkbox.label, "Open in new window")
    }
    func openProject(_ name: String, newWindow: Bool, doubleClick: Bool = false) throws {
        showOpen()
        setNewWindow(newWindow, in: open, id: "open.openInNewWindow")
        let row = try row(name, in: open, prefix: "open")
        wait(row)
        if doubleClick { row.doubleClick() } else {
            row.click()
            XCTAssertTrue(open.buttons["open.open"].wait(for: \.isEnabled, toEqual: true, timeout: 5))
            open.buttons["open.open"].click()
        }
        gone(open)
    }
    func chooseFolder(_ folder: String, from button: XCUIElement, expectingError: String? = nil) {
        button.click()
        // Exercise the real sandbox folder panel, including its authorization.
        app.typeKey("g", modifierFlags: [.command, .shift])
        let pathField = app.textFields["PathTextField"]
        wait(pathField)
        pathField.typeKey("a", modifierFlags: .command)
        paste(root.appendingPathComponent(folder).path, into: pathField)
        pathField.typeKey(.return, modifierFlags: [])
        gone(pathField)
        // Return activates the panel's real default action without depending
        // on the host system's translation of Open/Choose.
        app.typeKey(.return, modifierFlags: [])
        let chosenPath = root.appendingPathComponent(folder).resolvingSymlinksInPath().path
        let resultText = expectingError ?? chosenPath
        let selectionResult = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", resultText, resultText)).firstMatch
        wait(selectionResult)
    }
    private func paste(_ value: String, into field: XCUIElement) {
        let saved = UITestClipboardSnapshot()
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
        let ownChange = pasteboard.changeCount
        defer { saved.restore(ifUnchangedSince: ownChange) }
        field.typeKey("v", modifierFlags: .command)
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: field)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed, "Native text paste did not complete")
    }
    func changeFolder(_ folder: String) { chooseFolder(folder, from: settings.buttons["settings.changeFolder"]) }
    func answerFolder(_ label: String) {
        let button = app.buttons.matching(identifier: label).matching(NSPredicate(format: "enabled == YES")).firstMatch
        wait(button); button.click()
    }
    func dismissFailure() {
        // SwiftUI's macOS alert can be exposed as a sheet/dialog instead of
        // XCUIElementTypeAlert. Identify its acknowledgement, not its container.
        let ok = app.buttons.matching(NSPredicate(format: "(label == 'OK' OR title == 'OK') AND identifier != 'settings.ok' AND enabled == YES")).firstMatch
        wait(ok)
        ok.click()
    }
    func save(in window: XCUIElement? = nil) {
        let window = window ?? editor
        activate(window)
        window.typeKey("s", modifierFlags: .command)
        assertStatus("Capture saved.", in: window)
    }
    func assertStatus(_ expected: String, in window: XCUIElement? = nil, file: StaticString = #filePath, line: UInt = #line) {
        let status = element("editor.status", in: window ?? editor)
        let value = "Save status: \(expected)"
        let predicate = NSPredicate(format: "label == %@ OR value == %@", value, value)
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: status)], timeout: 8), .completed,
                       "Status label=\(status.label), value=\(String(describing: status.value))", file: file, line: line)
    }
    func markdown(in folder: String) throws -> [URL] {
        let directory = root.appendingPathComponent(folder)
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil))
        return enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "md" }.sorted { $0.path < $1.path }
    }
    func contents(in folder: String) throws -> [String] { try markdown(in: folder).map { try String(contentsOf: $0, encoding: .utf8) }.sorted() }
    func waitForFile(_ url: URL) throws {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in FileManager.default.fileExists(atPath: url.path) }, object: nil)
        guard XCTWaiter.wait(for: [expectation], timeout: 10) == .completed else { throw FixtureError.missingFile(url.path) }
    }
    func holdSaves() throws { try Data().write(to: root.appendingPathComponent("hold-saves")) }
    func waitForStagedSave() throws { try waitForFile(root.appendingPathComponent("save-staged")) }
    func releaseSaves() throws { try FileManager.default.removeItem(at: root.appendingPathComponent("hold-saves")) }
    func relaunch() { app.terminate(); app.launch() }

    enum FixtureError: Error { case missingFile(String) }
}

nonisolated class BrainDumpUITestCase: XCTestCase {
    @MainActor
    func launch(_ scenario: String = "two", dark: Bool = false) throws -> UITestSession {
        continueAfterFailure = false
        let session = try UITestSession(scenario: scenario, dark: dark)
        addTeardownBlock { await MainActor.run { session.finish() } }
        try session.start()
        return session
    }
}

/// Preserve all available clipboard representations, not just plain text.
@MainActor
struct UITestClipboardSnapshot {
    private let items: [[NSPasteboard.PasteboardType: Data]]
    init() {
        items = (NSPasteboard.general.pasteboardItems ?? []).map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in item.data(forType: type).map { (type, $0) } })
        }
    }
    func restore(ifUnchangedSince change: Int) {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount == change else { return }
        pasteboard.clearContents()
        let restored = items.map { values in
            let item = NSPasteboardItem()
            for (type, data) in values { item.setData(data, forType: type) }
            return item
        }
        if !restored.isEmpty { pasteboard.writeObjects(restored) }
    }
}
