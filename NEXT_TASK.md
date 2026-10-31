# Vavrio — Next Implementation Task

**Task:** Save As to a new destination for the existing single-file prototype.

**Status:** Proposed; awaits developer approval. The developer-authorized existing-file Open/Edit/Save prototype is implemented, passes 37 tests, and is installed as 0.2.0 (build 5). Native core-loop and unsaved Cancel/Discard checks passed; the later editor-width correction also passed geometry and developer visual checks; [STATUS.md](STATUS.md) records evidence. That completion does not authorize this follow-up, installation, a commit, or a push.

## Outcome

An already-open supported file can be saved under a new name through File → Save As. Success adopts the verified new file as the session's baseline; cancellation, a destination collision, or a failed/uncertain publication retains the current document and edits. Existing destinations are refused in this increment. No untitled/new-document lifecycle is added.

## Scope and proposed policy

1. Add a Foundation/Darwin-only create-new operation beside the existing writer. Reuse the encoder, metadata inspection, and typed outcomes where appropriate; do not weaken the existing-file replacement checks or add dependencies. Inspect the actual implementation before choosing small shared helpers.
2. Limit this first Save As to a supported source snapshot and a local destination parent whose identity, path resolution, permissions, and ACL policy can be verified. Use current-user ownership and the destination directory's normal group policy. Copy ordinary source rwx bits (including execute, stripping special bits), supported xattrs/security metadata, and supported nonblocking flags; use a new creation date. Refuse unsupported/unavailable metadata rather than silently discarding it. No privileged ownership repair. Define and test how an externally changed source snapshot is handled before enabling publication; retaining an in-memory snapshot must not imply permission to reread and overwrite the source.
3. Create and verify private staging on the destination volume. Verify encoded bytes and intended metadata, then publish exclusively with `renamex_np(RENAME_EXCL)` or an equally enforceable create-new primitive. A prior existence check alone is insufficient. The investigation established exclusive publish/EEXIST on the reference volume; complete metadata/failure behavior still needs integration tests. A collision, including one introduced after final checks, must leave the destination unchanged.
4. Distinguish failures before publication from uncertain outcomes after invoking it. Verify a successful result and return a fresh eligible baseline. Retain edits and owned recovery information for uncertainty; do not auto-retry, roll back, or overwrite an arbitrary destination. Report cleanup failure after verified success as a warning. Keep synchronous I/O within one background operation; serialize session operations.
5. Wire File → Save As (⇧⌘S) to NSSavePanel. Explain that this increment needs a new name; refuse overwrite even if the panel offers its own replacement confirmation. Preserve the current document on cancellation/failure. On verified success, adopt the new URL/baseline, preserve undo and any newer edits, and mark clean only if current bytes equal the saved snapshot. Keep the existing Save/Discard/Cancel guard behavior and uncertainty handling consistent. Save As after an uncertain save is outside this first scope unless explicitly resolved during review.
6. Record build/test/native evidence and refresh the one current handoff after completion. Prepare a bundle for an approved local refresh, but do not replace the installed app without authorization and a confirmed quit. No commit or push without a separate request.

Routine local type names and small refactors needed for this path are implementation choices. Return a concrete unresolved preservation/data-loss decision with evidence rather than silently broadening the policy.

## Acceptance checks

- All existing 37 tests remain green. New fixtures verify exact BOM/Unicode/line-ending bytes, ordinary/executable mode, supported xattrs/flags, ownership/group policy, and new creation metadata at a new destination, including Unicode names and a different parent directory.
- Verify source and unrelated sentinel bytes/metadata remain unchanged by Save As. Verify a second ordinary Save uses the newly adopted baseline/path.
- Refuse an already-existing regular file, symlink, directory, and a destination created between preflight and publication. Assert the contender/destination/sentinel contents are unchanged on collision.
- Exercise unsupported parent/metadata, staging failure, publication failure, post-publication uncertainty, and cleanup warnings with narrow seams only where real fixtures are insufficient. Reconcile result states with actual disk bytes and owned recovery directories.
- Session checks cover cancellation/failure retaining the original URL/text/dirty state and edits made during publication remaining dirty after success. Uncertain results must not silently adopt a clean baseline.
- Native checks cover Save As cancellation, a successful new-name save/adoption, collision refusal, and subsequent ordinary Save. Repeat existing Open/Edit/Undo/Redo and unsaved transitions only where this integration affects them. Record what was actually checked.

## Verification commands

Use existing tools and two build jobs:

```sh
sh Scripts/build.sh --local-manifest-libs
SWIFTPM_CUSTOM_LIBS_DIR="$PWD/.build/swiftpm-local-libs" xcrun swift test --jobs 2 --disable-xctest
git diff --check
```

Use normal permission handling for compiler caches and fixture metadata/coordination access. Do not repeat the full replacement investigation unless new evidence requires it. Native checks need the developer's interaction; compilation alone is insufficient.

## Non-goals

Existing-destination Save As overwrite; untitled/new documents; multi-document tabs; NSDocument migration; broad ACL/resource-fork/provider support; force-save/automatic recovery; crash or power-loss durability guarantees; hostile-path guarantees; file watching; resource benchmarking; runtime/Codex work; dependencies or global settings; automatic installation; commits; pushes. Remaining native edge checks and representative workload baselines still belong to full Milestone 2 and are not declared complete by this task.

## Handoff to Sol

> Read professor_ara.md, AGENTS.md, the current STATUS.md prototype evidence, and NEXT_TASK.md. After explicit authorization, implement only new-destination Save As for the existing single-file session. Preserve the guarded existing-file writer and pending user changes. Verify create-new exclusivity, metadata, failure/uncertain outcomes, session adoption, and native interactions. Stop before existing-destination overwrite or another milestone; do not commit/push without a separate request.
