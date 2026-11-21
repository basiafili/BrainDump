# EditorCoordinator Contract

## Purpose and boundary

EditorCoordinator is the single workflow authority for sessions, saves, New Capture, switching, close, quit, and project-related session transitions. Views, SwiftUI commands, and AppKit adapters forward intent and present outcomes; they do not duplicate workflow logic.

The contracts below describe required behavior, not fixed Swift method signatures. Use async operations where I/O is involved. The coordinator must be testable without creating windows and must not import SwiftUI or AppKit solely to control UI.

The production implementation lives in `BrainDumpCore/EditorCoordinator.swift` and `BrainDumpCore/EditorSession.swift`. Checkpoint 5 connects the SwiftUI app to these production types. The earlier no-write lifecycle fixture remains outside app target membership in `Verification/` for historical headless checks.

## State

Run coordinator/session mutations on the main actor. Each editor has one unique session ID stable for its window lifetime and never reused. SwiftUI view reconstruction must not recreate its session.

Each session holds:

- Session ID and registered project reference.
- Current text and monotonically tracked edit revision or equivalent snapshot identity.
- Optional bound file URL.
- Optional first-successful-save timestamp.
- Last successfully written content baseline for the bound file.
- Save/busy state sufficient to prevent overlapping transitions and expose accessibility feedback.

Derived state:

- Empty: trimming whitespace/newlines produces zero length.
- Unsaved: unbound and non-empty, or bound and current text differs from the last successful baseline.
- A cleared bound capture is unsaved, but empty Save remains a no-op.

Session text is authoritative. SwiftUI bindings/native editor adapters propagate user edits promptly; do not maintain a second independent text buffer that can be stale at save time.

## Dependencies

- ProjectStore: explicit registry, availability, and user-activation operations; never mutate its collections directly.
- CaptureFileWriter: off-main filesystem work, atomic writes, collision allocation, baseline comparison, and bound-file save policy.
- TitleFormatter: localized stable first-save time or New Capture title.
- Presentation adapter: create/close windows, reflect state, focus, and present structured errors/decisions.

The coordinator does not persist app state itself, enumerate folders, interpret content, or manipulate controls. ProjectStore owns MRU ordering; the coordinator reports successful explicit use through its API.

## Session lifecycle and edits

Register an empty session for a reachable project when an editor is created. Expose its initial title and focus request. Unregister only after an authorized close or successful encompassing operation; view disappearance alone must not silently discard a session.

Text updates change current text, not its saved baseline. User editor activation updates last active through ProjectStore; internal save processing does not count as activation.

## Common save operation

1. Snapshot the session text/binding/baseline and serialize against prior saves for that session.
2. Empty snapshot: succeed as a no-op, without modifying files, binding, or baseline.
3. Unbound non-empty snapshot: create a timestamped capture.
4. Bound non-empty snapshot: apply Project and Capture Rules (update, recreate missing path, or create/rebind to an external-change copy).
5. On success, record the actual written URL, baseline, and first-save timestamp. Never replace newer editor text with the saved snapshot or incorrectly mark it saved.
6. On failure, preserve text, original binding/baseline, and the pending transition's pre-commit state; return an actionable error.

All workflows below use this operation. Do not implement separate automatic-save logic. Manual Save permits typing during I/O; transition workflows lock affected editing and conflicting commands until completion/abort.

### Save ordering and cancellation

- Each accepted Save freezes its text and capture identity when requested, including when queued behind another Save.
- Saves run FIFO per session. Resolve the binding at the start of each write, after adopting the preceding successful result; do not create a duplicate merely because an earlier first save was still pending.
- Cancel only the requesting command's queued job, never its predecessor. Await cleanup rather than leaving an unowned background save.
- If a write commits despite cancellation, adopt and return its receipt. A cancelled transition then keeps the capture/window open instead of clearing or closing it; completed disk writes remain saved.
- Late success or failure must not update a different capture generation. Bulk operations must also verify every affected capture before authorizing closure or committing registry metadata.
- A successful save clears that capture's save error, not an unrelated project-access error.

## Create and open project

Prepare and validate a registration without changing registry or usage state. Lock any reused editor, save its current capture through the shared FIFO, prepare the current UTC month folder, and revalidate the selected folder. Commit registration, MRU, and last active in one ProjectStore snapshot, then reset the reused session or register a new empty session without another await. Failures retain the old session and usage state; successful prior disk writes remain reflected. Cancellation before commit leaves the project unregistered. Quit cannot overtake an in-flight creation transaction.

## New Capture

Save if non-empty. Only on success (or if empty), clear text, file binding, baseline, timestamp, and previous editing context; expose New Capture title and focus. On failure, retain the old capture.

## Close

Save if non-empty. Return permission to close only after success; otherwise keep the window and session. The platform adapter must intercept native close requests so closing cannot bypass this contract.

The implementation returns structured outcomes: completed, specific window IDs permitted to close, actionable failure, busy, cancellation, or missing session. Returning close permission does not unregister a session. Keep accepted-close sessions read-only until `windowDidClose` confirms actual closure. View disappearance alone cannot discard session state.

## Switch project

Validate the target before resetting state. This operation always reuses the specified editor. Save non-empty content first; failure leaves current project/text/binding intact. On success, reset the capture, assign the target project, update explicit usage through ProjectStore, then expose title and focus updates.

Menu/form routing decides whether to create a separate editor or request a switch. The switcher always calls the reuse operation for its own session.

## Quit

Lock all affected editors and save every non-empty session before closing any window or authorizing termination. On failure, abort quit, leave all windows open, restore editing, and present one blocking error. Previously completed saves remain valid. On success, allow termination; do not persist window/session restoration state.

Use stable session creation order for the save pass, never MRU ordering. Pending manual saves finish first, followed by a fresh save of the text locked for quit. Repeated quit requests cannot start another pass.

## Project removal and save-and-close folder change

Operate on all sessions for the project as one close/commit boundary:

1. Lock affected sessions and save required non-empty content.
2. If any save fails, keep every affected window open and leave registry metadata unchanged; restore editing.
3. After all saves succeed, allow closure and the corresponding registry transaction.

Project removal requires prior user confirmation. A folder-change decision is governed by Project Settings. Neither operation deletes files or rolls back earlier successful writes.

The production coordinator exposes removal and folder-change operations that commit registry metadata only after all required saves succeed, then return window IDs for the platform adapter. Prevent conflicting project operations/new windows while preparing that transaction and while its authorized windows are still closing. Other projects remain usable. Native activation caused by these internal closes must not guess a new persisted last-active project; explicit user activation/typing may update it.

## Committed project metadata changes

- Rename: update matching session project metadata and titles immediately after commit.
- Keep-open folder change: update session project references, but preserve every bound URL, baseline, timestamp, and old access authorization. Unbound/future captures use the new project folder.
- Do not use mutable project paths as session IDs or SwiftUI scene identities.

## Verification expectations

Meaningful future tests must cover empty/bound-empty behavior; save consistency across entry points; failure preservation; editing during manual save; transition locks and their release; quit/removal failure with no early closes; external rename versus content-edit behavior; collision copies and rebinding; stable timestamps; path changes preserving bindings; session identity; and MRU/last-active changes only on the agreed user events.
