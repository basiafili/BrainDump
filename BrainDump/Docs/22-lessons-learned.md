# What we learned building BrainDump

*Retrospective, 12 November 2026*

These are my observations from the project, including things I should have handled better. This is a retrospective, not a new product specification. The specifications and recorded decisions remain the behavior contract.

## 1. A quiet app requires deliberate design

The clearest product lesson came from the idle hint. A pause in typing is not evidence that someone needs help. They may be thinking. An announcement that seems harmless to its author can interrupt concentration and impose a real cost on the person using the app.

That decision clarified much more than one hint: BrainDump should make its state available without continually demanding attention. Persistent, actionable information is often better than an alert. An unavailable project belongs in the opening workflow, with a route to repair it; it does not need a succession of interruptions.

“Capture first” also gave us a useful boundary. Project registration is not a file browser. Saving is not organizing. Removing a registration is not deleting content. Keeping those distinctions prevented a small tool from acquiring responsibilities the user had never asked for.

## 2. Precise examples reveal requirements better than broad agreement

“Preserve the behavior” was a starting point, but it could not settle the difficult cases. Concrete examples did:

- An externally renamed capture must be recreated at its original bound path. We do not follow the renamed file.
- An externally edited capture must be preserved, with the editor saving a separate copy and then binding to that copy.
- Clearing a previously saved editor must not erase its file. Empty Save remains a no-op.
- An unavailable last-active project must not cause us to guess another project from the recent list.

The filename conversation was a particularly useful correction. I initially misunderstood what “use the original name” meant. The example involving an existing editor session and a Finder rename made the contract unambiguous.

Asking one question at a time helped, especially for Settings transactions. The important questions were about observable outcomes: what remains saved, which draft survives, which window stays open, and what Cancel actually cancels. Those answers were more useful than agreeing on an abstract implementation pattern.

A related documentation lesson: when a later decision supersedes an earlier rule, update the earlier summary too. Appending a new section alone leaves future readers to resolve contradictions. The Settings decisions evolved enough to make this risk concrete.

## 3. Accessibility feedback exposed product defects, not just missing labels

Your VoiceOver observations changed the application's behavior and structure. They exposed awkward focus placement, a checkbox that should be one stop, inaccessible toolbar overflow at the default size, a redundant announcement, and an error that needed an actionable recovery route.

These were questions about whether the workflow made sense. Treating accessibility as a final pass over labels would have missed much of that work.

Labels also need testing in the states where their content disappears. The Settings project-name field looked adequately described while it contained a name, but its empty state exposed a missing accessible description. A persistent label was the proper repair.

I should also have respected the context more carefully during diagnosis. Asking a blind user to identify visual magnification features was not a useful question. I could inspect the available evidence myself. A screenshot can help explain what a test captured; it should not become a demand that the user interpret the display for me.

## 4. SwiftUI works well when we respect the native lifecycle

SwiftUI remained the foundation: scenes, views, commands, forms, and observable state. Small AppKit bridges were useful where the actual macOS behavior needed more control, including the editor's undo manager, window lifecycle, the project menu, and the enclosing project-list scroll area's accessibility label.

The useful criterion was whether a bridge restored a specific native behavior. Framework purity would not have helped the user, but neither would replacing the application with a broad custom AppKit layer.

The most instructive lifecycle bug appeared late: a SwiftUI view disappearing is not the same event as its window closing. Clearing visibility in `onDisappear` allowed an existing New Project window to be treated as a new request. Raising it could replace the draft and lose its originating editor. Native window closure was the appropriate event for clearing that flag.

The broader lesson is to distinguish the identity of a view, a window, a capture session, and a project. They have different lifetimes. A callback from one lifetime must not silently reset another.

## 5. Concurrency correctness starts with ownership and user-visible guarantees

Using Swift 6 from the beginning made concurrency checking part of the implementation rather than a migration deferred until the end. Main-actor UI ownership and a separate writer made the boundaries explicit.

The compiler could not decide the important product guarantees for us, though. We still needed to define what happens when a save overlaps newer typing, when a transition fails, and when several projects are being applied in sequence.

Manual Save takes a snapshot while allowing later typing to continue. A save-before-close or switch temporarily makes affected editors read-only. A successful write remains a successful write even if a later operation fails; we must not pretend that an irreversible filesystem action was rolled back.

Settings made transaction scope especially important. A project's name and folder change must succeed together. But earlier successful project changes remain applied when a later project fails. Those are different boundaries, and tests need to preserve the distinction.

## 6. Filesystem identity and user intent must both be respected

Paths, display names, physical folder identity, and security-scoped bookmarks are related, but they are not interchangeable.

We needed physical identity to reject duplicate registrations, including alternate paths to the same folder. We needed explicit user intent to decide whether a moved folder should become a repaired registration. A bookmark being able to resolve a moved folder did not authorize the app to silently update the registered path.

Likewise, an editor's existing file binding survives a project-folder change. “Keep captures open” changes the destination of unbound and future captures; it does not move already-bound files.

File coordination and atomic publication gave us useful protections, but not an honest basis for promising absolute protection against every simultaneous external writer. Recording that platform limit was better than either overstating safety or giving up on conflict handling.

## 7. UI automation has a cost that belongs in the test plan

XCTest uses the person's desktop. In this project that meant taking over focus, opening dialogs, typing, and interfering with VoiceOver. Permission to run a shell command was not a substitute for agreeing on an interactive testing interval.

I ran broad suites too often before narrowing the process. That was disruptive, and it produced long lists of failures before the shared test helpers were reliable enough to make those lists useful.

The better sequence was to inspect retained evidence, repair the specific problem, and run only the affected cases. An uninterrupted interval then allowed the remaining cases to be resolved without asking you to repeat the entire manual walkthrough.

The first things to stabilize next time are fixture authorization, text entry, window raising, menu queries, failure diagnostics, and teardown. Every test depends on those helpers; uncertainty there multiplies across the suite.

## 8. A failed test is a finding to investigate, not an immediate app diagnosis

We saw failures caused by real app bugs, incorrect assertions, obscured windows, text-entry problems, and XCTest event-synthesis timeouts.

For example, the duplicate-folder test waited for a selected path after the application had correctly rejected that folder. The app was right; the assertion was wrong. A titlebar coordinate could also hit an overlapping editor instead of raising the requested form. Public app commands and the native Window menu were more reliable ways to select the intended window.

Using native Paste for scenario setup reduced dependence on long synthesized typing sequences. A separate direct-typing test still exercised actual keystrokes, deletion, Undo, and Redo. That preserved meaningful coverage without making every scenario repeat the same fragile input mechanism.

Evidence also has layers. A successful build is not a successful UI test. An accessibility audit is not a complete VoiceOver walkthrough. A condensed parser summary is not authoritative when it double-counts XCTest suite summaries. Retained raw logs and result bundles let us resolve those distinctions without repeatedly rerunning the app.

## 9. Accessibility audits need explicit limits

The audits found useful issues with descriptions, actions, and hierarchy. They did not establish the complete speech experience or every focus-notification sequence.

Contrast checking became an unproductive investigation involving system controls and questionable screenshot crops. You explicitly excluded it. The honest record is “excluded by decision,” not “passed.” I should have bounded that investigation sooner.

The remaining live native field-editor/overlay parent-child mismatch is also a limit worth preserving in the record. The invalid-name form passes its audit after Tab leaves native editing, and the empty field's accessible label is asserted. That does not prove the live-editing mismatch itself was fixed.

These qualifications make the evidence more useful. They prevent a future maintainer from assuming we verified something we did not.

## 10. Test isolation includes what remains after testing

UUID preference suites and disposable folders protected your normal registrations during UI automation. Real folder authorization also kept the sandbox tests meaningful.

The final cleanup nevertheless found many leftover test preference files and private temporary entries. Some cleared preference domains left empty plist files behind. Teardown that requests cleanup is not the same as verified absence of persistent test data.

Next time I would check cleanup much earlier, including failure before fixture readiness and interrupted tests. Resetting app data must also avoid following sandbox symlinks into shared user folders. Removing registrations and bookmarks is separate from deleting the external project folders they refer to.

## 11. Release readiness requires inspecting the built artifact

The application built and its signature verified, but inspecting its resources revealed that engineering Markdown documents had been bundled with it. That was easy to miss in a successful build and easy to catch in a content check.

We excluded those documents and verified a clean archive. We also checked the actual architectures, sandbox entitlement, absence of the debugger entitlement and test bootstrap, and the signature after extracting the distribution ZIP.

Ad hoc signing, notarization, and successful local signature verification are distinct facts. We produced the ad hoc release requested; we did not describe it as notarized.

The lesson is to verify the thing being delivered, including its packaged form. Compiler success is only one part of that.

## What I would carry into the next project

I would keep the deliberate checkpoints, concrete behavior examples, Swift 6 ownership boundaries, and early feedback from the person who will actually use the software.

I would improve the process by making the UI-test helpers reliable earlier, treating desktop disruption as a limited resource, inspecting release resources before the final day, and distinguishing test defects from application defects more carefully in progress reports.

My strongest observation is that the most valuable corrections were often requests for less: fewer interruptions, less guessing, less automatic file handling, and fewer repeated tests. BrainDump became better as its behavior became more explicit and its demands on the user became smaller.
