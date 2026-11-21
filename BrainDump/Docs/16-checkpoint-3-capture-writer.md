# Checkpoint 3 — Capture Writer and File Safety

Status: complete. Debug and Release builds pass, and all 46 test functions (60 cases) pass. No UI was launched or controlled. The writer is not yet connected to editor workflows; checkpoint 4 has not started. Checkpoint 3 changes remain uncommitted.

Checkpoint 2 was committed as `96d6f20` after the user confirmed the sandboxed folder-access checks.

## Approved safety scope

The user approved macOS file coordination plus fresh content checks, copies for detected conflicts, and safe failure when needed. Simultaneous writers which bypass coordination receive best-effort detection, not an absolute guarantee against an undetectable direct write at the exact replacement instant. Exclusive new-name allocation and atomic publication remain required regardless of that limitation.

This scope is now recorded in Project and Capture Rules and Decisions. [Apple's file-presenter documentation](https://developer.apple.com/documentation/foundation/nsfilepresenter) explains that direct low-level writes do not generate file-coordination notifications.

## Implemented

### Naming and service contracts

- CaptureNaming explicitly uses Gregorian calendar, en_US_POSIX locale, UTC, calendar-year formatting, and ASCII suffix construction. Suffixes expand beyond two digits and are always based on the original capture timestamp, never an already-suffixed filename.
- CaptureWriteRequest, CaptureBinding, and CaptureWriteOutcome are Sendable values. Bindings contain the original folder authorization, exact URL, stable first-save time, and last-written bytes.
- Empty content returns a no-op before obtaining folder access, creating a directory, or touching an existing file. Non-empty text is encoded as UTF-8 without trimming its content.
- CaptureFileWriter is an actor with an injectable clock and async save boundary. Its critical filesystem work is synchronous off-main, with no suspension inside the coordinated publication accessor. Per-session workflow ordering is added by the coordinator at checkpoint 4; this actor serializes its own critical writes.

### Filesystem publication

- Obtain a folder-access lease using the bound capture's original folder when applicable; release it on success and failure. Registry path edits do not redirect bound writes.
- Open project/month directories through descriptors, verify their physical identity/location, and reject symlink directory substitution. Create month folders when needed, including via a separate project-creation preparation operation.
- Stage bytes into an exclusively created, uniquely named hidden temporary file in the destination directory. Handle short writes, interruptions, cancellation, and flushing before publication. Failure cleans up owned staging files without publishing a partial capture.
- Allocate new files/copies with macOS exclusive atomic rename (`renameatx_np` with RENAME_EXCL). Existing candidate names are never overwritten, even when independent writers contend. Unsupported publication operations fail safely rather than falling back to an unsafe overwrite.
- Coordinate the original target URL using a new NSFileCoordinator for each operation. Create/use it on one synchronous thread. Reject a changed accessor path instead of following a renamed capture.
- Inspect regular-file content without following symlinks; re-read the content before publication. A missing bound path is recreated exclusively at its original name. A baseline match updates the same name atomically, preserving POSIX permissions. A mismatch publishes a collision-safe copy and returns its new binding while preserving the external file.
- Validate directory identity again before publication so a replaced month folder does not redirect a pending write.
- Successful publication returns its binding even if cancellation arrives during access cleanup. Do not check cancellation after commitment and falsely report an unwritten result.

Local descriptor/coordinator helpers are deliberately synchronous and nonisolated, confined to the writer's call stack. They read immutable Sendable dependencies and do not escape or cross actor boundaries. This resolved Swift 6 region-isolation checking without unsafe annotations or weakened diagnostics.

## Verification — passed

The authoritative xcresult summary reports 46 test functions, 60 cases including parameterized tests, zero failures/skips, and no runtime warnings. xcsift undercounts these parameterized output lines (45 functions); the result bundle, not the condensed count, establishes the full test scope.

New coverage includes:

- Exact Unicode/Markdown whitespace preservation; unbound and bound-empty no-ops.
- UTC month/year boundaries, calendar-year versus week-year naming, ASCII filenames, and suffixes beyond 99.
- Month preparation without empty capture creation.
- Existing-file updates retaining URL, first-save time, and permissions.
- External edits producing copies and subsequent saves updating those copies without stacked suffixes.
- External rename/deletion recreating the original path without scanning for or following the renamed file.
- Saving to the original folder after project registration changes.
- Failed staging and interruption after a partial write leaving original content intact and removing temporary bytes.
- An external edit inserted between initial inspection and final publication check being preserved as a conflict copy.
- A competing creator winning the initial filename without being overwritten.
- Symlink month/capture paths, unreadable files, directories at capture paths, and malformed bindings failing without modifying unrelated content.
- Twenty-four simultaneous new captures through eight independent writer actors receiving distinct names and correct contents.
- Independent writer actors saving the same baseline preserving both resulting contents as an update and conflict copy, rather than silently losing a save.
- Month-directory substitution during saving failing without publishing into the replacement.
- Cancellation after actual publication but before lease release still returning the successful binding, using continuations rather than timing sleeps.

Debug and Release app builds both pass under the existing Swift 6/complete-checking settings. Raw logs contain only the previously recorded skipped App Intents metadata tooling warning; there are no Swift/concurrency diagnostics. Whitespace checks pass.

The formatter's independence from user calendar/numeral settings also follows from its explicit fixed configuration; no system locale/calendar preference was changed during tests. Runtime on macOS 15 itself and real cross-process external-editor interoperability were not exercised here. Independent writer instances were exercised, and the documented coordination limit remains applicable.

## Evidence and reproduction

- Headless test log: `/private/tmp/braindump-checkpoint3-tests.log`.
- Result bundle: `<DerivedData>/BrainDump`.
- Debug build log: `/private/tmp/braindump-checkpoint3-debug-build.log`.
- Release build log: `/private/tmp/braindump-checkpoint3-release-build.log`.

Use the retained-log/pipefail workflow with:

```sh
xcodebuild test -project BrainDump.xcodeproj -scheme BrainDumpTests -testPlan BrainDumpTests -configuration Debug -destination 'platform=macOS,arch=arm64'
```

For app builds, use scheme BrainDump with build and configuration Debug or Release. No UI verification is required to complete this backend checkpoint. Any later UI check still needs advance approval or a user-led manual walkthrough.
