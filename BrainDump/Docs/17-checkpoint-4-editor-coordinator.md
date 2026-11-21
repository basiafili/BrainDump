# Checkpoint 4 — Editor coordinator

Status: complete on 2026-11-11. Checkpoint 5 has not started. Committed as `60cffbf` before checkpoint 5 began.

## Delivered behavior

`BrainDumpCore/EditorCoordinator.swift` owns observable editor sessions and UI-independent async save and transition outcomes. `EditorSession.swift`, `EditorWorkflowTypes.swift`, and `CaptureTitleFormatter.swift` provide session state, structured results, and localized titles based on the first successful save.

- Manual saves freeze text at request time and run in a per-session FIFO. Each queued write uses the preceding successful binding. Typing during a save survives and remains unsaved when it differs from the saved snapshot.
- New Capture, switch, close, quit, removal, and save-and-close folder changes share the save path. Transitions lock affected editors before awaiting. Failure preserves content, releases locks, and returns a presentable issue.
- Bulk operations save in stable creation order. Any failure grants no close permission and changes no registry entries; completed disk writes remain reflected in their sessions.
- Successful close permission keeps sessions locked until the native window callback confirms closure. Unexpected closure is rejected. Repeated and conflicting commands cannot bypass pending work.
- Cancellation retains successful write receipts. Capture-generation checks prevent late results or bulk operations from modifying or closing replacement captures. A successful save clears only a save issue, preserving unrelated project-access errors.
- Project removal, folder changes, rename, active-window history, and observable project-busy state are covered. Existing bound captures retain their original folder after a keep-open folder change. Internal close activation does not guess a replacement last-active project.

The visible application remains the checkpoint 1 no-write demo. Its types are now explicitly named `LifecycleDemoSession` and `LifecycleDemoCoordinator`; production UI wiring is checkpoint 5. No UI behavior was reverified or claimed from these headless checks. Settings draft integration remains a later checkpoint and must commit combined metadata edits atomically.

## Verification

Swift 6 language mode, complete concurrency checking, MainActor default isolation, and approachable concurrency remain enabled for app and unit-test targets. No unsafe isolation workaround was introduced.

- Debug and Release app builds passed through `scripts/verify.sh`.
- All 75 test functions / 97 cases passed, with zero failures, skipped tests, or runtime warnings, confirmed from the result bundle.
- Continuation-controlled writer fakes test await boundaries and failures without sleep-based timing. Real filesystem integration covers save, external-edit conflict copy, New Capture, and close.
- No UI tests, app launch, or UI automation ran. Future UI activity still requires advance user approval.

Final raw logs (temporary local evidence):

- Tests: `/var/folders/3n/x7yqq1590278p0q4yf543jhh0000gn/T/braindump-verification.Ucc9FV`
- Debug: `/var/folders/3n/x7yqq1590278p0q4yf543jhh0000gn/T/braindump-verification.AGrC51`
- Release: `/var/folders/3n/x7yqq1590278p0q4yf543jhh0000gn/T/braindump-verification.bylCWE`
- Result bundle: `<DerivedData>/BrainDump`

The known build-tool warning about skipped App Intents metadata extraction remains: the app has no AppIntents.framework dependency. No Swift or concurrency diagnostics remain.
