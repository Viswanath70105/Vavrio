# Vavrio — Verified Status

Last updated: 2026-11-03 (Asia/Kolkata).

This document records current evidence and limitations. Product intent belongs in [VISION.md](VISION.md), milestone criteria in [ROADMAP.md](ROADMAP.md), and the current bounded handoff in [NEXT_TASK.md](NEXT_TASK.md).

## Reader and navigation update — 2026-11-03

The developer confirmed build 6 works and requested improvements. Build 7 (0.3.1) adds per-tab × controls, native source-list explorer icons/selection and keyboard selection, folder-row expansion, active-tab selection synchronization, and an optional Reader pane. Closing a tab never deletes its file; dirty tabs use the existing Save/Discard/Cancel path.

The shared native reader renders common Markdown with 200 ms debounce and a 200,000-character preview limit. It uses AppKit plus Foundation's inline Markdown parser, with no added dependencies or web process. It formats headings, emphasis, code, bullets/task items and quotes; HTTP(S) links are clickable. Tables remain monospaced source, images are not fetched, and relative links/full Markdown compatibility remain unsupported. No memory/CPU measurement or resource advantage is claimed.

Final full suite passed 41 tests, including background-tab close preserving the file and other dirty edits, reader styling, CRLF handling, restricted clickable links and latest-update rendering. The previous native core workflow has user confirmation; visible build-7 layout, close dialogs, navigation and reading still need interaction checks. Build, signature/plist validation and whitespace checks passed. Bundle: `.build/app-packages/package.SA2kY2/Vavrio.app` (0.3.1 build 7). Storage/session implementations are unchanged. No installed-app replacement or publication occurred.

## Build 6 baseline

- Markdown workspace implemented in source and packaged as **0.3.0 (build 6)** on 2026-11-03 after the developer's explicit request. Folder explorer, multiple retained document tabs, plain Markdown editing, independent undo/redo, guarded Save, per-tab close and all-document quit decisions are implemented.
- Development bundle: `.build/app-packages/package.K7jZ1j/Vavrio.app`; build, ad-hoc signature and plist validation passed. Installed `/Applications/Vavrio.app` remains **0.2.0 (build 5)**. No installation, commit or push occurred in this increment.
- Full automated suite: **39 tests passed**, including the 37 existing storage/session tests and two new workspace tests. An unshown AppKit window exercised actual native text views, tab selection, independent unsaved text/undo, selection retention, duplicate-path selection and saving one file while another remains dirty. A subsequent focused run passed scroll-position retention and native editor width checks at 640/1200/900 points. An initial test exposed native undo changing text without synchronously updating the session; explicit undo/redo command synchronization fixed it.
- Native visible interaction with folder dialogs, explorer expansion, overflow tabs, Save/Discard/Cancel across several dirty tabs and window close/quit still needs developer verification. Automated AppKit checks are not a claim of completed manual interaction.
- No new memory, CPU or editing-latency measurement was taken. No resource advantage is claimed. The implementation has no new dependencies, preview renderer, watcher or indexer; directory reads run off the main actor on expansion. Each open file retains its own native editor, so memory increases with open documents and undo history.
- Save As, new documents, preview, syntax highlighting, tab restoration, runtime and Codex integration remain unimplemented. Existing 2 MiB UTF-8 and save-eligibility restrictions remain.

## Markdown workspace design and limits

The explicit DocumentSession model is retained per document rather than migrating storage to NSDocument in this increment. `EditorDocument` owns native editor/scroll/undo state; `MarkdownBrowser` owns lazy folder UI; AppDelegate still coordinates the window and native transitions. The earlier standalone window-controller extraction is superseded, with further ownership cleanup deferred.

Open Folder (⇧⌘O) changes the explorer without closing existing tabs. Open (⌘O) accepts `.md` files. Clicking a file selects an existing standardized-path tab or opens a new one. Tab switching retains unsaved edits without prompting. Save (⌘S) affects the active tab; Close Tab (⌘W) checks that tab; window close/quit checks all dirty tabs. A later Cancel leaves the remaining documents open, including any earlier Discard choices; prior successful saves remain saved. File transitions are gated while a read/write is outstanding. Newer edits during a save remain supported by the unchanged session.

The explorer omits hidden entries and symlinks, shows directories even when they contain no Markdown files, and reads only expanded directories. Refresh resets the tree and retains open documents. Directory reads have no timeout/cancellation and no live watching; a stalled provider can leave a listing pending. File-open logical cancellation retains the worker slot until the underlying read returns. No automatic reload, forced overwrite, create, rename or delete was added.

## Environment and commands

Reference machine: 2020 Apple M1 MacBook Pro, 8 GB unified memory. Last implementation environment: macOS 26.5.2 (25F84), Swift 6.1.2, Command Line Tools SDK 15.5. The package declares Swift 6 mode and macOS 14; execution on macOS 14 is untested. No third-party dependencies.

Plain SwiftPM builds encounter an installed manifest-interface mismatch. The verified no-download workaround copies the existing manifest libraries under ignored `.build` and excludes their private interfaces; it does not modify the installed toolchain.

```sh
sh Scripts/build.sh --local-manifest-libs
SWIFTPM_CUSTOM_LIBS_DIR="$PWD/.build/swiftpm-local-libs" xcrun swift test --jobs 2 --disable-xctest
sh Scripts/package-app.sh --local-manifest-libs
git diff --check
```

The helpers use two build jobs. Packaging creates a fresh signed bundle under `.build/app-packages`; it never installs or launches automatically. The installed app remains a snapshot until an authorized refresh after a confirmed quit.

## Verified prototype behavior

- Reads regular UTF-8 files up to 2 MiB, with strict decoding and NUL rejection. Omits at most one initial BOM from display and retains it for saving. Subsequent U+FEFF and existing line endings remain text. Unsupported save metadata does not unnecessarily break viewing.
- DocumentSession holds an immutable file baseline separately from editable text. Dirty state compares UTF-8 bytes. Failed opens/saves retain edits; a save finishing after newer edits updates only the saved baseline. The developer explicitly chose this single-file model; NSDocument remains deferred.
- Save eligibility requires an existing local, current-user-owned, single-link regular file with owner read/write permission. Selected symlinks, special mode bits, extended file/parent ACLs, unsupported flags/resource/compression metadata, and unavailable or excessive xattrs are refused. Xattr name/value capture is bounded at 256 KiB.
- The writer rechecks full bytes, identity, metadata, and parent identity; prepares a verified original copy in private same-volume staging; modifies only staged bytes; rechecks; replaces; and verifies. It uses `.usingNewMetadataOnly` only on the metadata-verified copy: default replacement rounded creation-time nanoseconds in fixtures. Mode, uid/gid, exact creation time, supported flags, and supported xattrs are verified before/after saving.
- Results distinguish not-written, saved, and uncertain. Uncertain outcomes retain edits/recovery information and block retry until a fresh open. Cleanup failure after verified success is a saved result with a warning. No automatic rollback or forced overwrite.
- Cancel Open and the logical 10-second timeout reject late results while retaining the single worker slot until synchronous I/O returns. They do not interrupt a stalled filesystem call. Close/quit is refused during saving.

## Verification evidence

- **Automated:** final prototype suite passed **37 tests** on 2026-10-31, covering reader/encoder fidelity, metadata/save round trips, stale/unsupported targets, injected failures, uncertain outcomes, cleanup warnings, sentinel preservation, dirty state, failed opens, late-load cancellation/timeout, and edits during saving. The reported 0.710-second suite duration is not a benchmark. Build 5 subsequently compiled successfully; no storage/session changes followed that suite.
- **Native:** the developer confirmed Open/Edit/Undo/Redo/Save/reopen, Cancel on unsaved quit, and Discard on replacement Open. Disk inspection of the edited Hello.swift fixture found `Prototype`, its original UTF-8 BOM/Unicode comment, two CRLF endings, and no bare LF.
- **Clipping fix:** an unshown AppKit diagnostic found a 900-point viewport containing an 1800-point editor, allowing horizontal offset. Initializing the editor from the scroll view's content size corrected widths at 900 → 480 → 1440 → 900, retained the 16-point inset, and held constrained horizontal origin at zero. The developer confirmed first characters and margin remain visible after resizing and sideways trackpad scrolling.
- **Packaging/install:** build 5 is staged at `.build/app-packages/package.Bow1NX/Vavrio.app`. Signature/plist checks and installed executable/plist comparisons passed; launch exited 0. The developer manually quit before replacement. Previous build 4 is retained at `.build/app-packages/previous.Bdk7vA/Vavrio.app`; earlier rollback bundles and native-check fixtures remain ignored and were not pruned.
- **Investigation:** the retained [replacement probe](Scripts/probe-file-replacement.swift) passed 22 disposable scenarios. Product tests now cover core guarded-save behavior, but the probe still contains raw API comparisons and exclusive new-file publication/EEXIST evidence needed to inform Save As. It is an experiment, not production code or a substitute for Save As integration tests.

## Known limits

The final check and replacement are not an atomic compare-and-swap. An uncooperative writer can change the target in the gap; a controlled test demonstrates overwrite in that interleaving. File coordination does not remove this race. Power-loss durability, disk-full/provider/network stress, hostile-path safety, broad ACL support, crash recovery, and current performance claims are not established.

Native close-button behavior, Save from the unsaved dialog, current native error paths, and representative source/long-line/many-line/complex-Unicode workloads still need checks. Save As, new documents, external-file watching, and broader document lifecycle support remain future work.

## Maintenance audit — 2026-10-31

- Created the developer-approved local prototype checkpoint before cleanup; the tree was clean immediately afterward. Publication followed the later explicit commit/push request.
- Removed the persona document and active references. Consolidated professional communication, scope, architecture, preservation, and verification rules in AGENTS.md. No application behavior or installed bundle changed.
- Reduced this file to current state/evidence. The complete earlier record, including original approvals, failures, 1A observations, publications, replacement scenarios, and install details, remains in `git show ae2ea87:STATUS.md`.
- NEXT_TASK.md records the file inventory and proposed AppDelegate/window-controller split. No production file was established to be dead. The probe is retained for unique coverage; selected assets, tests, and both build scripts remain in use. Known mechanical cleanup candidates are an unused `verifyCopy` parameter and a discarded `check` return value; neither was changed in this documentation increment.
- Sources, Tests, Package.swift, Scripts, Resources, and Assets remain identical to the checkpoint. Final checks passed: `git diff --check`, eight Markdown documents with balanced fenced blocks/final newlines, 29 resolving local links, and absence of retired-persona references in active documents and `.gitignore`. All application/test/build/package/asset files match the checkpoint. No application tests or native checks were repeated for these documentation-only edits. The developer subsequently authorized committing and publishing the completed cleanup; the proposed structural refactor remains unapproved.

## Publication — 2026-10-31

The developer explicitly requested “Commit and push now.” Fetch confirmed origin/main was one checkpoint behind local HEAD with no remote-only commits. Pushed `ae2ea87` and independently verified its full hash with `git ls-remote`. The accompanying cleanup commit removes the persona and simplifies documentation without source changes. The final cleanup commit and remote equality are verified after committing/pushing; publication does not authorize the structural refactor or Save As.

## Next action

Use the staged build for the native Markdown workflow checks in NEXT_TASK.md. Refreshing Applications requires explicit authorization and a confirmed manual quit. No publication is authorized. The previously verified build-5 evidence below the current state remains historical evidence, not verification of the new multi-document UI.
