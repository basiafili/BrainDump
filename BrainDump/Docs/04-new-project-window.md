# New Project

## SwiftUI form

Controls: Project name, Choose Folder, selected path display, “Open in new window” checkbox, Cancel, Create. Choose Folder may use `folder`; Create and Cancel need no icons.

The selected folder itself is the project folder. Do not create an additional folder named after the project; the name is a display label.

## Validation

- Trim leading/trailing whitespace and newlines from the name; reject an empty name.
- Names must be unique case-insensitively among all registered projects, including unreachable entries.
- Require an accessible selected folder and valid persistent folder authorization.
- Reject a folder already registered through any equivalent path, including symlink aliases and filesystem case equivalence.
- Show persistent, accessible inline errors beside the relevant field/control; disable Create while invalid.

## Routing

Remember this window’s last “Open in new window” choice across closing/reopening and app launches, independently of the global preference. Until a window-specific choice exists, initialize from the global preference. Changing this checkbox remembers only the New Project window choice, including when the form is later cancelled. If unchecked, reuse the originating/most recently active editor according to the menu routing contract; if no editor exists, create one.

## Create transaction

Validate first. If reusing a non-empty editor, use the shared save-before-switch workflow. Create the current UTC month folder in the selected project folder, register the project with its display name/path/bookmark, and open it. Update MRU and last active only after successful create-and-open.

If any required step fails, leave the project unregistered, MRU and last active unchanged, and the current editor's text, binding, and project unchanged. Earlier successful capture writes are not rolled back. Show a persistent in-window error and allow retry. A filesystem folder already created need not be removed; never delete user files to roll back.

Cancel registers nothing and does not change any editor or the global preference. Only the window’s checkbox memory is retained.

After successful create-and-open, close this form. Stop validating its committed name before closing; it must not report its own newly registered project as a duplicate. A real validation/create failure keeps the form open.

Use a native checkbox with its label and checked state exposed as one accessibility stop.

## Startup fallback

With no last-active reference, startup opens this creation form. An unavailable last-active project instead opens Open Project with an accessible error and a Project Settings repair action. Never automatically open a different registry/MRU project.
