# Accessibility

## General

Keyboard-first workflows, predictable focus, system semantic colors, system fonts, and understandable visible labels are required. Support light/dark appearance and system text-size settings where practical. Do not communicate information by color or icons alone.

## SwiftUI controls and focus

- Prefer native SwiftUI controls with their built-in semantics; AppKit bridges must preserve equivalent accessibility.
- Give every control a clear visible action/field label and matching accessible name.
- Maintain logical keyboard navigation and tab order.
- Focus editors after opening, New Capture, and switching; do not steal focus during unrelated saves.
- Toolbar actions retain visible text labels with supplementary SF Symbols.
- Form checkboxes place the checkbox before its label and expose label, action, and checked state as one VoiceOver stop.
- Do not add idle-time reminders, forced delayed help, or redundant hints to the editor. Thinking time must not trigger app announcements. Keep essential state available without repeatedly drawing attention to it.
- Native text editing must support VoiceOver, undo/redo, spellchecking, and system services.

## Project presentation

- Open Project’s native project-list scroll area is labelled “Available projects”.
- Settings and Open Project rows expose both name and path; Settings also exposes unavailable status and an explanation.
- Compact menu/switcher entries use the full unique display name.
- Group labels explain the contents: “Projects A–D”, “Projects starting with A”, “Other projects…”. Do not use unexplained bare ranges.
- Unavailable registrations are omitted from project selectors but remain discoverable and repairable in Settings.

## Validation and feedback

- Inline errors remain available until resolved and are associated with their controls. Focus actionable operation/folder-selection errors accessibly. Do not announce a successfully committed name as a duplicate while closing its form.
- An unavailable last-active project is explained in Open Project, without a separate routine alert. Place VoiceOver focus on the error and provide Project Settings for repair.
- Saving/busy state and save outcomes must be perceivable without vision; use announcements or equivalent where appropriate.
- When a workflow temporarily makes an editor read-only, expose why and restore editability on failure.
- Save failure preserves content and provides a clear retry path.
- Reserve modal interruption for the agreed critical errors and explicit decisions.

## Windows and dates

No tabs or hidden window-restoration behavior. Titles identify project and capture state. UI dates use the user's locale and local time zone; avoid technical filename strings as date labels.

## Help

Semantic HTML headings, logical reading order, system font, relative sizing, and local content. Do not require icon recognition to follow instructions.

## Initial language scope

English is the supported language for this implementation. Keep localization-ready strings, but do not require additional translations for acceptance.

## Contrast audit scope

Per the user's checkpoint 8 decision, omit contrast checks from UI acceptance. Continue element detection, hit region, description, action, and parent/child audits, and investigate application defects they expose. This exclusion does not establish contrast compliance. Do not change system display or VoiceOver settings for these tests.
