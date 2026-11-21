# Checkpoint 6 — Menus, Open Project, and routing

Status: complete. The user confirms all six targeted native checks and the final Command-W/Format recheck pass. Checkpoint 5 was committed as `361b617` before this work. Checkpoint 7 has not started beyond the previously authorized folder-repair subset.

## Delivered behavior

- File provides New Capture, New Project, Open Project, Open Recent/Clear Menu, Save, and Project Settings. Command-N/Shift-Command-N/Command-O/Command-S use shared coordinator operations. Projects renders the same reachable-project structure as the editor switcher, with full names and meaningful group labels.
- The Projects global window preference persists in ProjectStore. Project menus/Open Recent snapshot it at selection: ON creates a new editor; OFF saves and reuses the active editor or most recently active editor behind an auxiliary window. With no editor, create one. The switcher always targets its own editor regardless of the preference.
- `ProjectCommandRouter` resolves active/most-recent/originating IDs once before awaiting. Existing form origins are retained; closed origins fall back to the surviving most recent editor, then creation. Open Project → New Project carries that origin forward. Saving and switching remain exclusively in EditorCoordinator.
- Menus, toolbar, and picker use the same coordinator-derived availability checks. Pending transition locks disable conflicting reuse/Save/New Capture actions while unrelated editors remain usable. A manual Save still permits typing and queued saves.
- Failed saves abort reuse without changing project/usage or clearing text. Stale reachability is revalidated before saving and before switching. Project-menu access errors use Open Project's persistent inline error and the failed registration's Settings repair action, retaining the originating editor where applicable. No alternative project is guessed.
- Open Recent retains explicit recency, omits unavailable entries, and never fills missing rows with unrelated projects. Clear Menu clears only MRU; registry and last active stay intact.
- New Project and Open Project each retain independent checkbox memory. Only before a form has a remembered choice does it use the current global default; an availability refresh does not reset an open form.
- Standard About/Services/Hide/Quit, native Undo/Redo/clipboard, and applicable Window commands remain. Explicit spelling/grammar, substitutions, transformations, and speech actions use the native responder chain and validation, including form fields. The default text-editing group was replaced because it includes Find. Plain-text Find/Replace entry points are disabled; no custom editing engine was added.
- Singleton-scene shortcuts that bypass form initialization are suppressed; the native list of already-open windows remains. Existing no-tabbing/restoration guards remain. Actual native Window-menu contents still require the manual gate below.
- Help opens a SwiftUI scene containing bundled local HTML through a small macOS 15 WKWebView bridge. JavaScript is disabled and navigation is restricted to that HTML file and its topic fragments. Help is a real auxiliary window for routing checks. Full Help/accessibility acceptance remains checkpoint 8 work.

Native text-menu observers are app-scoped, start once with the runtime, and are removed during termination. Their finite main-actor callbacks only validate responder actions; they never choose an editor or perform saves. Unchanged validation snapshots do not invalidate views. No idle hints or announcements were added.

## Headless verification

- Debug and Release app builds pass with Swift 6, complete checking, MainActor default isolation, and approachable concurrency unchanged for app/test targets.
- All 107 test functions / 132 cases pass, with zero failures, skipped tests, or runtime warnings, confirmed from the result bundle. Eleven new routing tests cover active/auxiliary/no-editor cases, retained/closed origins, global/explicit modes, preference snapshots, failures, reachability, overlapping routes, and MRU filtering/clearing. Existing capture/form/repair tests still pass.
- Help HTML has five semantic headings, valid local topic links, and no script elements. The Debug app's bundled HTML matches the tracked source. No preview/browser rendering or VoiceOver inspection was performed.
- Changed/new text files pass whitespace checks. The known App Intents metadata-extraction warning remains because the app has no AppIntents.framework dependency; no Swift/concurrency diagnostic remains.

Final Debug log: `/var/folders/3n/x7yqq1590278p0q4yf543jhh0000gn/T/braindump-verification.4eyh5G`.

Final Release log: `/var/folders/3n/x7yqq1590278p0q4yf543jhh0000gn/T/braindump-verification.JtuE6K`.

Final tests log: `/var/folders/3n/x7yqq1590278p0q4yf543jhh0000gn/T/braindump-verification.4SecfG`.

Result bundle: `<DerivedData>/BrainDump`.

No app launch, UI test, or UI automation ran. Service tests and compilation do not establish native menu contents, responder validation, focus, or VoiceOver behavior. Do not mark the checkpoint complete or proceed to checkpoint 7 until the native gate passes.

## Targeted user checks

Use disposable capture text/folders. The capture/save/repair loop already accepted in checkpoint 5 need not be repeated wholesale.

1. Check File shortcuts: Command-N starts a new capture in the intended editor; Shift-Command-N opens New Project; Command-O opens Open Project; Command-S saves the target editor. There must be no implicit New Window shortcut, tabs/tabbing commands, Find, or Replace.
2. With text in an editor, select another project from Projects with Always Open in New Window OFF: it saves and reuses that editor. Turn ON and select a project: a separate empty editor opens and the old editor/text stays. The toolbar switcher still reuses its own editor in both modes. Check the global choice survives relaunch without altering either form's checkbox memory.
3. Check Open Recent order/full names and omission of unavailable projects. Clear Menu empties only recents; Projects/Settings still show registrations, and New Capture/relaunch still use last active as specified.
4. With two editors, activate one, then open Help. Help loads local readable content and topic links. While Help is active, New Capture/Save/project reuse must target the most recently active editor, not another window. Close all editors but leave Help open: a project-menu selection creates one editor, and New Capture uses last active or the existing Open Project recovery flow.
5. Open a project form from editor A, activate editor B, then return and submit the form in reuse mode: it still targets A. If A is closed first, it falls back to B. New Project opened from Open Project inherits that originating target. Check cancel leaves capture/registry/global preference unchanged.
6. In a project-name field, Cut/Copy/Paste and Undo/Redo must affect that field, not an editor behind it. Check native text-menu enablement and visible labels. A failed save must preserve the source capture and prevent reuse; an access failure should stay actionable through Open Project/Settings.

Report any native menu, keyboard, or VoiceOver issue before closing this gate. Automated UI verification still requires advance approval because it interferes with ongoing VoiceOver use.

## Native gate feedback — Close and Format

The user reports all six targeted checks pass, but Command-W does not work and Format is visible with no entries. The saveItem replacement omitted the native Close command (Apple documents Close as part of that group). It now explicitly declares Close/Command-W, validated and dispatched through the native responder chain as performClose. This reaches the existing editor window delegate and save-before-close path; auxiliary windows remain their own close targets. The empty textFormatting replacement was removed instead of creating an empty Format menu. The responder-state helper is now named NativeCommandState because it also validates Close. Both corrections require a focused native recheck; no app/UI automation was run.

Close/Format correction verification: Debug and Release builds pass; all 107 headless test functions still pass. The six original native checks are user-confirmed. Only the focused recheck of Command-W on editor/auxiliary windows and absence of the empty Format menu remains. Changes remain uncommitted.

Final acceptance: the user confirms “Now it works” after the Close/Format corrections and requests committing checkpoint 6 and starting checkpoint 7. This completes the native gate; future UI automation still requires separate advance approval.
