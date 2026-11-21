# AI Build and Testing Workflow

## Goal

Keep diagnostics useful while avoiding verbose logs in the agent's context. This workflow does not replace product requirements or justify skipping required tests. Token savings depend on actual output; no fixed reduction relative to Xcode MCP is assumed.

## Choose the appropriate route

For BrainDump, use the tracked `scripts/verify.sh` runner for command-line verification. Invoke it from the repository root:

```sh
scripts/verify.sh build Debug
scripts/verify.sh build Release
scripts/verify.sh test
scripts/verify.sh test BrainDumpTests/CaptureNamingTests
```

The runner accepts only the fixed app build, UI-test compilation (`build-ui-tests`), or hostless service-test routes, validates its arguments, saves a unique raw log, and preserves a failing pipeline status. It never launches BrainDump or UI automation. Request a narrow reusable prefix for this runner rather than a broad shell/interpreter approval. More restrictive managed policies can still require approval. The generic pipeline examples below remain useful for adapting the workflow to other projects.

- Prefer Xcode MCP for ordinary builds, focused compiler diagnostics, and Xcode-specific operations. Its build response already summarizes results and points to a full log.
- Prefer command-line tests through the local `./.bin/xcsift` in TOON format for routine test verification, particularly larger suites.
- MCP targeted test runs are also appropriate when they simplify discovery or troubleshooting. Do not rerun a successful check through a second route merely to compare output.
- Use the smallest meaningful test scope during iteration and complete the required broader checks before delivery. Do not add tests that merely mirror implementation.
- Inspect condensed results first. If results are incomplete, missing, contradictory, or insufficient, inspect the relevant portion of the saved raw log or result bundle. Do not assume success from empty output or an absence of parsed failures.

## Local setup

Run commands from the repository root. Use `./.bin/xcsift`, not an assumed global installation; do not install Homebrew.

1. If a working local binary exists, check `./.bin/xcsift --version` and `--help` before choosing version-specific options.
2. Otherwise, reuse a compatible trusted binary from another local project when available. Copy it into this project's `.bin/`; do not modify the source project's installation or use a fragile cross-project symlink.
3. If none is available, obtain a compatible macOS binary from the official `ldomaradzki/xcsift` GitHub releases, following applicable download permissions. Pin/record the version used and verify the published checksum when available; do not automatically upgrade a working installation.
4. Ignore `/.bin/` in Git. Keep instructions tracked, not downloaded executables.

BrainDump currently uses xcsift 1.3.1, copied from Explorium's local installation. Re-check capabilities if replacing the binary.

## Running tests safely

Use `2>&1` so the parser sees stderr, `set -o pipefail` so failures in the producer or pipeline are preserved, and `--exit-on-failure` so recognized test/build failures also produce a nonzero parser exit code. The installed version supports these flags.

Retain raw output outside the repository using a unique temporary file. `tee` saves the raw output without sending it directly to the agent; only the condensed output should normally be read.

### Swift package

Use only when the repository actually has a Swift package to test:

```sh
set -o pipefail
test_log=$(mktemp "${TMPDIR:-/tmp}/swift-tests.XXXXXX")
swift test 2>&1 | tee "$test_log" | ./.bin/xcsift -f toon --exit-on-failure
test_status=$?
printf '\nRaw log: %s\n' "$test_log"
(exit "$test_status")
```

### Xcode macOS project

Replace `YourScheme` with the actual shared scheme and select the appropriate destination for the project. Use the same scheme, destination, and test plan when comparing runs.

```sh
set -o pipefail
test_log=$(mktemp "${TMPDIR:-/tmp}/xcode-tests.XXXXXX")
xcodebuild test -scheme 'YourScheme' -destination 'platform=macOS' 2>&1 | tee "$test_log" | ./.bin/xcsift -f toon --exit-on-failure
test_status=$?
printf '\nRaw log: %s\n' "$test_log"
(exit "$test_status")
```

Run these blocks in bash or zsh. The final subshell returns the captured pipeline status without terminating an interactive shell. If adapting them into a standalone script, return/exit with that same status; do not let a later successful command mask it. If using `set -e`, explicitly handle the failing pipeline so status reporting still runs.

For shell builds when MCP is unsuitable, use the same pipeline with `xcodebuild build` or `swift build`. Add `-w` when warning details are needed; avoid verbose timing, coverage details, or complete passing-test listings unless the task needs them.

## Reporting and troubleshooting

For BrainDump's hostless service tests, use scheme `BrainDumpTests` and test plan `BrainDumpTests`: `xcodebuild test -project BrainDump.xcodeproj -scheme BrainDumpTests -testPlan BrainDumpTests -configuration Debug -destination 'platform=macOS,arch=arm64'`, wrapped in the retained-log pipeline above. This target does not launch the app. Use scheme `BrainDump` for ordinary app builds.

- Report the actual scope, outcome, and any skipped/unavailable checks. A build is not a test run.
- Keep failed raw logs available long enough to investigate. Search/read only relevant sections before requesting complete logs or rerunning.
- Parsing can omit unfamiliar diagnostics. Use the producer's exit status and expected test counts as well as the condensed summary.
- Do not run real builds/tests merely to verify a documentation edit or the output parser installation; a small parser smoke check is sufficient for that setup.
- No additional MCP proxy, plugin installation, background service, or global configuration change is required.

## XCTest UI automation (checkpoint 8)

The separate shared `BrainDumpUITests` scheme and English UI test plan use XCTest/XCUIAutomation. They are not part of the ordinary app or hostless test scheme. Compile without launching anything:

```sh
scripts/verify.sh build-ui-tests
```

After explicit advance approval for an interactive verification session, run:

```sh
scripts/ui-tests.sh BrainDumpUITests/CaptureUITests/testDirectTypingPreservesWordsMarkdownAndUndoRedo
scripts/ui-tests.sh BrainDumpUITests/AccessibilityUITests
```

This runner opens windows, types, uses native folder panels, closes/quits/relaunches BrainDump, and tests Reveal through Finder. It interferes with VoiceOver. A saved shell approval does not replace asking whether an interactive session is convenient. Do not substitute computer use for this suite.

Each test uses a fresh UUID preference suite and runner-owned temporary fixture directory authorized through the native folder panel. Debug-only launch configuration seeds real registrations where needed; tested interactions use the actual views, native folder picker, coordinator, bookmarks, and writer. Release builds omit the configuration. A bounded writer file gate makes snapshot/busy checks deterministic; it does not replace the writer. Teardown terminates the test app and removes only that UUID's data. Failures before fixture readiness can leave a UUID directory for investigation; never clear the user's normal defaults or registrations to repair a test.

The UI target retains Swift 6, complete concurrency checking, and MainActor default isolation. XCTest subclasses are explicitly nonisolated because XCTest's inherited initializers are nonisolated; UI test methods run on MainActor. Tests run serially with condition-based waits. Accessibility tests use `performAccessibilityAudit(for: .all.subtracting(.contrast))` with diagnostic issue recording for every app window in light/dark appearance, plus invalid/unavailable forms and decision dialogs. macOS supports contrast, element detection, hit regions, descriptions, actions, and parent/child audits; iOS-only dynamic-type/clipping/trait audit categories are not exposed by this SDK on macOS. Audits do not establish the full VoiceOver reading experience or announcement/focus timing.

Run only the case(s) needed for each repair. The UI runner requires explicit filters and rejects an unfiltered invocation. Multiple named filters may share one serial run to avoid repeated build/startup overhead. Do not repeat the whole suite as routine verification. UI typing and pixel audits need a quiet desktop without concurrent typing/app switching; overlapping use invalidates those results. Record the end of the UI interval so the user knows they can resume.

For obscured windows, use the native Window menu (editors) or the existing public app command (singleton forms), not a titlebar coordinate covered by another window. Scenario setup may use native Paste while restoring the clipboard if unchanged; retain a separate direct-keystroke regression. Validation-state audits assert the empty field's accessible label, then Tab out of native editing before auditing the resulting form. This avoids the observed live field-editor/overlay parent-child mismatch without excluding any noncontrast audit category; do not describe that as a fix to the native editing overlay.

Contrast checks are omitted by the user's checkpoint 8 decision. All other supported audit categories remain active, including Help's full accessibility hierarchy. Do not investigate contrast crops or change system display/VoiceOver settings to satisfy them. This exclusion is not a claim of contrast compliance.
