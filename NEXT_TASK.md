# Vavrio — Next Task

**Task:** Milestone 2B preparation — verify replacement behavior and finalize the writer contract.

**Status:** Proposed; not started or authorized. Milestone 2A was explicitly approved with “Yes, proceed” and completed locally on 2026-10-30. Its successful build and 21-test reader/encoder evidence are in [STATUS.md](STATUS.md). The completed 2A/app-packaging snapshot was subsequently published as [e8e95b9](https://github.com/Viswanath70105/Vavrio/commit/e8e95b98b8c25ac5d0dfdfc8adc10f425fa59545), with the remote hash independently verified. Approval of 2A does not authorize this investigation, a production writer, or native editing/saving. The developer then requested a local macOS icon/app-packaging interlude; the app is installed and its launch/opening confirmed, with the selected dark minimal logo installed, then corrected to edge-to-edge artwork after a Dock screenshot. This persistence task remains proposed and has not begun.

## Outcome

Resolve the file-replacement and metadata questions on disposable fixtures, then prepare one bounded production-writer handoff with a supported-file policy, failure semantics, acceptance checks, and authorization status. The application remains read-only throughout this investigation.

The current app can retain an original byte snapshot and serialize text to Data in memory. That does not establish safe filesystem writes, source identity, metadata preservation, conflict detection, or native Save behavior.

## Proposed scope

1. Read the current encoder/reader and Milestone 2 planning policies in STATUS.md. Recheck installed API declarations and Apple's replacement/coordination documentation. Prefer existing Swift, Foundation, Darwin, and system tools; no downloads or global changes.
2. Prepare a small reproducible probe using a uniquely named disposable directory under ignored .build output or the system temporary directory. Restrict every write/replacement/cleanup to fixtures created by that probe. Keep only a small sanitized script/fixture recipe if it materially helps review or future tests; no package/dependency restructuring.
3. Test same-volume temporary-file preparation and FileManager replacement on an ordinary existing file, verifying resulting bytes and cleanup. Compare original/resulting POSIX modes (including executable bits), ownership, relevant flags, creation metadata, ACLs, and extended attributes where the current environment permits those fixtures. Probe the proposed new-Save-As metadata policy separately from replacement of an existing destination; document unavailable checks explicitly.
4. Exercise missing destinations, rejected directories/special files, leaf symlinks, multiply hard-linked files, an external byte change, and changed target identity. Check link targets and unrelated fixture bytes remain intact. Determine exactly which checks the later writer needs before an operation; do not treat raw replacement API behavior as a sufficient Vavrio policy.
5. Exercise deterministically reproducible failures in preparation and replacement, inspect bytes/metadata/remaining temporary files afterward, and distinguish proven unchanged-source failures from uncertain outcomes. Do not manufacture proof of every disk-full, power-loss, concurrent-writer, or rollback scenario. Explain the final check/replacement race and whether cooperative coordination is useful; do not promise an atomic compare-and-swap guarantee.
6. Recommend the initial writer's supported paths/files and metadata contract. Preserve POSIX executable/read-write bits; either preserve relevant ACL/xattr/security metadata with verified behavior or reject unsupported in-place saves explicitly. Settle new-file permissions and existing-destination overwrite semantics before implementation. Resolve any material architecture or data-loss decision with concrete evidence and a recommendation.
7. Record the observations/limits in STATUS.md and prepare only one bounded writer implementation handoff in this file. Keep lifecycle/NSDocument integration and UI work out of that handoff unless separately approved.

## Acceptance checks

- All filesystem changes are confined to known disposable fixtures; the current viewer and selected source files acquire no write capability.
- Evidence distinguishes replacement success, metadata behavior, rejected unsupported cases, known pre-replacement failures, and uncertain outcomes. Report exact byte/metadata observations rather than treating a nonthrowing call as complete verification.
- The proposed writer handoff specifies source/destination identity and byte baselines, link policy, permissions/metadata support, same-volume replacement, temporary-file ownership/cleanup, and success/failure/uncertainty results. It keeps blocking I/O off the main actor and carries immutable input; no document UI or runtime state leaks into storage code.
- The developer receives a concrete recommendation for any unresolved preservation or data-loss choice before production writes are implemented. No source-path overwrite feature is silently introduced by this investigation.
- NEXT_TASK.md ends with only the next proposed bounded task. Current capability/status references remain consistent and no experimental result is recorded as a shipped save feature.

## Verification

Run the disposable probe with existing tools and modest compiler concurrency; record exact commands and results. Use normal permission handling for compiler caches or fixture metadata operations if necessary. Verify cleanup is restricted to the probe's own directory. Review any retained script/recipe, local Markdown links, final newlines, and `git diff --check`.

Application source/tests remain unchanged in this proposed investigation, so a full package build/test rerun is unnecessary unless a separately approved source change occurs. The latest implementation commands remain:

```sh
sh Scripts/build.sh --local-manifest-libs
SWIFTPM_CUSTOM_LIBS_DIR="$PWD/.build/swiftpm-local-libs" xcrun swift test --jobs 2 --disable-xctest
```

## Non-goals

Production writer or conflict-gate implementation; writes outside owned disposable fixtures; AppDelegate/NSDocument changes; editing, Save/Save As, or native prompts; loading recovery; runtime/Codex work; new dependencies; installations/toolchain repair; global configuration changes; app launch; commits; and pushes.
