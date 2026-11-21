# Implementation Plan

Status: checkpoints 0–7 complete; checkpoint 6 committed as `a83f191`. The user accepted checkpoint 7, including its native Settings and double-click fixes. Checkpoint 7 committed as `22f2a94`. Checkpoint 8 implementation and targeted automated acceptance are complete, with contrast excluded by user decision and the recorded VoiceOver/live-field-editor evidence limits; see [checkpoint 8 evidence](21-checkpoint-8-ui-acceptance.md). See [checkpoint 7 evidence](20-checkpoint-7-settings.md).

## Purpose and authority

Implement the committed specifications in small, reviewable increments, using SwiftUI for lifecycle/presentation and Swift Concurrency for isolation and asynchronous workflows. This plan sequences work; it does not replace the product specifications or introduce additional product behavior.

Swift 6 language mode with complete concurrency checking is required for app and test targets. Establish it in Checkpoint 0, before adding implementation. This migration is authorized; do not retain Swift 5 mode as a fallback.

Use the installed `swiftui-expert-skill` and `swift-concurrency` skills throughout implementation. Revisit their relevant references when implementing scenes, state ownership, native editing, actor boundaries, or task lifetime. Both skills are installed locally; copying skills from Explorium is unnecessary.

If an invariant is missing, a specification conflicts with another, or preserving a behavior requires a product decision, stop that work and ask the user one question at a time. Resolve it in the specifications before implementing it. Technical experiments may establish feasibility; they must not silently decide product behavior.

## Checkpoint protocol

Each numbered checkpoint has a deliverable and an exit gate. Do not start the next checkpoint with a failing gate or an unexplained diagnostic. Report completed behavior, verification evidence, known limits, and the next step. Keep changes suitable for a separate commit; commit only when authorized.

The marked user walkthroughs are deliberate opportunities to review behavior before more UI is built on it. During implementation, pause there for feedback. Other checkpoints are verification gates that can proceed after passing unless a product question arises. Planning this work does not begin implementation.

Use Xcode MCP for compact builds/diagnostics and the local xcsift workflow for routine tests. Read relevant saved-log sections when condensed output is insufficient. Do not rerun checks solely through a different tool. Use isolated temporary folders and UserDefaults suites for tests; never use real project content as test fixtures.

Before UI tests, UI automation, or interactive app verification, stop and ask the user for approval. Give advance notice of planned app launches/focus changes because they disrupt ongoing VoiceOver use. Noninteractive builds and headless checks may proceed. A pending UI gate is not passed by a successful build or headless check.

## Implementation boundaries

| Area | Planned ownership |
| --- | --- |
| SwiftUI App, scenes, commands, forms | Presentation and forwarding user intent |
| ProjectStore | Main-actor registry, MRU, last active, preference, persistence commits |
| EditorCoordinator and observable sessions | Main-actor text/state ownership and all editor workflows |
| Filesystem/access services | Off-main folder resolution, authorization work, file inspection and atomic writing |
| Immutable request/result values | Sendable snapshots across actor boundaries |
| Small platform adapters | Native editing, window events, folder picker, Finder, Help web view |

- Prefer macOS 15-compatible native SwiftUI APIs; check SDK availability before selecting newer APIs. Do not add Liquid Glass or a document lifecycle.
- SwiftUI observes coordinator-owned session state. Forms own drafts; they do not mutate the registry while the user types.
- Editor windows use stable session IDs, not project paths or view identity. A separate stable registry handle may link records while paths change; physical folder identity still defines duplicate-project rules.
- A dedicated writer actor is the initial design for serializing capture filesystem operations across sessions. Its synchronous I/O runs in its own isolation domain, not on the main actor. Do not assume `async` alone moves work off-main.
- Do not suspend between checking/allocating a target and the critical write if that would permit actor reentrancy to break reservation rules. Coordinate external changes using appropriate filesystem primitives, not actor isolation alone.
- Retain per-session operation state across awaits. Revalidate session/revision/operation identity before applying results. A writer actor alone does not prevent two coordinator workflows from interleaving.
- Use structured async calls inside workflows. Tasks needed to bridge synchronous UI callbacks have explicit ownership and completion/cleanup. Avoid detached tasks and unsafe Sendable/isolation escape hatches without a demonstrated need and documented invariant.
- A completed write must be reflected in the session even if a surrounding task is cancelled. Never pretend an irreversible write was rolled back. Prevent stale completions from attaching to a replacement capture.
- Keep access authorization alive for both current project folders and original bound-file folders. Release access when no operation/session needs it, including failure paths.

## Checkpoint 0 — Confirm project and toolchain baseline

Completed on 2026-11-11. Swift 6/complete checking is configured; Debug and Release baseline builds pass. No test target exists yet; its setup is identified for checkpoint 2. Full settings, warning record, sandbox limits, and commands are in [the baseline report](13-checkpoint-0-baseline.md).

Deliver:

- Discover the actual project, app target, schemes, test plans, compiler version, and Debug/Release effective settings through Xcode tooling.
- Record effective Swift language mode, strict concurrency checking, default actor isolation, approachable concurrency, and upcoming features. Before checkpoint 0 the target used Swift 5.0 without an explicit strict-checking setting; checkpoint 0 changes it to Swift 6.0/complete. MainActor default isolation, approachable concurrency, and member-import visibility remain enabled. The target's effective deployment minimum is confirmed as 15.0 despite a differing project-level setting.
- Set Swift language mode to 6 and ensure complete concurrency checking in Debug and Release for the app and all test targets. Review inherited isolation/upcoming-feature settings against the actual toolchain; fix isolation and Sendable diagnostics at their ownership boundaries.
- Establish the smallest baseline macOS build. Confirm sandbox/read-write selected-folder settings and what bookmark authorization the implementation needs.
- Identify the test target/scheme setup needed for the service tests; preserve the simple existing project structure.

Exit gate:

- The starter builds, or its exact existing blocker is recorded and fixed before proceeding.
- Effective settings confirm Swift 6 language mode and complete concurrency checking; compiler/isolation settings are known. The baseline builds without unresolved concurrency diagnostics. Do not downgrade language mode, reduce checking, or introduce unsafe isolation/Sendable workarounds to pass this gate.
- A reproducible build/test invocation is documented once the actual scheme exists. No placeholder command is reported as a passed check.

## Checkpoint 1 — Prove SwiftUI window lifecycle boundaries

Complete: the shell builds, six headless lifecycle checks pass, and the user reports all ten manual native checks pass, completing walkthrough A. Automated native inspection was unavailable; native acceptance is based on the user's manual verification. See [the checkpoint report](14-checkpoint-1-lifecycle.md).

Deliver a minimal SwiftUI shell with temporary in-memory state, not a second application architecture:

- Explicit editor-session creation and multiple editor windows for the same project.
- Auxiliary SwiftUI window routes for New Project, Open Project, Project Settings, and Help.
- Minimal native adapters for activation, close requests, asynchronous quit deferral, and suppression of tabs/restoration where SwiftUI alone is insufficient.
- A fake coordinator outcome that can delay, allow, or reject close/quit, so native callbacks can be exercised before real saving exists.

Exit gate:

- Rebuilding a view does not create another session.
- Native close and Command-Q wait for an asynchronous decision; failed simulated quit leaves every window open. Completion does not recursively trigger another save.
- Closing the final editor leaves the app running. A relaunch does not restore old editor windows or create an extra default editor alongside the intended startup window.
- Two editors and Help demonstrate that activation tracking distinguishes the active editor from the most recently active editor.

**User walkthrough A:** review window creation, focus, close/quit behavior, and the absence of tabs/restoration before connecting real user content.

## Checkpoint 2 — Registry, folder access, and project-list data

Complete: noninteractive checks pass, and the user reports all manual sandboxed bookmark/relaunch checks passed. See [the checkpoint report](15-checkpoint-2-registry.md).

Deliver:

- Project records, persistent UserDefaults representation, main-actor ProjectStore, and folder-access service.
- Canonical physical-folder duplicate detection, name validation, availability reasons, and explicit registration/rename/path-change/removal APIs.
- Security-scoped bookmark acquisition, resolution, and balanced access lifetimes. Keep old-folder access independent of a changed registry path.
- MRU with a maximum of 10, separate last-active reference, and OFF as the unset global window-opening preference.
- One shared sort/group builder for both compact project selectors, with meaningful localized labels and the specified 15-item/10-item grouping rules.

Exit gate:

- Tests cover persistence round trips, whitespace/case name duplicates, symlink folder aliases, and filesystem-sensitive path case handling.
- Explicit usage changes MRU; focus changes last active only; saves change neither. Clear Menu and removal update only the specified references.
- Unreachable entries remain in registry/settings data and disappear from selector data without selecting replacements.
- Shared grouping fixtures cover 15 versus 16 projects, more than 10 with the same initial, multiple scripts, diacritics, digits/symbols, and one versus several fallback candidates. No project is lost or duplicated.
- A sandboxed relaunch experiment confirms persistent folder access; mocks alone do not establish this.

## Checkpoint 3 — Capture writer and external-file safety

Complete: the user approved the platform-bounded external-write guarantee; the writer, file-safety tests, and Debug/Release verification pass. See [checkpoint 3 evidence](16-checkpoint-3-capture-writer.md). Simultaneous changes that bypass macOS file coordination receive best-effort detection, as recorded in Project and Capture Rules.

Deliver:

- Injectable clock, fixed UTC Gregorian filename formatter, collision allocator, and atomic UTF-8 writer.
- Unbound creation and bound update/recreate/copy behavior using last-written content baselines.
- A write result containing the actual URL, stable first-save time, and new baseline; no UI or UserDefaults mutation in the writer.
- A demonstrable strategy for safe allocation and external-writer races. A read-compare followed by an unconditional overwrite is insufficient; exercise the coordination/publication boundary explicitly.

Exit gate:

- Temporary-folder tests cover exact content preservation, Unicode, whitespace-only no-ops, and a cleared bound file remaining unchanged.
- Controlled time covers UTC month/year boundaries, non-Gregorian/user numeral settings, repeated timestamps, and suffixes beyond 99.
- Simultaneous sessions cannot overwrite each other when allocating names.
- External rename/deletion recreates the original path; external content editing preserves that file, creates the next suffixed copy, and returns the new binding. Further copies use the original timestamp stem, not stacked suffixes.
- Unreadable paths, competing creation, failed writes, and a change at the comparison/write boundary do not silently overwrite unrelated/external content or publish partial captures.
- Failed operations retain the original binding/baseline at the caller. Old-folder saves remain possible after a project folder change.

## Checkpoint 4 — Coordinator save and transition state machine

Completed on 2026-11-11. See [the coordinator report](17-checkpoint-4-editor-coordinator.md). Production UI integration remains checkpoint 5.

Deliver UI-independent async workflow contracts:

- Session registration, text/revision updates, manual Save, New Capture, close, and project switch.
- One save path with per-session serialization and snapshot-aware completion.
- Transition read-only state, conflicting-command prevention, and structured success/failure/presentation outcomes.
- Multi-session prepare/commit handling for quit, removal, and save-and-close folder changes.

Exit gate:

- Use controllable async writer fakes to pause at awaits and inject failures deterministically; do not use sleep-based timing tests.
- Typing during manual Save survives completion and remains unsaved; repeated saves do not use stale bindings or baselines.
- New Capture/switch/close locks before saving, resets only after success, and restores editing without lost text on failure.
- Starting a transition during a pending manual save cannot clear newer text or apply its result to a new capture.
- For multi-window operations, a failure in a later session closes no windows and commits no registry changes; earlier successful writes stay saved.
- Repeated close/quit requests and cancellation do not bypass the pending operation, strand a busy state, leak a task, or update MRU from internal save order.

## Checkpoint 5 — First complete capture workflow

Completed on 2026-11-11. The user reviewed the capture workflows and confirms the final repair correction behaves as expected, completing walkthrough B. Folder repair was brought forward from checkpoint 7 at the user’s request to make unavailable-project recovery actionable; the rest of that checkpoint remains deferred. See [the capture workflow report](18-checkpoint-5-capture-workflow.md).

Deliver:

- Real startup routing and New Project form, including inline startup/access explanations and transactional create-and-open.
- SwiftUI editor window connected to coordinator state and the real writer.
- Evaluate native SwiftUI editing against required behavior. Use a focused NSTextView bridge if needed for plain text, wrapping, spellchecking, text services, undo boundaries, and Markdown-safe typing.
- Localized title formatting, visible-label toolbar core actions, accessible saving/read-only/error feedback, and editor focus.

Exit gate:

- First launch → choose folder → create project → type → Save → New Capture → close → relaunch works in the sandbox.
- Creation failure registers nothing and leaves the old editor/usage state intact; a successfully written prior capture is not rolled back.
- Launch opens only last active when reachable; otherwise New Project with an inline explanation, never another MRU project.
- Clearing a saved capture then saving/closing leaves the old file intact. Undo after a successful reset cannot resurrect the previous capture in the new one.
- Saved titles keep the first-save time across updates and external-change copies, displayed in local time/locale.

**User walkthrough B:** review the first usable capture loop, editor feel, toolbar labels, save feedback, and inline errors before expanding project management.

## Checkpoint 6 — Menus, Open Project, and routing

Completed. The user confirms the six native checks and final Command-W/Format recheck pass. See [the menus and routing report](19-checkpoint-6-menus-routing.md).

Deliver:

- SwiftUI App/File/Edit/Projects/Window/Help commands and shortcuts, sharing coordinator actions and enabled state with the toolbar.
- Open Project form, global window preference, Open Recent/Clear Menu, and the editor project switcher.
- One compact project-list structure rendered by menu and switcher. Each form remembers its own checkbox independently, using the current global preference only until that form has a remembered choice. Neither writes back to the global preference.

Exit gate:

- Exercise active editor, Help-active with an existing editor, and no-editor cases. Reuse chooses the specified editor; no editor creates one. Forms retain their originating target as specified.
- Global ON opens a new editor from project menus; OFF saves/reuses. The switcher always reuses its own editor.
- Save failure aborts routing. Reachability is rechecked before abandoning the current capture.
- MRU order, full project names, grouping labels, unavailable filtering, and Clear Menu match the shared rules.
- Native editing commands target the focused editor or form field. Command-N means New Capture, and no implicit SwiftUI New Window, tab, Find, or document command bypasses app workflows.

## Checkpoint 7 — Settings transactions and removal

Complete: implemented with the user-confirmed row-commit/draft rules; the user accepted the native fixes and checkpoint 7 was committed. See [the Settings report](20-checkpoint-7-settings.md).

Deliver:

- SwiftUI settings drafts, persistent validation, unavailable-project status, folder repair, and Reveal in Finder.
- Committed renames, both folder-change choices, and separately confirmed removal.
- Registry/reference updates coordinated with prepared session outcomes, without partial metadata commits across awaits.

Exit gate:

- Invalid rows and disabled OK do not commit their drafts. Cancel discards only unapplied drafts; earlier valid row commits remain. A successful rename updates every matching title.
- Test bound-clean, bound-dirty, bound-cleared, and unbound-nonempty sessions together during folder changes.
- Keep-open retains bound files/access and redirects only unbound/future captures. Save-and-close writes to old destinations and closes only after all required saves succeed.
- Failed save leaves all affected windows open and registration unchanged. Removal does not commit unrelated drafts or delete files.
- Removing last active clears its reference without guessing a replacement; unavailable entries can be repaired or removed with clear feedback.

**User walkthrough C:** review multi-window folder changes, failure recovery, unavailable projects, and removal before the final polish pass.

## Checkpoint 8 — Help, accessibility, and final acceptance

Deliver:

- Bundled local HTML Help in a SwiftUI-hosted web view, with scripting disabled and no remote dependency.
- Consistent system typography/colors, SF Symbols and visible labels, localized group wording and dates, and accessible errors/status throughout.
- A short acceptance record mapping the completed checkpoints to specifications and actual verification outcomes.

Exit gate:

- Complete required service/coordinator tests, then exercise the integrated app's native lifecycle and multi-window scenarios. Include real sandbox relaunch/access checks, not just unit tests.
- Keyboard-only and VoiceOver walkthroughs cover capture, forms, meaningful groups, inline errors, busy/read-only state, save outcomes, settings, and Help headings.
- Check light/dark appearance, practical text-size changes, and toolbar readability at supported window sizes. Do not claim compatibility or accessibility checks that were not run.
- Confirm no search/browser/tabs, restoration, extra autosave path, remote Help content, or unintended file deletion has appeared.
- Review Debug/Release effective macOS minimum, Swift 6 language mode, complete concurrency checking, and concurrency diagnostics for app and test targets. Resolve newly introduced diagnostics rather than suppress them without an invariant.
- Final diff has no generated binaries/logs/user preferences and passes whitespace checks. Report any environment-limited checks explicitly.

**User walkthrough D:** demonstrate the acceptance scenarios and capture any remaining product feedback before calling the implementation complete.

## Evidence to keep at each checkpoint

Record the checkpoint status, relevant commit when authorized, commands/tool operations and test scope, concise outcomes, and manual observations. Link retained raw logs or result bundles only when useful. Mark unperformed checks as pending, not passed. If a product decision changes a specification, update the relevant specification and this plan before continuing.
