# Checkpoint 8 — UI automation and accessibility acceptance

Status: checkpoint 8 implementation and targeted automated acceptance are complete, with the evidence limits below. Contrast investigation is closed by user decision. Checkpoint 7 is committed as `22f2a94`; checkpoint 8 is committed with this acceptance record. The XCTest suite contains 46 UI test methods. Contrast checks are excluded, not marked passed.

## Implementation

The shared `BrainDumpUITests` scheme and English test plan are separate from the app and hostless service-test schemes. Tests use XCTest/XCUIAutomation only. Each uses a UUID preference suite and runner-owned temporary directory, authorized to the sandboxed app through a real native folder panel. Bootstrap seeds real registrations and bookmarks; tested actions use production views, coordinator, and writer. A bounded writer file gate makes snapshot/read-only checks deterministic. Cleanup removes only the UUID preferences/files and the test's Finder window. Release excludes test configuration.

The app and UI target use Swift 6, complete concurrency checking, and MainActor default isolation. XCTest classes are explicitly nonisolated to preserve their inherited initializers; their UI methods are MainActor-isolated. English is the initial supported language; no additional translations were added.

Accessibility identifiers cover editor windows/text, form controls, project rows, and Help. Open Project's enclosing native scroll area is labelled “Available projects”. Native hosting content has meaningful labels. Decorative zoom-button image groups are excluded while preserving the native button. A small native project-menu adapter exposes a real accessibility press action and retains ProjectListBuilder grouping; the SDK's SwiftUI Menu and Picker failed that action audit. Unchanged menu/toolbar state is not rebuilt during typing.

Open Project uses the list's native primary action for double-click opening. Auxiliary scenes remove implicit creation shortcuts that bypass form initialization. New Project uses a column form to avoid the grouped form's reproducible accessibility parent/child mismatch. Capture editors disable inline predictions and automatic text/math completions, as explicitly requested; spellchecking and explicit native services remain. Native Undo/Redo and window undo-manager lookup now use the capture's actual undo manager.

Settings' project-name field has a persistent visible/accessibility label, including when empty. Auxiliary-window visibility is cleared by native window closure rather than SwiftUI `onDisappear`: replacing an identified view must not mark its open window as closed. The origin regression now fills New Project before activating another editor, raises the form through its public command, and checks both retained draft and save destination.

## Execution policy and evidence limits

Run only cases needed for a repair. The UI runner requires an explicit filter; unfiltered invocation is rejected. Ask before each interactive test interval because it disrupts VoiceOver. No UI test is running. No accessibility/display settings were changed. No additional full-suite reruns are authorized as routine verification.

UI tests require a quiet foreground desktop. A saved failure screenshot showed another app and Command-Tab covering the test app during an earlier run, so affected results cannot establish application defects. The baseline second full run recorded 22 passed and 23 failed test cases, with several failures later traced to shared driver assumptions, input interference, or invalid pixel measurement. It is not a passing acceptance run.

Audits use `.all.subtracting(.contrast)`: element detection, hit region, sufficient description, action, and parent/child structure. Contrast is omitted by explicit user decision, without asserting compliance. Full VoiceOver reading order, speech/announcement behavior, and focus-notification timing are not established by these audits. iOS-only dynamic-type/clipping/trait categories are not exposed by this SDK on macOS.

Help receives the same noncontrast audit against its accessibility hierarchy. Contrast-specific scrolling, viewport deferral, and native-chrome classification have been removed. Opening animations are disabled only in the Debug UI-test environment.

## Coverage map

| Acceptance/regression | XCTest coverage |
| --- | --- |
| First launch only New Project; existing-folder creation; no self-duplicate error; form closes; reopen | ProjectFormsUITests first-project test |
| Empty/duplicate name and duplicate physical folder; Cancel | ProjectFormsUITests name/folder validation |
| Both form checkboxes remembered independently and across relaunch; double-click Open | ProjectFormsUITests checkbox/double-click test |
| Unavailable last active uses actionable Open Project, omitted selectors, explicit repair | ProjectFormsUITests unavailable test; AccessibilityUITests unavailable/invalid audits |
| Nested folder rename repairing its own registration | ProjectFormsUITests nested-rename regression |
| Form-origin preservation across Open → New and other activation; fallback after origin closes | ProjectFormsUITests origin test; MenuAndLifecycleUITests fallback test |
| Exact text; update same file/title; New Capture save/clear and undo reset | CaptureUITests save/update test |
| Exact direct typing without predictions/completion; Undo/Redo | CaptureUITests direct-typing regression |
| Idle thinking time keeps focus and adds no hints | CaptureUITests thinking-time regression |
| Empty/cleared bound saves preserve files | CaptureUITests empty-save test |
| External rename/deletion recreates original name; external edit creates/rebinds copy | CaptureUITests external-change test |
| Manual save permits newer typing; transition read-only; failed close restores editing | CaptureUITests snapshot and close tests |
| Quit failure retains every window; successful quit saves; no restoration | CaptureUITests quit test; Help relaunch test |
| Immediate valid Settings row commit; Cancel only unapplied drafts; rename all titles | SettingsUITests valid-row test |
| Invalid drafts retain problems and block OK while selection moves | SettingsUITests invalid-draft test |
| Folder-decision Cancel retains whole draft; OK applies all | SettingsUITests cancelled-decision test |
| Mixed clean/dirty/cleared/unbound captures; keep-open and save-close destinations | SettingsUITests two mixed-capture tests |
| Removal uses committed metadata, ignores invalid drafts, never deletes files; no guessed last active | SettingsUITests removal test |
| Failed folder save/removal keeps metadata, draft, windows; retry | SettingsUITests failure/retry tests |
| Later OK failure retains earlier successful commit/close | SettingsUITests later-failure test |
| Retained folder draft invalidated by competing row commit | SettingsUITests competing-folder test |
| Unavailable entries rename/remove without folder access | SettingsUITests unavailable test |
| Cmd-W closes correct auxiliary/editor; no windows remains usable | MenuAndLifecycleUITests close test |
| No empty Format, Find/Replace or tab commands; toolbar visible at minimum size | MenuAndLifecycleUITests menu/toolbar test |
| Native form editing/undo; global new-window routing vs toolbar reuse | MenuAndLifecycleUITests editing/global tests |
| Help preserves most-recent target; clear recents preserves registry/last active | MenuAndLifecycleUITests Help/recent test |
| Meaningful group labels/full row names; labelled scroll area | MenuAndLifecycleUITests grouping test |
| Reveal committed folder, not draft | MenuAndLifecycleUITests Finder test |
| Help topics/local link and no restoration | MenuAndLifecycleUITests Help test |
| All five windows in light/dark; unavailable/invalid forms; required decisions | AccessibilityUITests, all supported noncontrast audits with diagnostics |

## Verified results

- Hostless suite: 127 test functions passed, zero compiler warnings/errors (`braindump-verification.iFWDwJ`).
- Release app build passed with no compiler warnings/errors (`braindump-verification.bxBZ7A`).
- UI target compiled with Swift 6 and complete checking (`braindump-verification.RnyQQD`).
- Exact typing, deletion, Undo and Redo passed after the native undo repair (`braindump-ui-tests.EBBWM4`).
- Save/update/New Capture and undo-context reset passed with the repaired undo path (`braindump-ui-tests.5MlJK8`).
- Mixed clean/dirty/cleared/unbound Save and Close passed, saving at old destinations and closing only after success (`braindump-ui-tests.Mj7Nli`). Keep Open had also passed its focused scenario (`braindump-ui-tests.xDQTXj`).
- Reveal selected the committed folder, retained the draft, and cleaned up its Finder window (`braindump-ui-tests.SIAbzY`).
- Menu exclusions, implicit-scene suppression, minimum-width toolbar visibility passed (`braindump-ui-tests.MNxHGh`). Global new-window preference versus toolbar reuse passed (`braindump-ui-tests.JUmusE`).
- Editor and Open Project audits passed in both appearances during focused/baseline verification. Help's viewport-aware light audit passed (`braindump-ui-tests.a9kyKa`).
- First-project creation/form closure/relaunch (`braindump-ui-tests.ejyV0h`) and double-click/independent checkbox memory (`braindump-ui-tests.kP75Mi`) passed focused checks.

Raw logs and result bundles remain outside Git. The UI runner now retains each result bundle next to its unique raw log, avoiding DerivedData's automatic pruning. Some XCTest runs emitted internal thread/QoS advisories from the automation runtime; these are recorded separately from app compiler diagnostics. The output parser can double-count passing XCTest suite summaries; raw XCTest counts/xcresulttool are authoritative.

## Focused follow-up on 2026-11-12

The user authorized an uninterrupted targeted UI interval. No full-suite rerun was performed. The outstanding functional cases were checked individually or in explicitly filtered serial batches:

- `braindump-ui-tests.F0V6PY`: New Project light noncontrast audit passed.
- `braindump-ui-tests.lqS2Ni`: five audits passed (New Project dark, Settings light/dark, Help dark, folder/removal decisions). The unavailable-project case stopped in obsolete window-isolation setup, not an audit finding.
- `braindump-ui-tests.A2YwvT`: nine functional cases passed, including close/read-only/failure recovery, external file changes, grouping, first creation, nested repair, cancelled folder decisions, failed folder-save retry, partial batch success, and unavailable rename/removal. Four cases needed follow-up.
- `braindump-ui-tests.f3McmB`: duplicate-folder validation and mixed Keep Open passed. The validation helper now waits for the rejection message instead of expecting a rejected folder to become selected. Keep Open's preceding event-synthesis timeout was an XCTest failure, not evidence of an app save failure.
- `braindump-ui-tests.LcgWO9`: unavailable/invalid Settings accessibility and New Project origin/draft preservation passed after the persistent-label and native-visibility repairs.
- `braindump-ui-tests.fuU1sJ`: all three final native-visibility regressions passed: first creation/New Project close and reopen, Open Project double-click/checkbox memory, and Settings immediate row commit/Cancel/reopen.

All 46 current test methods have passing recorded results across the baseline and focused repair runs. This is cumulative evidence, not a claim that the entire final suite passed in one run. Twenty-one distinct methods were exercised in this approved follow-up interval; successful unrelated cases were not repeated. The test app was terminated by teardown; interactive testing has ended.

Window raising uses public app commands for singleton forms and the native Window menu for editors. Scenario setup uses native Paste with conditional clipboard restoration; the dedicated direct-typing/Undo regression retains actual keystrokes. These changes avoid overlap/keystroke-driver failures without bypassing production workflows.

The invalid-name audit asserts the empty field's accessible name and disabled OK, then uses Tab to finish native field editing before auditing the validation state. A parent/child mismatch occurred while the native field editor was active; it had no associated element, and the screenshot showed an additional focused-text overlay. No noncontrast audit category or finding is suppressed. Passing validation-state coverage does not establish that the live field-editor/overlay mismatch is fixed.

The historical demonstration-only delayed accept/reject controls are gone; production save gates/failures exercise native close/quit. Raw logs/results remain outside Git. The final close/reopen outcomes are recorded above. Final Release build passed with zero compiler warnings/errors (`braindump-verification.IQujhl`); shell syntax, scheme XML, plan JSON, and tracked/new-file whitespace checks passed. No generated binaries, raw logs, or user preferences were added to Git.

## Contrast decision

The user explicitly requested skipping all contrast checks and investigating only internal issues/bugs. The earlier native-panel reference and crop investigation is closed. Contrast findings are excluded from current acceptance, not passed; there are no remaining contrast blockers. The temporary reference test and contrast-specific audit machinery are removed. No system display or VoiceOver settings were changed.
