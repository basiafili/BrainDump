# BrainDump contributor instructions

Read the product specifications in `BrainDump/Docs/` before implementing behavior. Ask the user about ambiguous or missing product invariants rather than inventing behavior.

For build and test verification, follow `BrainDump/Docs/AI-Testing-Workflow.md`. Use Xcode MCP for compact build diagnostics and Xcode-specific operations; prefer the local `./.bin/xcsift` for routine command-line tests. Do not install Homebrew or global tooling. Keep generated binaries and raw logs out of Git.

For command-line verification, invoke `scripts/verify.sh` from the repository root with `build Debug`, `build Release`, `build-ui-tests` (compilation only), or `test` (optionally followed by a `BrainDumpTests/Suite/test` filter). Do not wrap it in a multiline shell command or combine unrelated commands into an approval request. The runner handles retained logs, xcsift, and failure status; it does not support UI tests or launching the app.

Before running UI tests, UI automation, or interactive app verification, stop and ask the user first. These actions interfere with their ongoing VoiceOver use. Give advance notice of the intended interactions and wait for approval; do not launch or manipulate the app as part of an unannounced check. Noninteractive builds and tests that do not launch/control UI may proceed.

For UI repairs, run only the specific XCTest UI cases needed to verify that repair. Use `scripts/ui-tests.sh` with an explicit `BrainDumpUITests/Class/test` filter; do not routinely rerun the whole suite. UI typing/pixel audits need a quiet desktop without concurrent keyboard input or app switching. Respect the user’s announced availability; new product questions can wait until they are available.
