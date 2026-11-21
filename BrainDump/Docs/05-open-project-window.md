# Open Project

## SwiftUI form

Controls: registered-project list showing name and path, New Project, “Open in new window” checkbox, Cancel, Open. Only reachable projects are selectable/displayed here; all registrations remain available in Project Settings.

Double-clicking an available project row selects and opens that project using the same validation, originating editor, and “Open in new window” choice as the Open button. Ignore repeated activation while an opening operation is in progress.

New Project may use `folder.badge.plus`. Open and Cancel need no icons.

## Behavior

- Remember this window’s last checkbox choice across closing/reopening and app launches, separately from both New Project and the global “Always Open in New Window” preference. Until it has its own remembered choice, initialize from the global preference. Cancel retains only this UI choice; it does not change the global preference or registry.
- Open requires a selected reachable project. Revalidate access before opening.
- Checked: open a new empty editor for the selected project.
- Unchecked: reuse the originating editor, otherwise the most recently active editor, otherwise create one. A non-empty editor must save successfully before it is reset and switched.
- Update MRU and last active only after success.
- Save failure preserves the existing editor and blocks the switch.
- Project access/selection errors stay visible and accessible inside this form where practical.
- Cancel has no effect on sessions, registry, or global preferences.

Opening a registered project does not browse or load its existing Markdown files. It starts a fresh capture.

## Unavailable-project recovery

When startup or New Capture cannot open the last-active project, show the persistent error here and place VoiceOver focus on the message. Do not open another project automatically. Include Project Settings so the user can explicitly reconnect the moved/renamed folder. After repair, remove the resolved error and make the repaired registration selectable; opening an editor remains an explicit action. With no last-active reference, startup still uses New Project.

Use a native checkbox with its label and checked state as one accessibility stop. Close this form after a successful open/switch; keep it open on failure.
