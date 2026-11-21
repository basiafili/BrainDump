# BrainDump

BrainDump is a small, keyboard- and VoiceOver-friendly macOS app for quickly capturing plain-text notes into Markdown files. Captures are grouped into user-selected project folders, saved locally, and remain ordinary files that can be read or edited with other tools.

This repository is the source for a personal tool. It is shared so that other people can study it, build it for themselves, and adapt it to their own workflows.

## Project status

BrainDump is not a distributed product. There are no promised public releases, packaged downloads, update feed, release schedule, compatibility guarantees, or end-user support. Development follows the needs of its primary user, so public consumers should expect to maintain their own fork and make any changes their workflow requires.

## Requirements

- macOS 15 or later
- Xcode with Swift 6 support

## Building

1. Clone the repository.
2. Open `BrainDump.xcodeproj` in Xcode.
3. If Xcode asks for signing configuration, choose your own development team or use local ad-hoc signing. No signing identity or Apple team is stored in this repository.
4. Select the `BrainDump` scheme and build.

The default bundle identifiers use the `org.example` namespace. Change them to identifiers you control before signing or distributing your own fork.

For command-line verification, the repository includes `scripts/verify.sh`. Its compact output uses a local `.bin/xcsift` executable when present; that optional binary is deliberately not committed. You can also run the shared Xcode schemes directly.

## Data and privacy

BrainDump stores project registrations and security-scoped folder bookmarks in the app's local preferences. Capture contents are written only to folders selected by the user. The app does not include an account system or a remote service.

Before publishing a fork, review your own Xcode signing settings, bundle identifiers, schemes, documentation, and Git history. Local build products, Xcode user data, result bundles, and `.DS_Store` files are ignored.

## Documentation and tests

The product behavior and architecture are documented in `BrainDump/Docs`. Hostless service tests live in `BrainDumpTests`; UI automation lives in `BrainDumpUITests` and launches and controls the app.

## Reuse

BrainDump is available under the MIT License. You may reuse and adapt it under the terms in `LICENSE`.
