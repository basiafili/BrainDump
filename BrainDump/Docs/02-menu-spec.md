# Menu

## Command ownership and routing

Define menus with SwiftUI commands. Menu and toolbar actions invoke the same coordinator operations and share enabled state. Native editing actions target the focused text control, including form fields.

For project-opening commands that reuse a window, target the active editor, or the most recently active editor if an auxiliary window is active. If no editor exists, create one. Do not retarget an operation midway through a dialog: retain its originating editor while it exists, with the same fallback if it has closed.

Project menu and Open Recent requests snapshot the global window preference when selected. Open Project → New Project retains the first form’s originating editor while it exists. Menu/switcher entries use the same shared project-list structure.

## App

Standard About, Services, Hide/Show, and Quit. Quit uses the coordinator's save-before-quit contract; native termination must wait for its outcome.

## File

- New Capture — Command-N.
- New Project — Command-Shift-N.
- Open Project — Command-O.
- Open Recent submenu.
- Separator.
- Close — Command-W. Close the key native window through performClose; editors use the save-before-close coordinator path, and auxiliary windows close only themselves. Never apply the active/most-recent editor fallback to Close.
- Save — Command-S.
- Separator.
- Project Settings.

New Capture acts on the active or most recently active editor. With none, use the last active reachable project; if no reference exists open New Project, and if the referenced project is unavailable open Open Project with the focused error and Settings repair action. Save requires a target editor and follows the common save policy.

### Open Recent

- Projects only; stored MRU contains at most 10 entries.
- Show reachable entries in their existing MRU order; never replace missing entries with unrelated projects.
- Include Clear Menu; it clears only MRU.
- Selecting a project opens a new editor when “Always Open in New Window” is enabled. Otherwise save and reuse the target editor; create one if none exists.
- Save failure prevents reuse and preserves the current editor.

## Edit

Standard system editing items, undo/redo, spellchecking, and text services as applicable. No Find, Replace, or app search command. Do not introduce a custom editing engine. Use native responder validation, including for form fields. Do not add the default TextEditingCommands group wholesale, because it includes Find. Preserve its applicable spelling/substitution/transformation/speech actions through explicit native responder actions.

## Projects

- Reachable project entries using the shared sorting/grouping structure in Architecture.
- Separator.
- “Always Open in New Window” global toggle, persisted between launches. Default to OFF when no saved preference exists; otherwise honor the saved value.

Project entries show full project names only. Group labels use meaningful wording such as “Projects A–D”, “Projects starting with A”, and “Other projects…”. Selecting a project follows the same global-preference routing as Open Recent.

## Window

Standard applicable window actions. No tabs or tabbing commands.

## Help

BrainDump Help opens local HTML Help.

## Icons and toolbar relationship

Menus need no icons. Auxiliary/context menus that use icons must use the shared SF Symbols where applicable. Toolbar actions mirror these commands; view code must not duplicate workflow logic.

Suppress implicit singleton-scene menu shortcuts that bypass originating-editor and draft initialization. Keep the native list of already-open windows and applicable standard window actions. A project-menu access failure with no editor is shown inline in Open Project with the correct failed registration available to its Settings repair action.

Replacing the saveItem command group also removes the system Close command, so explicitly restore Close and Command-W in that replacement. Do not declare an empty textFormatting replacement merely to suppress formatting: it can leave an empty Format menu shell.
