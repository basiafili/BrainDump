# Checkpoint 5 — First capture workflow

Status: complete. The user confirms the final folder-repair recheck behaves as expected, completing walkthrough B. Debug/Release builds and all 96 test functions / 121 cases pass. Checkpoint 6 has not started.

## Implementation

- SwiftUI scenes now use the production coordinator, registry, authorization service, and file writer. Every scene suppresses default launch and restoration; one initial scene callback starts the explicit async startup router. There is no temporary launch window. Startup opens only the last active project and preserves MRU ordering, or presents New Project when no last-active reference exists. An unavailable last-active project now opens Open Project with a focused inline explanation and a Settings repair action. Window creation/focus still require manual runtime verification.
- New Project keeps local draft fields and an originating-editor reference. Name/folder validation is inline, the checkbox remembers this window’s own last choice independently of the global preference, and Cancel makes no registry changes. Reopening an already-visible form preserves its draft and origin.
- Create-and-open prepares authorization, saves the reused capture, creates the UTC month folder, revalidates, and commits registration/usage together before resetting or creating a session. Failure/cancellation keeps the old editor and usage state; successful earlier writes remain saved. Quit cannot overtake creation.
- The editor binds directly to coordinator-owned text. The small NSTextView bridge provides plain-text paste, wrapping, native spellchecking/context menus/text services, disabled smart substitutions, system monospaced text, and a separate undo manager for each capture generation. Focus changes only on opening/reset/switch, not ordinary saves.
- Core toolbar actions have visible text labels and shared coordinator operations. The switcher consumes the common grouping structure and always reuses its own editor. Basic File commands and a real Open Project picker support this first usable loop; remaining menu/global-preference/full-settings/help work stays in its planned checkpoints. A focused Settings folder-repair path has been brought forward at the user’s request so recovery is actionable.
- Persistent save status and inline issues supplement accessible announcements. Snapshot completion distinguishes newer unsaved edits. Native close and quit use structured coordinator outcomes; blocked workflows present one error and keep windows open.
- The no-write demo UI and folder probe were removed from the app. Three historical headless lifecycle fixture types remain in `Verification/`, outside app/test target membership.

## Headless evidence

Both app build configurations pass with Swift 6, complete checking, MainActor default isolation, and approachable concurrency. No concurrency settings were reduced or unsafe workarounds introduced.

All 96 test functions / 121 cases pass, with zero failures, skipped tests, or runtime warnings, confirmed with xcresulttool. New tests cover transactional reuse/new-window creation, save/month-folder failures, concurrent duplicate registration, cancellation, a moved target folder, no-MRU startup fallback, explicit-use MRU updates, a changed folder-selection identity before creation, last-active preservation during internal failure presentation, and a real create/save/bound-empty/close/relaunch service loop.

Final Debug build log: `/var/folders/3n/x7yqq1590278p0q4yf543jhh0000gn/T/braindump-verification.ayQqy6`.

Final Release build log: `/var/folders/3n/x7yqq1590278p0q4yf543jhh0000gn/T/braindump-verification.A9aAZz`.

Final tests log: `/var/folders/3n/x7yqq1590278p0q4yf543jhh0000gn/T/braindump-verification.9Pirdq`.

Result bundle: `<DerivedData>/BrainDump`.

The known tool warning about skipped App Intents metadata extraction remains because there is no AppIntents.framework dependency. No Swift/concurrency diagnostics remain. Changed/new text files pass whitespace checks.

No app launch, UI automation, or UI tests ran. Compilation and service tests do not establish native focus, accessibility, toolbar appearance, undo behavior, or sandboxed relaunch behavior for this integration. Prior checkpoint UI approvals do not authorize an unannounced new UI run.

## Walkthrough feedback and corrections

The user reports that capture, update/save, New Capture/reset, bound-empty preservation, and reopening work. They found a false duplicate-name announcement, a creation form remaining visible, toolbar overflow, redundant delayed hints, checkbox accessibility/memory problems, and unhelpful unavailable-project recovery.

Corrections:

- Validation pauses while submitting and ends permanently for a completed creation. The closing form cannot report its own newly registered name as a duplicate. The native bridge closes the exact form window after commit, avoiding stale busy/button state in scene dismissal. Open Project uses the same close-request mechanism.
- New Project and Open Project each store their own checkbox state in separate UserDefaults keys and restore it across window/app launches. Neither changes the other window, registry usage, or the global preference. Open Project seeds its choice once per form request instead of resetting it during its availability-refresh task. Both forms use native checkbox style, with the checkbox before its label.
- App-provided editor help and field hints were removed. Inline text no longer announces itself automatically on appearance/change. Explicit save feedback remains; true workflow/folder-selection errors receive accessibility focus. No idle timer/help was added.
- Editor default/minimum width is 1340 points, default height 700, with an expanded native toolbar. Smaller resizing is constrained. Native toolbar fit still requires verification on the user's display; screens narrower than this minimum or exceptionally long labels/project names cannot be guaranteed overflow-free. Icon-only controls were not silently substituted.
- An unavailable last-active project opens Open Project, with VoiceOver focus requested on its error and a Project Settings button. The Settings folder-repair view includes unavailable registrations, retains drafts until OK, and uses existing keep-open/save-and-close coordinator rules. It does not implicitly open a different project. Full Settings rename/removal and other checkpoint 7 controls remain later work.
- Regression tests cover both real duplicate rejection and suppression after successful registration, independent checkbox persistence, and an actual renamed-folder → Open Project error → explicit folder repair → reopen service loop, preserving registration identity, usage, and user files.

Targeted recheck (the already-passing capture loop need not be repeated):

1. Create a project: no false duplicate announcement, and New Project closes when the editor opens.
2. Reopen New Project: checkbox choice survives; checkbox and label are one VoiceOver stop. Check Open Project checkbox semantics too.
3. Leave the editor idle: no app-provided delayed help. Check the larger window has no toolbar overflow and cannot shrink below its minimum.
4. Rename the last-active folder while the app is quit: Open Project receives focus on the error, with a working Project Settings repair button.
5. Repair the registration via Change Folder/OK, return to Open Project, and explicitly open it. Verify the old registration is reused and files remain intact.

## User walkthrough B

Use disposable project folders. The app now writes real Markdown files.

1. Launch: New Project appears if no last-active project exists. Check the name, folder path, checkbox, Cancel/Create labels, and inline validation. Empty/duplicate names or a duplicate folder must not be accepted.
2. Create a project: its selected folder contains a UTC month subfolder, no Markdown file yet, and one empty editor opens with text focus.
3. Type Markdown with quotes/dashes, Save, and inspect the UTF-8 file. Edit and Save again: the file and localized first-save title remain the same.
4. Choose New Capture with unsaved text: it saves, clears, resets the title, and focuses the editor. Undo must not restore the previous capture.
5. Check wrapping, native undo/redo, plain-text paste, Cut/Copy/Paste, spellchecking, context menus, keyboard navigation, toolbar labels, and VoiceOver save feedback. Manual Save must permit continued typing.
6. Save a capture, clear it to whitespace, and Save/close: the saved file remains intact. Closing the final editor leaves the app running; Command-N returns to the last project.
7. Create another project by reusing an editor, then another in a new window. The old capture must save before reuse. Cancel/invalid creation must preserve it. Open Project and the switcher must start fresh captures, saving the old capture first.
8. Quit with multiple non-empty captures, then relaunch: files are saved and only one empty editor for the last active project opens; no old text/windows return.
9. With editors closed, quit and rename/move the last-active project folder outside the app. Relaunch: Open Project focuses the inline error and does not open another reachable project. Choose Project Settings, Change Folder, select the renamed directory, and OK. The existing registration becomes available again without moving/deleting files or creating another project.

Record observed failures and VoiceOver/editor feedback before marking the checkpoint complete or proceeding to checkpoint 6.

## Further walkthrough feedback

The user confirms successful form closing, New Project checkbox memory, quiet idle behavior, and toolbar fit. Open Project was still resetting its checkbox; this is now corrected with the same per-window storage service and independent keys. Regression coverage checks checked/unchecked persistence for both forms and their independence from each other/global settings.

A reported folder-repair error remains under investigation: the user says they were repairing the renamed parent project's own registration, saw its old name above the newly selected path, and received a folder-in-use error after OK. A real filesystem regression reproducing registered parent/child folders, a parent rename, and repair of each correct registration passes; using the same folder for a different registration correctly fails. This does not establish the cause of the user's UI failure. The user clarified that the original registered path ended in TestFolder2/TestFolder3, they changed its final component to TestFolder34, received the error after OK, and created TestFolder5 as a workaround. The saved app registry and known folder metadata were inspected read-only; no user registrations or files were changed. No UI launched or controlled.

Settings target correction: the view previously assigned its initial registration in onAppear, which could reset a later user selection when returning from native presentation. It now seeds an observable folder draft once per Settings request. Each picker request carries its registration ID and unique token; stale/cancelled results cannot attach to another project. OK captures the registration/folder pair before a confirmation or async operation. Native row accessibility activation explicitly selects the registration. Visible labels distinguish Project, Registered folder, and Selected folder, and Change Folder identifies the target accessibly. Conflict errors now name the conflicting registration/path and the failed operation identifies its target. Genuine duplicate registration remains prohibited; self-repair still excludes its own ID.

Three further tests cover stale picker results, preservation of accepted drafts on repeated selection, and immutable submitted repair targets. All 96 functions / 121 cases pass in the result bundle (the condensed parser undercounted this run by one function). Debug and Release builds pass with unchanged Swift 6 checking. The exact native failure remains unverified; the next user check is the original registration ending in TestFolder3 → existing TestFolder34 → OK. No application registry or user files were modified during diagnosis, and no UI was launched/controlled.

Final user acceptance: “Now it behaves as expected.” The final folder-repair recheck passes. This completes the checkpoint 5 native gate and walkthrough B; future UI testing still requires advance permission.
