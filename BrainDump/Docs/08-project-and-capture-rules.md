# Project and Capture Rules

## Project identity and access

- Project identity is its resolved folder, not its display name.
- Reject duplicate physical folders even if selected using symlinks, alternate path spellings, or case variations on a case-insensitive filesystem.
- Store a canonical path and persistent security-scoped folder bookmark. Use filesystem-aware identity; do not simply lowercase all paths on case-sensitive filesystems.
- Display names are trimmed, non-empty, and unique case-insensitively among all registrations. They are labels, not folder names.
- Selecting a folder uses that folder directly. Never create a project-name subfolder automatically.
- Multiple editors per project are permitted without an artificial one-window restriction.
- Retain unavailable registrations. Settings explains their status; selectors omit them. Revalidate access before operations.
- If a registered project folder is renamed or moved outside BrainDump, keep its registered path unchanged and mark it unavailable, even if its bookmark resolves the moved folder. Do not follow the move automatically or silently register a replacement folder at the old path. Repair requires explicitly selecting the folder with Change Folder in Settings.

## Content and encoding

Empty means whitespace/newline-trimmed length is zero. Do not judge any other content. Save non-empty text as plain UTF-8 Markdown, preserving its text and whitespace; trimming is not a content transformation.

Empty Save is always a no-op, including for an existing bound file. Do not write an empty file, erase old content, or delete the existing file when the editor is empty. The user can delete files outside the app.

## First save and naming

On first successful save, choose the current absolute save time as the capture's stable first-save timestamp. Generate both its month folder and filename from that timestamp in UTC:

- Month folder: `YYYY-MM`.
- Filename: `YYYY-MM-DD_HH-mm-ss.md`.
- Collision: `YYYY-MM-DD_HH-mm-ss_01.md`, then `_02`, and so on; use at least two suffix digits and expand as needed.

Allocate an unused name without overwriting an existing capture. Multiple sessions saving within one second must receive distinct names.

Use Gregorian calendar, ASCII digits, fixed separators, and app-defined locale-independent formatting. Never inherit the user's calendar, numbering system, region, local time zone, or localized date styles. The `YYYY` notation denotes the calendar year, not a week-based year.

Create month folders as needed. Project creation also creates the current UTC month folder, even before a capture exists; this does not permit creating an empty capture file.

## Bound-file save policy

Keep the session's bound URL, first-save timestamp, and baseline content from its last successful write.

For non-empty Save:

1. If the bound path is missing, recreate that same path with the current editor content. Do not follow or search for an externally renamed/moved file. Recreate its month folder if needed and authorized.
2. If the bound path exists and its content matches the last successful write, atomically update that same file.
3. If its content differs, preserve that file and create a copy in the same folder using the original timestamp stem with the next available collision suffix. After success, bind the session to the copy and make its written content the new baseline.

External-change comparison is content-based, not merely modification-date-based. If the path cannot be inspected/read safely, fail without overwriting it. A failed write does not change the session's binding or baseline.

Example: if `2026-11-11_12-24-14.md` is renamed elsewhere, Save recreates that original filename. If that original file is edited externally instead, Save creates `2026-11-11_12-24-14_01.md` (or the next available suffix) and future saves target the copy.

Copies retain the capture's original first-save time for the window title; they are not new capture sessions. A project folder change never redirects an already-bound capture.

## Write safety

- File writes must be atomic; failures must not leave partially written capture files or corrupt an existing file.
- Serialize writes for each session and safely allocate new names across sessions.
- Update binding, baseline, and saved state only after success.
- Do not overwrite an externally changed file when creating a copy.
- Do not scan project folders, follow external renames, move files, reorganize directories, or modify unrelated files.
- No automatic deletion of user content or rollback deletion of successful prior saves.
- Coordinate inspection and publication with macOS file coordination and compare fresh file content inside that operation. Preserve detected external edits as copies; fail safely when the operation cannot be completed safely.
- Simultaneous changes by applications that bypass macOS file coordination receive best-effort conflict detection. Absolute protection against an undetectable direct write at the exact replacement instant is not guaranteed. This platform limit does not weaken exclusive new-name allocation or atomic publication guarantees.

## Folder changes and removal

Follow the transaction and decision rules in Project Settings. Unsaved means either unbound non-empty content or a bound editor whose current text differs from its last successfully written baseline. A bound editor cleared to whitespace is unsaved, but its Save is still a no-op.

“Keep captures open” changes where unbound/future captures save, not existing file bindings. “Save and close captures” saves at the old destinations before changing registration. Keep old access authorization for bound captures that remain open.

Removal unregisters and closes after successful required saves; it never deletes files.

## UI time

Window titles show the stable first-save timestamp using current local time zone and user locale. They never expose the raw technical timestamp. Before first save, use New Capture. All UI date/time representations must be human-readable and accessible.
