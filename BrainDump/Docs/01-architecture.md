# Architecture

## Core idea

BrainDump captures notes. It does not manage documents or organize knowledge. SwiftUI is the presentation layer; workflow and file-writing rules remain independently testable.

## Ownership

### App and platform adapters

- Declare SwiftUI scenes and commands.
- Route window creation, activation, focus, alerts, and close/quit callbacks.
- Forward actions to the coordinator; do not implement saving or switching in views, commands, or AppKit adapters.

### ProjectStore

- Own the complete registered-project collection, MRU, last active project, and global window-opening preference.
- Enforce unique names and unique folders (see Project and Capture Rules).
- Expose explicit operations rather than allow callers to mutate its collections.
- Persist registry names, canonical paths, and folder-access bookmarks in UserDefaults.
- Keep unreachable projects registered. Expose an accessible status and reason in Project Settings; omit them from project-selection lists, the Projects menu, switcher, and displayed Open Recent entries.
- Revalidate folder access before opening a project or committing a folder selection; stale UI availability must not allow a failed operation to discard editor state.

### EditorSession

One observable state object per editor window, owned by EditorCoordinator and identified independently of SwiftUI view recreation. See the coordinator contract for fields and invariants.

### EditorCoordinator

- Own sessions and orchestrate Save, New Capture, close, project switching, quit, and saves needed by settings/removal.
- Use one save implementation for every entry point.
- Depend on model/service interfaces, not SwiftUI views, AppKit classes, or window objects.
- Expose observable state and structured operation outcomes. The presentation adapter performs window actions and displays errors.

### CaptureFileWriter

- Perform filesystem work off the main actor.
- Create UTC month folders and timestamped Markdown files, allocate collision suffixes, perform safe updates, and detect external content changes.
- Never create or modify a capture file for whitespace-only content.
- Return the actual written URL, first-save timestamp where applicable, and saved-content baseline.

### Shared presentation helpers

- ProjectCommandRouter resolves active/most-recent/originating editor IDs and snapshots menu window preference at invocation; it forwards all actual saves and switches to EditorCoordinator. Requests do not retarget during an await.

- TitleFormatter renders the first-save time in the user's local time and locale.
- One project-list builder provides identical sorting/grouping to the Projects menu and editor switcher.

## SwiftUI data flow

- Use one source of truth for registry state and each session's text; avoid view-local copies of authoritative session text.
- Bind editing controls to coordinator-owned session state through explicit updates or bindings.
- Pending New Project fields remain form-local drafts until create-and-open succeeds. Settings keeps separate project drafts: valid rows commit when leaving them, invalid/cancelled rows remain pending, and OK applies all remaining valid drafts. Settings Cancel discards only unapplied drafts.
- Use stable session identity, not project path, as editor scene identity; multiple windows may share a project, and a project's path may change.
- Scene recreation must not duplicate sessions, lose text, or trigger saves.

## Persistence

Use UserDefaults only for application state. No database, Core Data, separate state files, sync, or automatic migration system. Capture Markdown files are user content, not app-state persistence.

Persist:

- Full project registry: display names, paths, and security-scoped folder bookmarks.
- Ordered MRU references, at most 10.
- Last active project reference, separately from MRU.
- Independent remembered checkbox choices for New Project and Open Project.
- Global “Always Open in New Window” preference. Default to OFF when no saved preference exists; otherwise honor the saved value.

Folder-access authorization must survive relaunch. Preserve access needed by already-bound captures after their project's folder changes; changing registry metadata must not revoke an open capture's original file access.

## MRU and last active project

MRU is most recently used first, deduplicated by project. A successful explicit open, create-and-open, or switch moves that project to the front. Focus changes alone do not reorder MRU. Removal deletes the project's MRU reference. Clear Menu clears MRU without unregistering projects or clearing last active project.

Last active means the project of the editor most recently used by the user. Update it on editor activation and successful open/create/switch. Do not change it due to internal save order, background work, failed saves, or failed switches. If a registered project's path changes, update its persisted references consistently; removal clears a matching last active reference without selecting a replacement.

Neither quit saves nor close saves may reorder MRU or change last active. Startup never falls back to MRU.

## Concurrency and failure boundaries

- UI, ProjectStore, and session state are main-actor isolated.
- Filesystem work must not block the main actor.
- Serialize saves per session. Manual Save snapshots text; subsequent typing remains in the editor and remains unsaved if it differs from the successfully written snapshot.
- Workflows that save before clearing, switching, closing, removing, or quitting make affected editors read-only until the workflow completes or aborts. Prevent overlapping state-changing actions on those sessions. Other editors remain usable unless included in that operation.
- A failed write never clears text, changes a binding to an unwritten file, or completes the pending destructive transition.
- Multi-session operations save first and close/commit only after all required saves succeed. On failure, all affected windows remain open and editing is restored. Earlier successful disk writes are not rolled back.
- Keep orchestration simple and explicit; no background autosave or task framework is required.

## Error presentation

Use persistent, accessible in-window errors for validation, unavailable folders, project-opening failures in selection forms, startup fallback, and creation failure. Associate errors with controls where possible, announce them, and never use color alone.

Reserve blocking alerts/confirmation dialogs for removal, the unsaved-capture folder-change decision, save failures blocking a workflow, or a failure with no suitable in-window presentation. Avoid routine success alerts and repeated error alerts for one failed operation.

## Project list sorting and grouping

The Projects menu and editor switcher consume exactly the same reachable-project structure. Project entries always show their complete registered names; group labels must explain their purpose.

- Sort names ascending with localized, case-insensitive, diacritic-insensitive comparison. Use one comparator everywhere.
- At most 15 reachable projects: show a flat list.
- Above 15: traverse the sorted list and form contiguous groups, preferring script boundaries. Group by the initial letter of the displayed name.
- Aim for at most 10 projects per group. Do not split projects sharing an initial to enforce that limit.
- Do not mix scripts in a range label. Labels use actual first/last grouping initials: “Projects A–D”; a one-initial group is “Projects starting with A”. Localize label wording.
- Single-project fragments and names beginning with digits or symbols are fallback candidates. With at least two candidates, place them in “Other projects…” at the end, sorted by the same comparator. A single leftover is displayed directly, not hidden behind a submenu.
- Except for this explicit fallback placement, grouping must preserve sorted order. Never truncate or hide reachable projects.

Project Settings includes all registered projects and their availability. Open Project shows reachable projects with name and path. MRU retains its own explicit recency order, not alphabetical grouping.

Settings OK applies pending projects as separate transactions: a later project failure preserves earlier successful metadata commits and editor closes. Within each project, save all affected sessions before committing name/folder metadata or granting any closes. Quit remains one all-editor save barrier.
