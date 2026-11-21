# Editor Window

## Purpose and state

One editor window captures one Markdown note, with one stable coordinator-owned session. Multiple windows for one project are allowed.

Empty means text trimmed of whitespace and newlines has zero length. Use this definition everywhere. Trimming is only an emptiness test; save non-empty text exactly as entered.

A session has either no file binding or one bound file. A bound capture may have unsaved edits, including being cleared to whitespace. Empty Save remains a no-op even for a bound file: the old file is neither emptied nor deleted.

## SwiftUI layout

A SwiftUI window contains a toolbar and a plain-text editor. Use a small NSTextView bridge if necessary to preserve the required native editing behavior.

Toolbar, in order:

- New Capture — `square.and.pencil`.
- New Project — `folder.badge.plus`.
- Open Project — `folder`.
- Save — `square.and.arrow.down`.
- Flexible space.
- Cut — `scissors`.
- Copy — `doc.on.doc`.
- Paste — `clipboard`.
- Project switcher, without a leading icon.

Use a 1340-point default and minimum editor width with an expanded native toolbar. Verify toolbar fit on the user’s display; do not silently switch to icon-only buttons if screen constraints or unusually long names prevent all labels fitting.

Labels must remain visibly available; symbols supplement text. Use system semantic colors, system control fonts, and a readable system monospaced editor font that accommodates system text-size settings where practical.

## Title and focus

- Before the first successful save: `<Project> - BrainDump - New Capture`.
- Afterwards: `<Project> - BrainDump - <localized first-save date and time>`.
- Use current local time zone and user locale for display. Do not display the raw filename timestamp.
- Later saves and external-change copies retain the capture's first-save timestamp.
- A committed rename updates all matching window titles immediately.
- Focus the editor on opening, successful New Capture, and successful project switch.

## Editing

Plain text only, wrapping enabled. Support native undo/redo, spellchecking, context menus, and system text services. Disable smart substitutions that change Markdown syntax where possible. Disable inline word predictions and automatic text/math completions; keep spellchecking and explicit native text services. Do not implement custom replacements for standard text editing. New Capture/project switch starts a new editing context; undo must not restore the previous capture into the new one.

## Workflows

All workflows call EditorCoordinator; SwiftUI views and platform adapters only present state and forward actions.

| Action | Behavior |
| --- | --- |
| Save | Empty: no-op. Unbound non-empty: create. Bound non-empty: save using the existing-file policy in Project and Capture Rules. |
| New Capture | If non-empty, save first. On success (or if empty), clear text and binding, reset title, and focus. |
| Close | Empty: close. Non-empty: save, then close only on success. |
| Project switcher | Always reuse this editor, regardless of the global preference. If non-empty, save first; then reset text/binding and switch. |
| Quit | Save all non-empty sessions before allowing any windows to close. Failure aborts quit with all windows open. |

Selecting a project must validate reachability before abandoning the current capture. Successful open/switch updates project usage as defined in Architecture.

## Save and busy feedback

- Manual Save permits continued typing and saves a snapshot; later edits must remain intact and unsaved.
- Save-before-transition makes the affected editor read-only and disables conflicting actions temporarily. Provide accessible busy feedback.
- On failure, retain text, binding, and project; restore editing and allow retry. Present one appropriate blocking error for a blocked workflow.
- Empty save never creates a file or alters an existing one. Clearing an editor after an empty transition does not delete the older saved content on disk.
- Save feedback must be perceivable, persistent where needed, and accessible without relying only on visual changes.

## Project switcher data

Reachable projects only, full registered name only. Use exactly the same sort order, groups, meaningful group labels, and fallback structure as the Projects menu.
