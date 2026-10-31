# Vavrio — Verified Status

Last updated: 2026-10-31 (Asia/Kolkata).

This document records current evidence and limitations. Product intent belongs in [VISION.md](VISION.md), milestone criteria in [ROADMAP.md](ROADMAP.md), and the current bounded handoff in [NEXT_TASK.md](NEXT_TASK.md).

## Current state

- Single-file native Open/Edit/Save prototype: implemented and verified on the reference Mac. Full Milestone 2 is incomplete; Save As, further native edge checks, and representative file-layout workloads remain.
- Installed app: `/Applications/Vavrio.app`, version **0.2.0 (build 5)**, with the selected dark icon and corrected editor width. Local debug/ad-hoc signing only; no public binary release or notarization.
- Local checkpoint: `ae2ea87ffeb479078ce2da487fd27a2fe2a29336` (`feat: checkpoint verified single-file editing prototype`). It includes the writer, document session, native integration, investigation script, tests, and clipping fix. It was pushed to origin/main on 2026-10-31 after the developer's explicit commit/push request; a direct remote query returned the same full hash.
- Current maintenance: the developer approved the checkpoint, persona removal, concise guidance, and a cleanup/refactor audit. Persona removal and the audit are complete. The proposed structural refactor is in NEXT_TASK.md and awaits approval; Save As is deferred in ROADMAP.md.
- Agent runtime, CLI host, Codex integration, syntax highlighting, and workspace browser: not implemented. No performance advantage has been demonstrated.

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

Review the bounded structural refactor in NEXT_TASK.md. Do not implement it, start Save As, refresh the installed app, or push without the corresponding authorization. The completed cleanup is approved for publication; the prototype checkpoint is published.
