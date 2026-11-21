# BrainDump Project Setup

## Goal

Build a minimal, sandboxed macOS capture app using SwiftUI. Capture plain-text Markdown notes into user-selected project folders. Preserve the workflows in these specifications.

## Platform and structure

- Minimum macOS version: 15.
- Use Swift 6 language mode and complete concurrency checking for app and test targets. Do not fall back to Swift 5 mode or reduce checking to bypass isolation/Sendable errors.
- Use a SwiftUI `App` entry point and SwiftUI scenes, views, menus, and controls.
- Use native SwiftUI APIs first. Small AppKit bridges are allowed where necessary for native plain-text editing, folder selection, window activation, disabling tabbing/restoration, reliable close/quit interception, and native accessibility support. The project-switcher bridge is limited to menu presentation/activation because the installed SDK's SwiftUI Menu and Picker fail the accessibility action audit; workflow ownership remains in the coordinator.
- An app delegate adapter may handle platform lifecycle callbacks; it must delegate workflows to EditorCoordinator rather than own application state.
- No storyboards, segues, document-based lifecycle, project generators, or unnecessary tooling.
- Keep the existing `.xcodeproj`. One type per file where practical; use obvious names.
- Enable App Sandbox. Persist security-scoped folder bookmarks in UserDefaults and manage access explicitly, including across launches.

## Startup

1. Resolve the last active project and its folder access.
2. If reachable, open exactly one empty editor for that project.
3. With no last-active reference, open New Project. If a last active project exists but cannot be opened, open Open Project with a persistent, accessible explanation, accessibility focus on that explanation, and a Project Settings button for folder repair.

Do not choose another project from MRU or the registry. Do not restore previous windows, editor contents, or file bindings. Do not show a separate launch error alert when Open Project can explain the failure and offer repair.

## Window lifecycle

- Multiple editor windows per project are allowed.
- Never enable window tabs.
- Closing the last editor leaves the app running without automatically opening another window.
- With no editor open, New Capture opens an empty editor for the last active project if reachable; with no last-active reference it opens New Project; with an unavailable last-active project it opens Open Project with the focused error and repair action.
- System window restoration must not bypass startup routing or recreate old sessions.

## Scope exclusions

No file browser/sidebar, formatting toolbar, Find, Replace, search, tagging, knowledge management, folder scanning, content interpretation, or automation. Files are managed outside BrainDump after capture.

## Reading the specifications

Architecture defines ownership and persistence; Project and Capture Rules defines storage behavior; EditorCoordinator defines workflow contracts. Window specifications define presentation. Shared behavior must be implemented once, not separately per view or command.
