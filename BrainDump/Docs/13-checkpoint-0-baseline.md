# Checkpoint 0 — Project and Toolchain Baseline

Status: complete, 2026-11-11. Checkpoint 1 has not started. No application behavior was implemented in this checkpoint.

## Discovery

- Project: `BrainDump.xcodeproj`, using Xcode's `project.xcproj` format.
- App target: `BrainDump`; application product, supports hosting tests.
- Scheme: `BrainDump`, reported shared by Xcode; successfully usable from the command line.
- Active test plan: `BrainDump`.
- Test targets: none. The test plan's existence does not mean tests exist or have run.
- Destination: My Mac, arm64. No simulator is required.
- Xcode: 27.2, build 27B52.
- Compiler: Apple Swift 6.4.2, swiftlang-6.4.2.1.9.

## Changes

Used Xcode MCP's target build-setting API to set the app target's unconditional settings:

- `SWIFT_VERSION = 6.0`.
- `SWIFT_STRICT_CONCURRENCY = complete`.

These settings apply to Debug and Release. No Swift source changes, unsafe Sendable annotations, suppressed concurrency diagnostics, or compatibility workarounds were necessary.

## Effective settings and compiler evidence

Xcode MCP's resolved settings confirm:

| Setting | Effective value |
| --- | --- |
| Swift language mode | 6.0 |
| Strict concurrency | complete |
| Default actor isolation | MainActor |
| Approachable concurrency | YES |
| Member import visibility | YES |
| macOS deployment target | 15.0 |
| App Sandbox | YES |
| User-selected files | readwrite |

The pre-existing main-actor default and approachable concurrency settings were retained. In Swift 6, full concurrency enforcement is part of the language mode; it need not appear as a separate `-strict-concurrency` compiler argument.

Actual Debug and Release compiler invocations include `-swift-version 6`, `-default-isolation=MainActor`, and `-target arm64-apple-macos15.0`. They explicitly enable `MemberImportVisibility`, `InferIsolatedConformances`, and `NonisolatedNonsendingByDefault`.

The resolved Swift-6 feature defaults also enable concise magic file, deprecate application main, disable outward actor isolation, dynamic actor isolation, forward trailing closures, global-actor isolated types usability, global concurrency, implicit open existentials, Objective-C forward declaration imports, Sendable inference from captures, isolated default values, nonfrozen enum exhaustivity, and region-based isolation. ExistentialAny and InternalImportsByDefault are not enabled. No additional feature overrides were added.

The project's inherited deployment setting differs, but the app target resolves to 15.0 and both configurations actually compile for macOS 15.0. A newer build SDK does not raise the app's effective minimum. Running on macOS 15 itself remains a later compatibility check, not something established by these builds.

Because nonisolated async work may retain caller isolation with the retained approachable settings, later filesystem services must use an explicit off-main boundary such as their own actor. Adding `async` to a main-actor operation is not sufficient.

## Build verification

| Check | Outcome |
| --- | --- |
| Debug build through Xcode MCP BuildProject | Passed |
| Release build through xcodebuild and local xcsift 1.3.1 | Passed |
| Swift/compiler/concurrency diagnostics in raw logs | None |
| Whitespace check | Passed |
| Tests | Not run: no test target exists |

Raw logs from this session:

- Debug: `/var/folders/3n/x7yqq1590278p0q4yf543jhh0000gn/T/ActionArtifacts/default/BuildProject/BuildProject-Log-20261111-133008.txt`.
- Release: `/private/tmp/braindump-checkpoint0-release.log`.

Both raw logs contain the Xcode tooling warning `Metadata extraction skipped, no AppIntents.framework dependency found`. The app does not currently use App Intents; no dependency was added merely to silence the metadata processor. xcsift's summary reported zero warnings, so the raw-log review is the authoritative warning record.

The first command-line Release attempt could not write DerivedData under the execution sandbox. Retrying with normal developer-service access succeeded. This was an execution-permission issue, not a source/build-setting failure.

## Sandbox and bookmark readiness

Generated Debug and Release signing entitlements include App Sandbox and user-selected read/write access. They also retain the existing network-client entitlement; this checkpoint did not change unrelated capabilities.

Persistent project-folder access is not yet implemented. At checkpoint 2, implement app-scoped security-scoped folder bookmarks, verify/add the required bookmark entitlement through Xcode's capability/entitlement tools, balance access lifetimes, and test access after a sandboxed relaunch. Confirm continued authorization for old bound-file folders after changing project registration. Do not treat the existing picker read/write entitlement as proof of persistent bookmark access.

## Test infrastructure to add

At checkpoint 2, before implementing registry behavior, add a `BrainDumpTests` unit-test target to the existing project/scheme and active test plan. Use Swift Testing for service/coordinator behavior, including deterministic async fakes and temporary filesystem fixtures. Set Swift 6 language mode and complete concurrency checking on that new target, confirm effective isolation settings, and choose a host arrangement that avoids launching production startup workflows during service tests. Do not add a Swift package or an empty test suite merely to claim a test pass at this checkpoint.

Native lifecycle checks begin at checkpoint 1. Add focused UI automation only where it validates behavior that service tests cannot establish.

## Reproducible commands

Run from the repository root. Ordinary Debug builds may use Xcode MCP BuildProject with the BrainDump workspace active. To reproduce either configuration explicitly, replace `Debug` with `Release` as needed:

```sh
set -o pipefail
build_log=$(mktemp "${TMPDIR:-/tmp}/braindump-build.XXXXXX")
xcodebuild build -project BrainDump.xcodeproj -scheme BrainDump -configuration Debug -destination 'platform=macOS,arch=arm64' 2>&1 | tee "$build_log" | ./.bin/xcsift -f toon -w --exit-on-failure
build_status=$?
printf '\nRaw log: %s\n' "$build_log"
(exit "$build_status")
```

After the test target has been added to the plan, use the same retained-log pipeline with:

```sh
xcodebuild test -project BrainDump.xcodeproj -scheme BrainDump -testPlan BrainDump -configuration Debug -destination 'platform=macOS,arch=arm64'
```

The test command is planned, not yet validated. Do not report the current empty test plan as a successful test suite. On another Mac, select its appropriate native architecture/destination.
