# Decisions

This is a concise index of binding product decisions. Detailed contracts live in the corresponding specifications; implementation must not invent a different behavior for a particular UI entry point.

## Platform

- SwiftUI lifecycle, scenes, views, commands, and controls; minimal AppKit bridges where needed to preserve native behavior.
- macOS 15 minimum, App Sandbox enabled, security-scoped folder bookmarks persisted in UserDefaults.
- Swift 6 language mode with complete concurrency checking in app and test targets; explicit actor ownership and safe Sendable boundaries.
- Simple existing `.xcodeproj`, no storyboards, document-based lifecycle, generators, or unnecessary tooling.
- Workflow/state services remain independent of UI classes; one coordinator owns editor workflows.

## Product scope

Capture first. Plain-text Markdown; anything non-empty is valid. No interpretation, search, tagging, file browser, knowledge management, folder scanning, automation, or file reorganization. Users manage files outside the app.

## Projects and launch

- Selected folder is the project folder; unique trimmed display name, unique resolved physical folder.
- Persist the full registry separately from MRU (max 10) and last active.
- Launch only the last active reachable project; with no last-active reference use New Project, and for an unavailable last-active project use Open Project. No MRU guessing or prior-window restoration.
- Explain launch access failure inside Open Project, focus the error accessibly, and offer Project Settings for explicit folder repair.
- Keep unavailable registrations with accessible status in Settings; omit them from selectors.
- External project-folder moves/renames leave the original registration unavailable until explicitly repaired with Change Folder; bookmarks must not silently follow and update registry paths.
- Multiple editors per project; no tabs. Closing the last editor leaves the app running.

## Opening and routing

- Global “Always Open in New Window” controls menu project openings. It defaults to OFF when no saved preference exists; saved choices persist between launches.
- New Project and Open Project each remember their own last checkbox choice across window/app launches, separately from each other and the global preference. Use the global preference only until that particular window has a remembered choice. Neither form changes the global preference.
- Reuse targets the active/most recently active editor, including when Help or another auxiliary window is active; create one if none exists.
- The editor project switcher always reuses its own editor.
- New Capture without an editor uses last active if reachable; without a reference use New Project, and for an unavailable project use Open Project with the actionable error.

## Saving

- One save policy across manual Save, New Capture, switch, close, removal, folder-change close, and quit.
- Empty Save never creates, erases, or deletes a capture, even if a previously saved editor was cleared.
- UTC Gregorian filenames and month folders, ASCII digits, collision suffixes; first-save timestamp stays stable.
- UI displays first-save time in local time and user locale.
- Missing bound file: recreate its original path. External content edit: preserve it, create a suffixed copy, and rebind the session.
- Atomic writes off the main actor; serialize per session.
- Use macOS file coordination and fresh baseline checks for external edits. Protection against simultaneous writers that bypass coordination is best-effort; detected conflicts still preserve external content as copies or fail safely.
- Manual Save preserves later typing. Save-before-transition temporarily makes affected editors read-only.
- Failed transitions preserve content and restore editing. Multi-window failures leave all affected windows open; completed writes remain saved.

## Settings and removal

- Form edits commit only on successful OK; Cancel discards drafts.
- Folder-change choices with unsaved captures: Keep captures open; Save and close captures; Cancel.
- Existing file bindings never move; unbound/future captures use the new folder.
- Unsaved includes edits to bound captures and non-empty unbound captures.
- Removal is separately confirmed, saves before closing/unregistering, and never deletes files.

## Presentation

- System fonts and semantic colors; system monospaced editor font. Help uses the system font; Roboto was an exploratory idea, not a requirement.
- SF Symbols supplement visible action labels; main menus need no icons.
- Shared sorting/grouping for Projects menu and switcher; meaningful group labels and no hidden/truncated projects.
- Standard native editing, spellchecking, text services, and context menus; disable Markdown-altering smart substitutions where practical.
- Local HTML Help with no scripting.
- Accessibility and keyboard operation are part of the primary workflow.
- Persistent inline validation and status by default; modal interruption only for required critical failures and explicit decisions.

- No app-provided idle help/reminders or redundant editor hints. Native form checkboxes expose their label and state as one VoiceOver stop. Successful creation closes its form without revalidating its own committed name.

## Checkpoint 7 settings decisions

- Leaving a Settings row commits its valid changes immediately. Invalid drafts remain in their rows, the requested row becomes selected, and OK stays disabled until all input drafts are valid.
- A folder-decision Cancel moves to the requested row while retaining the earlier project's complete draft.
- OK applies all remaining valid drafts, including earlier cancelled folder changes. Each project's name/folder change is atomic; earlier independent row commits stay applied if a later one fails.
- Cancel/close discards unapplied drafts only. Removal is separately confirmed against committed metadata and never applies unrelated drafts or deletes files.

## Checkpoint 8 input decision

Disable inline word predictions and automatic text/math completions in capture editors, while preserving spellchecking and explicit text services. The user confirmed this during UI-test verification.

Contrast checks are excluded from checkpoint 8 acceptance by explicit user direction. Continue all other supported accessibility audits and investigate internal application defects; do not pursue native chrome or app-content contrast measurements.
