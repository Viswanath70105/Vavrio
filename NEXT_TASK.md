# Vavrio — Next Implementation Task

**Task:** Separate application lifecycle from the native editor window.

**Status:** Proposed; awaits approval. The developer approved the preceding local checkpoint, persona removal, and cleanup audit. Those are complete. The developer subsequently authorized committing/pushing the completed work; the structural refactor below still awaits approval. The working prototype is checkpointed in `ae2ea87`; the installed app remains 0.2.0 build 5. Save As is deferred in ROADMAP.md.

## Audit outcome

There is no unused production source file to delete. The actionable issue is ownership: AppDelegate currently constructs the window, configures menus, binds editor/session state, presents file/error/unsaved dialogs, and handles both window and application termination. Seven source files total 827 lines; an additional runtime/module hierarchy is not justified by the current feature set.

The persona document was removed as requested. STATUS.md now contains current evidence; the full prior record is retained in `git show ae2ea87:STATUS.md`. The earlier new-destination Save As proposal is retained in `git show ae2ea87:NEXT_TASK.md` and summarized in ROADMAP.md.

## File inventory and disposition

| File | Finding and disposition |
| --- | --- |
| `Sources/Vavrio/Vavrio.swift` | Executable entry point and delegate lifetime; keep. |
| `Sources/Vavrio/AppDelegate.swift` | Active UI and lifecycle code; split responsibilities in the proposed task. |
| `Sources/Vavrio/DocumentSession.swift` | Active document state and operation serialization; keep unchanged for this refactor. |
| `Sources/Vavrio/TextFileReader.swift` | Bounded strict reader and original snapshot; keep. |
| `Sources/Vavrio/TextFileEncoder.swift` | Byte/BOM validation and serialization; keep. Its comment about writes belonging to a later task is stale; correct in a later mechanical cleanup. |
| `Sources/Vavrio/FileSaveBaseline.swift` | Descriptor metadata/eligibility used by reader and writer; keep. |
| `Sources/Vavrio/TextFileWriter.swift` | Guarded persistence and test seams; keep unchanged. `verifyCopy` has an unused file parameter and `check` returns a snapshot all callers discard; these are later mechanical cleanup candidates, not dead files. |
| `Tests/VavrioTests/TextFileReaderTests.swift` | Reader fidelity, bounds, invalid input, and special-file checks; keep. |
| `Tests/VavrioTests/TextFileEncoderTests.swift` | Serialization/byte round trips and rejection checks; keep. |
| `Tests/VavrioTests/TextFileWriterTests.swift` | Save/metadata/conflict/failure/uncertainty tests; keep. |
| `Tests/VavrioTests/DocumentSessionTests.swift` | Dirty state, newer edits, failure, cancellation/timeout tests; keep. |
| `Scripts/build.sh` | Verified two-job build and installed-toolchain workaround; keep. |
| `Scripts/package-app.sh` | Used to generate installed app, icon and signature; keep. |
| `Scripts/probe-file-replacement.swift` | Not in the app target, but not obsolete. Retain raw API metadata comparisons, ACL inheritance, and exclusive new-file/EEXIST evidence until Save As has focused coverage and its remaining investigative value is reviewed. |
| `Package.swift` | Active executable/test targets, no third-party dependency; keep. |
| `Resources/Info.plist` | Packaging identity/version/icon/minimum OS; keep. |
| `Assets/VavrioIcon-minimal-dark.png` | Selected installed icon; keep. |
| `Assets/README.md` | Packaging asset description and provenance link; keep. |
| `Assets/VavrioIcon-minimal-dark-prompt.md` | Provenance of the selected asset; keep. |
| `.gitignore` | Prevents generated bundles, credentials and local output being tracked; keep, remove obsolete persona comment. |
| `AGENTS.md` | Simplified professional development rules; keep. |
| `README.md` | User/build/verification entry point; keep, remove persona references. |
| `VISION.md` | Product/runtime boundary and risks; keep. |
| `ROADMAP.md` | Broader milestone criteria, deferred Save As policy; keep. |
| `STATUS.md` | Current evidence and limitations; shorten, retain detailed history in Git. |
| `NEXT_TASK.md` | This single audit/handoff; replace the prior Save As handoff while maintenance is current. |

Ignored `.build` output is separate from dead source. It contains generated diagnostics/bundles as well as rollback copies and developer-edited native fixtures. Nothing there was deleted; cache/backup removal needs a bounded list that preserves useful fixtures and recovery copies. No new permanent audit document or archive tree is needed.

## Proposed outcome and scope

Introduce one `EditorWindowController` for the single native window. AppDelegate manages application startup, application-level menu installation, and termination delegation. The window controller owns its views, DocumentSession, undo manager, file/edit commands, UI updates, and native dialogs. Preserve observable behavior and keep the storage layer unchanged.

1. Extract the existing window/editor configuration and bindings into an AppKit window controller. Make window/session ownership explicit and retain the controller through the app lifetime; avoid delegate ownership cycles. Preserve the build-5 viewport sizing and text configuration exactly.
2. Move Open/Save/Cancel Open, undo/redo, menu validation, alerts, and Save/Discard/Cancel handling with their window/session state. Keep the three-button unsaved decision consistent across Open, close, and quit.
3. Keep the application menu and app termination entry point in AppDelegate. Delegate the asynchronous leave-document decision to the window controller through a small interface; keep `.terminateLater`/reply behavior, in-flight-save refusal, modal transition exclusion, and last-window-close termination intact. File/Edit menu items must target the live controller. No general coordinator/service or separate menu-builder hierarchy is needed.
4. Keep DocumentSession and persistence implementation unchanged; do not mix status/result redesign, Save As, or storage cleanup into this extraction. Correct only moved-code comments/names that would otherwise be misleading. Return any concrete behavior/ownership issue discovered during extraction with evidence.
5. Update the status and prepare only the next bounded handoff. Do not delete the probe, change dependencies/package layout, reinstall, commit, or push automatically.

## Acceptance and verification

- Review the diff against `ae2ea87`: all existing UI actions, text settings, width tracking, session operation gates, title/dirty indication, undo routing, and unsaved decisions remain represented.
- All 37 existing tests pass. Avoid new tests that only assert the new class/file structure; add a behavioral test only if an actual policy change or uncovered failure needs one.
- Build using the existing two-job helper and validate whitespace:

```sh
sh Scripts/build.sh --local-manifest-libs
SWIFTPM_CUSTOM_LIBS_DIR="$PWD/.build/swiftpm-local-libs" xcrun swift test --jobs 2 --disable-xctest
git diff --check
```

- Run an authorized development build for native checks: Open/Edit/Undo/Redo/Save/reopen, menu enablement, unsaved Cancel/Discard/Save, close/quit, and resize/sideways-scroll margin behavior. Check both window-close and application-quit paths because responsibility moves between delegates. Use disposable fixtures; no automated quit of a developer session.
- Report code/build/tests separately from manual interaction. Do not mark the refactor fully verified until the affected native paths are checked. No performance improvement is claimed from moving code.

## Non-goals

Save As/new documents; NSDocument migration; storage-policy changes; generic protocols/services or additional packages; a new UI design; broad formatting rewrites; deleting tests or experiments with unique coverage; cache/rollback cleanup; runtime/Codex work; dependencies/global settings; installed-app replacement; commits; pushes.

## Continuation

After explicit authorization, implement only this application/window ownership split. Preserve the checkpoint behavior, current user edits, and file-preservation gates. Stop before another implementation increment or publication.
