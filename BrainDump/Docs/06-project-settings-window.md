# Project Settings

## SwiftUI form

Controls: project list, editable name, path display, Change Folder, Reveal in Finder, Remove Project, Cancel, OK.

Include all registered projects, including unreachable ones. Show name, path, and a persistent, accessible explanation for unavailable folders. Unreachable projects remain renameable, removable, and repairable by choosing a reachable folder.

Optional symbols: Change Folder `folder`, Reveal in Finder `magnifyingglass`, Remove Project `trash`. Keep visible action labels.

## Draft edits

Each project retains its own draft. Typing in the name field does not rename sessions. When selecting another row, validate the row being left: commit valid name/folder changes immediately as one project transaction, then retain the new row selection. Keep invalid drafts, move to the requested row, show their problems in the list, and disable OK while any input draft is invalid. Revalidate retained drafts against later commits from other rows.

If leaving a valid row requires the folder-change decision, Cancel moves to the requested row while preserving the original row's uncommitted name/folder draft. A failed required save also retains the draft and all affected windows; earlier successful row commits remain applied. The user can correct/retry remaining changes.

OK applies every remaining valid draft, including earlier cancelled folder-change drafts, with a decision for each project that needs one. Complete each project's name/folder transaction atomically; do not partially apply a name when its folder cannot commit. A failure keeps Settings open; earlier independent successful project commits and their completed editor closes are not rolled back. A cancelled folder decision keeps that draft and Settings open.

Cancel or closing Settings discards only unapplied drafts, not earlier row commits. A committed name updates all corresponding editor titles immediately. Explain this behavior visibly without idle hints or routine success alerts.

Validate trimmed, non-empty, case-insensitively unique names and unique resolved folders using the same rules as New Project. Exclude the selected project itself from duplicate checks. A replacement folder needs persistent sandbox authorization. Inline errors persist until resolved and prevent an invalid commit.

## Folder changes

Seed the selected registration once when Settings opens. Returning from the folder picker must not reset it to the last-active project. Bind each pending picker result and submitted change to that registration's stable ID; reject stale picker results rather than attach a folder to another selection. Capture the target before an unsaved-capture confirmation and retain it through completion.

Show explicit Project, Registered folder, and Selected folder labels. VoiceOver row activation selects that registration; Change Folder's accessible label identifies it. A duplicate-folder error names the conflicting registration and its registered path. Exclude the target registration itself, so reconnecting its renamed folder is valid even when parent/child folders are also registered.

Changing the folder changes project registration, not existing capture files. Keep MRU, last active, and session project references consistent with the committed path change.

Unsaved captures include both non-empty unbound captures and edits to bound captures, including an edit that clears a bound capture to whitespace.

If no unsaved captures exist, commit without an unsaved-content decision. Existing bound captures keep their original file URLs and required folder access.

If unsaved captures exist, offer:

1. **Keep captures open:** commit the new project folder and leave sessions open. Bound captures retain their original file URLs; unbound captures and future new captures use the new folder.
2. **Save and close captures:** save the project's captures to their old destinations using the common policy, then close all its editors and commit the folder change.
3. **Cancel:** leave registration and editor state unchanged; retain form drafts for further editing.

Do not move or rename existing files. Save-before-close uses read-only affected editors. Any required save failure leaves every affected window open and the old registration intact; successful earlier writes remain on disk. Empty saves remain no-ops.

## Reveal in Finder

Reveal the committed registered folder, not a pending folder draft, using validated scoped access. Do not apply metadata or change usage as a side effect. Disable Reveal for an unavailable registration and retain its visible explanation; repair, rename, and removal remain available. The actual Finder action is user-invoked and is not part of unannounced automated verification.

## Removal

Remove Project is a separate confirmed action, not an uncommitted name/folder edit. Do not apply form drafts as a side effect of removal.

After confirmation:

1. Save all non-empty sessions belonging to the registered project using the common save policy.
2. Only after every required save succeeds, close those editors and unregister the project.
3. Remove its MRU reference and clear last active if it refers to that project; do not select a replacement automatically.

Cancel confirmation changes nothing. Save failure leaves registration and all its windows intact. Never delete project folders or capture files.
