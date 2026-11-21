# Checkpoint 2 — Registry and Folder Access

Status: complete. The user reports all manual sandboxed folder-access checks passed, including relaunch, external rename rejection, and explicit repair. No agent-driven UI was launched or controlled for this checkpoint.

Checkpoint 1 was committed as `3fd189c`, including the user's passing manual native checks and walkthrough A. Checkpoint 2 was committed as `96d6f20` after the user's manual verification passed.

## Resolved behavior

The user selected option 2 for external project-folder moves: preserve the registered path, mark the project unavailable, and require explicit repair through Change Folder. A bookmark resolving elsewhere must not silently update the path. A replacement directory at the old path does not become the original project. This rule is recorded in Project and Capture Rules and Decisions.

## Implemented

- Shared `BrainDumpCore` sources compile into both the app and a hostless Swift Testing target. No extra framework, package, or copied implementation is needed.
- Sendable project/folder records use stable registry handles while physical folder identity defines duplicate detection. Volume UUID plus inode is preferred so remount device-number changes do not change identity; device/inode is the fallback where no volume UUID exists.
- Main-actor observable ProjectStore implements a complete UserDefaults registry snapshot, trimmed/case-insensitively unique names, unique folders, MRU capped at ten, separate last active, the initially OFF window preference, explicit rename/repair/removal, and availability with actionable explanations.
- Registry revalidation never changes usage order. Unavailable entries remain registered but are omitted from reachable/recent selector data. Removal clears a matching last-active reference without selecting a replacement. Corrupt persisted data produces an error rather than being overwritten.
- Post-await validation and cancellation checks prevent stale or cancelled registrations/path changes from committing. Stale failures do not invalidate an explicitly repaired record.
- Off-main FolderAuthorizationService creates/resolves/refreshed security-scoped bookmarks and manages explicit leases plus scoped async operations. Registry edits/removal do not revoke a lease still owned by a capture/operation.
- Bookmark resolution rejects moved/replaced folders. Real symlink selection is canonicalized while authorization is active before creating bookmark data.
- One ProjectListBuilder provides localized sorting, deterministic ties, grouping above fifteen, groups aiming at ten without splitting an initial, Unicode-script boundaries, meaningful labels, and the agreed orphan/fallback behavior.
- A tracked shared `BrainDumpTests` scheme and `BrainDumpTests.xctestplan` run the actual shared core sources with no app host. App and test targets use Swift 6 and complete concurrency checking, MainActor default isolation, approachable concurrency, and a macOS 15 minimum.
- The New Project demonstration panel has a temporary folder-authorization probe. It persists verification authorization separately from production projects and can write/read/remove its own uniquely named temporary check file. It does not register projects or create captures. Production forms and editor integration remain later checkpoints.

## Noninteractive verification — passed

- Final Debug app build passed through `xcodebuild`, with raw output retained and condensed by local xcsift.
- All 21 Swift Testing functions passed: 24 cases including the four-argument list-threshold test. No failures or skips; no app host or UI automation was used.
- Tests cover persistence/defaults, corrupt-data preservation, names and physical folder duplicates, MRU/focus/removal, unavailable-folder repair, existing lease independence, localized grouping, symlink/case identity, moved/replaced folders, volume remount identity, temporary read/write probe cleanup, concurrent registration validation, and cancellation before commit.
- Whitespace checks passed.
- Raw logs contain only the known App Intents metadata-extraction tooling warning; no Swift/concurrency diagnostics. xcsift omits that tooling warning, so its zero-warning summary is not treated as the complete warning record.
- This checkpoint's Release build and runtime on macOS 15 itself were not checked. Earlier checkpoint builds are not evidence for new code.

Evidence:

- App build log: `/private/tmp/braindump-checkpoint2-app-build.log`.
- Test log: `/private/tmp/braindump-checkpoint2-tests.log`.
- Result bundle: `<DerivedData>/BrainDump`.

The tests found two implementation problems during development: Foundation could not create bookmarks from some trailing-slash symlink URLs, and combining Data's atomic and no-overwrite options traps. Both were corrected and the final run passed. The temporary probe now uses exclusive creation; production capture atomic publication is still checkpoint 3 work.

## Tooling and capability limits

Xcode's AddEntitlement tool rejected `com.apple.security.files.bookmarks.app-scope` as unavailable, although [Apple documents it](https://developer.apple.com/documentation/professional-video-applications/enabling-security-scoped-bookmark-and-url-access). No entitlement file was manually created or patched. The subsequent user-led check passed persistent read/write access across relaunch in the sandboxed app with the existing capabilities. That runtime evidence resolves this checkpoint's access gate; no extra entitlement was added solely to satisfy a tooling discrepancy.

Xcode MCP temporarily stopped resolving schemes after project-structure changes, while `xcodebuild -list` recognized the project and schemes. Command-line builds/tests were used as the fallback. Xcode's result reader required normal developer-service permissions to update its result-bundle index. No UI permissions or automation were used to work around these tooling limits.

## Reproduce headless tests

From the repository root, use the retained-log/pipefail workflow in AI-Testing-Workflow with:

```sh
xcodebuild test -project BrainDump.xcodeproj -scheme BrainDumpTests -testPlan BrainDumpTests -configuration Debug -destination 'platform=macOS,arch=arm64'
```

The test target's TEST_HOST and BUNDLE_LOADER are empty. It does not launch BrainDump. The auto-generated empty template test was removed rather than reported as test coverage.

## Manual sandboxed check — passed by the user

The user reported “All clear” after the following list. These are user-reported manual results, not an automated UI test result.

The user operates these controls when convenient; do not launch or automate the app without advance approval.

1. Launch the newly built Debug app. In New Project, choose a disposable folder using Choose verification folder.
2. Press Verify saved read/write access. Expect success stating that the temporary check file was removed.
3. Quit and relaunch. Without selecting the folder again, verify saved access. Expect the same success.
4. Rename or move that folder in Finder. Verify again. Expect an unavailable explanation and the unchanged saved path.
5. Choose the renamed/moved folder explicitly, verify success, then quit/relaunch and verify once more.

All five checks passed. Registry availability filtering is covered by service tests; the verification panel is intentionally not the production Settings UI.
