# Help Window

## Presentation

Title: BrainDump Help.

Use a SwiftUI window hosting a WKWebView bridge as needed. Load bundled local HTML only; no scripting or remote content dependency.

## Typography and accessibility

- Use the system font. Roboto is not required or bundled for Help.
- Use semantic headings, simple structure, readable contrast, and accessible links.
- Respect system text-size settings; use relative CSS sizing such as rem where appropriate, without fixed typography that defeats scaling.
- Test the reading order and headings with VoiceOver.
- Use action names as primary references; icons are supplementary.

## Required topics

- A project is a registered user-selected folder with a display name.
- Capture creation, UTC month folders, filename suffixes, and update behavior.
- Empty content does not create, erase, or delete files, including when a saved capture is cleared in the editor.
- File/folder names use Gregorian UTC timestamps and ASCII digits; window titles display the first-save time in the user's local time and locale.
- Close, New Capture, project switching, and quit save non-empty content; explain temporary read-only state and failure behavior.
- Folder changes keep bound files at their original locations; explain both unsaved-capture choices.
- Unavailable projects remain registered in Settings but do not appear in project selectors.
- External rename/deletion recreates the original bound path on save; external content edits produce a suffixed copy which becomes the session's new file.
- Removing a project unregisters it without deleting files.
