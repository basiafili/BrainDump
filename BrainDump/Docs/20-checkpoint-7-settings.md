# Checkpoint 7 — Project Settings

Status: complete. Headless verification passed and the user accepted the Settings initialization and Open Project double-click fixes. Checkpoint 6 is committed as `a83f191`. Checkpoint 7 is approved for commit. Checkpoint 8 follows with XCTest UI automation and accessibility audits.

## Behavior

- Leaving a row commits that project's valid changes immediately. Invalid drafts remain visible in their rows while selection moves; any invalid input disables OK.
- Cancelling a folder-change decision keeps that project's entire draft and moves to the requested row. OK retries all remaining valid drafts in registry order.
- Each project's name and folder update commits together. If a later project fails, earlier successful changes and authorized editor closes stay applied. Cancel/close discards only unapplied drafts.
- Removal uses the committed registration, ignores raw settings drafts, saves required captures, and never deletes Markdown files. Reveal in Finder uses the registered folder without applying drafts.

The observable settings controller retains per-project drafts and immutable submitted changes. Name/folder validation runs before capture saves and is rechecked before the synchronous metadata/session commit. Rename-only changes require no access to an unavailable folder. Folder uniqueness is checked against current registrations, including when another row has just committed.

Keep-open waits for already accepted saves, preserves bound destinations, and redirects only unbound/future captures. Save-and-close and removal use the existing save-first barrier for every affected editor. A failed save preserves that project's registration and windows; earlier successful disk writes remain adopted. Authorized native closes are delivered synchronously, before Settings can dismiss.

The list exposes committed identity, pending changes, and problems. Field failures remain inline; required save failures use an alert. Busy state describes the operation; no idle hints or routine success announcements were introduced.

## Verification

- Debug and Release builds passed with Swift 6, complete concurrency checking, MainActor default isolation, and approachable concurrency.
- Full hostless suite passed: 127 test functions, 153 expanded cases, zero failures/skips/runtime warnings, confirmed by xcresulttool.
- Coverage includes immediate row commits, invalid drafts, cancelled folder decisions, all-draft OK, later batch failure preserving earlier commits/closes, removal cancellation/failure, stale validation, mixed capture states, pending saves, unavailable registrations, and real temporary-folder file preservation.
- Final logs: `braindump-verification.X9lRE2` (Debug), `braindump-verification.53leQr` (Release), and `braindump-verification.PDjrxY` (tests), retained in the system temporary directory. Test result: `Test-BrainDumpTests-2026.11.11_23-45-02-+0100.xcresult` in BrainDump DerivedData.
- No Swift/concurrency diagnostics. Xcode's existing App Intents metadata-extraction warning remains because the app has no AppIntents framework dependency.
- No app launch, UI automation, Finder interaction, or real user registry/file modification was performed. Native focus, VoiceOver, dialogs, and sandbox relaunch behavior remain for user verification.

## User walkthrough C

Follow-up fixes after the first native attempt: explicitly initialize the optional Settings controller's State backing storage so the window does not retain its implicit nil seed. Open Project now supports double-clicking an available row through the same guarded opening path as the Open button. Both require native rechecking; no UI automation was used.

Use disposable projects and captures.

1. Rename A, then select B: A commits and all its editor titles update. Edit B and Cancel Settings: only B's unapplied draft disappears.
2. Give A an empty or duplicate name, then select B: A retains its problem in the list and OK stays disabled until corrected.
3. Change A's folder with captures open, select B, and cancel the folder decision: B becomes selected and A retains its draft. OK later offers to apply every remaining draft.
4. Try both folder-change choices with bound, edited, cleared, and new captures. Existing bound files stay at their original destinations; new captures use the replacement folder. Save-and-close closes affected windows only after saves succeed.
5. Remove a project after editing its settings draft: confirmation uses its committed name. Cancel preserves everything; confirm saves captures, removes the registration, and leaves files intact.
6. Reveal in Finder uses the registered folder. An unavailable registration remains visible and can be renamed, repaired, or removed.
7. With a disposable original folder temporarily renamed, attempt Save and Close: a failed save must leave that project's windows and registration intact. Restore the folder and retry.

Check keyboard and VoiceOver operation of row selection, inline problems, folder decisions, and removal during these steps. The multi-project later-failure case is covered headlessly; earlier successful projects must remain applied if reproduced manually.
