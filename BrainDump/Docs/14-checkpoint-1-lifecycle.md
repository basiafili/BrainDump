# Checkpoint 1 — SwiftUI Window Lifecycle Shell

Status: complete. The user reports all ten manual native checks pass, completing walkthrough A. Checkpoint 2 has not started.

Checkpoint 0 was committed separately as `880f531`. Checkpoint 1 changes remain uncommitted.

## Implemented

- SwiftUI App with an explicitly presented New Project demonstration panel, a session-ID-based editor WindowGroup, and separate Open Project, Project Settings, and Help window routes.
- Editor scenes and other auxiliary scenes suppress default launch. All scenes disable restoration; native attachments also set non-restorable, non-tabbed windows. Automatic window tabbing is disabled during app startup.
- Observable main-actor EditorCoordinator owns session identity, text, lifecycle status, active editor, and most recently active editor. Views look up existing sessions rather than creating them during view reconstruction.
- Repeated demonstration-editor creation produces independent sessions for the same demo project. No registry, persistence, file access, or saving is implemented at this checkpoint.
- An injectable lifecycle decision provider supports allow/reject and two-second delayed allow/reject outcomes. The delay suspends asynchronously, not by blocking the main thread.
- A native registry intercepts close requests, owns finite callback tasks, and closes only after permission. Approved closure calls `close()` rather than recursively requesting permission again. Sessions unregister only after the native close notification.
- An application delegate adapter returns terminate-later while awaiting the coordinator and replies once. Rejected quit retains all sessions and restores editing; accepted quit keeps sessions locked until termination.
- Original SwiftUI delegate close/activation, resize/move, main-window, and live-resize notifications and undo-manager requests are forwarded explicitly. Broad untyped Objective-C forwarding was rejected by Swift 6 sendability checking and was removed rather than weakened with unsafe annotations. The user manually verified normal focus, typing, undo, and window behavior through this adapter.
- Minimal SwiftUI commands expose the demonstration editor and auxiliary routes. This is scaffolding, not the complete checkpoint 6 menu or final New Capture behavior.
- Demonstration panels explicitly state that text is in memory only and files/preferences are not written. The production forms, editor bridge, save policy, project store, and startup last-active resolution belong to later checkpoints.

Checkpoint 5 moves the three headless demo fixture types into `Verification/` and removes their old production UI. The reproduction command below uses their current locations; the results recorded here remain historical.

## Noninteractive verification completed

- Xcode MCP Debug build passed with Swift 6 and complete concurrency checking.
- Latest build log: `/var/folders/3n/x7yqq1590278p0q4yf543jhh0000gn/T/ActionArtifacts/default/BuildProject/BuildProject-Log-20261111-134516.txt`.
- No Swift/concurrency errors or warnings. The existing App Intents metadata-extraction tooling warning remains, as recorded at checkpoint 0.
- Six headless checks passed against the actual coordinator/session source:
  1. Independent stable sessions and active-versus-most-recent tracking.
  2. Pending close locks only its session; duplicate/conflicting operations do not start another decision; rejection preserves text.
  3. Rejected quit keeps all sessions open, restores editing, and leaves activation history unchanged.
  4. Cancellation releases a close lock and preserves the capture.
  5. Approved close retains the session and read-only state until actual window closure, then activation fallback uses the remaining history.
  6. Approved quit retains sessions and read-only state until native termination.
- Checks use continuations for deterministic suspension and do not launch AppKit, create windows, or interact with VoiceOver. The test source lives outside app target membership in `Verification/Checkpoint1LifecycleChecks.swift`.
- The initial headless compile was blocked by the execution sandbox's macro-plugin restrictions; it passed with normal compiler-plugin permissions. No language-mode/diagnostic bypass was used.
- Whitespace checks passed. Release compilation has not been reverified for this checkpoint; checkpoint 0's Release build is not claimed as evidence for new code. Native behavior was subsequently verified manually by the user, as recorded below.

Reproduce the headless checks from the repository root:

```sh
xcrun swiftc -swift-version 6 -strict-concurrency=complete -default-isolation MainActor -enable-upcoming-feature NonisolatedNonsendingByDefault -module-cache-path /private/tmp/braindump-lifecycle-module-cache -parse-as-library Verification/LifecycleDemoSession.swift Verification/LifecycleDecisionProvider.swift Verification/LifecycleDemoCoordinator.swift Verification/Checkpoint1LifecycleChecks.swift -o /private/tmp/braindump-checkpoint1-checks && /private/tmp/braindump-checkpoint1-checks
```

These are temporary executable headless checks, not an Xcode test-target run. Move useful cases into the planned Swift Testing target when that infrastructure is added.

## Manual native acceptance — passed

After the automation attempt below, the user ran the app and reported: “All ten pass.” This is user-reported manual evidence, not an automated UI test result.

1. Launch opens only New Project.
2. Two demonstration editors retain independent text.
3. Opening Help clears active-editor status while preserving the most recently active editor ID.
4. Delayed rejected close pauses editing, then restores it with the window/text intact.
5. Delayed accepted close closes once and reduces the editor count by one.
6. Delayed rejected Command-Q retains all windows and restores editing.
7. Delayed accepted Command-Q terminates the app.
8. Relaunch restores neither old editors nor Help.
9. Closing every window leaves the app running; File → New Project reopens its window.
10. Windows cannot become tabs; editor focus, typing, undo, and VoiceOver navigation work normally.

These results complete the checkpoint 1 native gate and user walkthrough A. No additional UI interaction is needed for this checkpoint. Future UI testing still requires advance approval, or a user-led manual walkthrough, because the computer-use permission UI itself has accessibility issues.

## Automated UI attempt — historical record

### Approved attempt on 2026-11-11

The user approved this verification session. Direct computer-use app attachment timed out, including an attempt to inspect Xcode itself. Attaching by bundle ID reported the Debug/Release copies as ambiguous; selecting the explicit Debug app path still timed out.

Xcode RunProject successfully built/launched BrainDump with debugging, and `process status` confirmed the process was running. Console retrieval returned no output. These observations establish launch/process state only; they do not prove which windows appeared, responsiveness, focus, or native lifecycle behavior. No close/quit/relaunch interaction or VoiceOver walkthrough could be completed through the unavailable native inspection surface. The cause is not established as an application defect or a tool defect.

The Xcode-launched process was stopped through StopProject after the unsuccessful inspection attempts. This is cleanup, not evidence that normal Command-Q works. No product behavior was changed based on the timeouts. Native acceptance was unverified at that point; the subsequent user-led checks above resolved that gate. Ask before starting a later UI verification session because VoiceOver interference remains relevant.

Launch log: `/var/folders/3n/x7yqq1590278p0q4yf543jhh0000gn/T/ActionArtifacts/default/RunProject/RunProject-Log-20261111-135059.txt`.

The user uses VoiceOver while working. Do not launch/control the app or run UI automation until they explicitly approve the proposed verification window. Build and headless checks are not that permission.

The original proposed verification scope was:

1. Launch opens only New Project; no unwanted default editor or restored windows appear.
2. Create two demonstration editors for the same demo project. Trigger view updates and confirm session/text identity is stable.
3. Activate each editor, then Help; active editor becomes none while most-recent editor remains correct. Check editor focus and auxiliary routing.
4. Choose delayed rejection and request native close. Confirm text stays read-only during the wait, the window remains open after rejection, and editing returns. Repeat with delayed approval and confirm one close and one session removal.
5. With multiple editors open, exercise delayed rejected Command-Q. Confirm no windows close, no duplicate termination decision occurs, and all editors become editable again. Repeat with approval and verify termination.
6. Close the final editor while auxiliary windows are present, then close all windows. Confirm the app remains running and commands can open the demonstration routes again.
7. Relaunch with previously open editors/Help and confirm no restoration. Inspect that tab actions cannot produce tabs and native window/undo behavior remains intact through the delegate adapter.
8. Complete user walkthrough A for focus, lifecycle feedback, and VoiceOver behavior. Resolve problems before checkpoint 2.

Do not mark checkpoint 1 complete based solely on compilation or headless state tests.
