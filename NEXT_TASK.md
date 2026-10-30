# Vavrio — Next Task

**Task:** Plan the first small Milestone 2 increment — editing and safe saving.

**Status:** Proposed planning task; not started. Milestone 1C was explicitly authorized and completed locally on 2026-10-30. Its regression/build/test evidence is in [STATUS.md](STATUS.md). No commit or push was made. The completed 1C authorization does not authorize Milestone 2 implementation; obtain developer direction before starting this proposed planning task.

## Outcome

Prepare one bounded implementation handoff for the first editing/safe-saving increment. Explain the relevant document-lifecycle and persistence decisions so the developer can approve concrete scope before application changes begin.

## Planning scope

1. Inspect the current AppKit viewer and independent reader against Milestone 2 in [ROADMAP.md](ROADMAP.md) and the architecture boundaries in [VISION.md](VISION.md).
2. Compare NSDocument with a small explicit document model for the single-file app. Recommend an approach and explain its ownership of file identity, text, dirty state, asynchronous load/save completion, and native decisions.
3. Settle the policies needed before writes: BOM retention, newline handling, symlink targets, executable permissions/relevant metadata, safe replacement, and external-change conflicts. Explain race limitations rather than promising conflict prevention from replacement alone.
4. Define the first increment's scope and dependencies. Include the relevant unsaved-edit protections, failure behavior, loading/cancellation policy, tests, and manual native checks. Keep the full Milestone 2 requirements visible without bundling all of them into an unnecessarily large first implementation.
5. Replace this proposal with one implementation handoff containing outcome, scope, non-goals, acceptance checks, verification commands, and explicit authorization status. Record decisions and unresolved questions in STATUS.md; update ROADMAP.md/VISION.md only if an agreed decision changes them.

## Acceptance checks

- The recommendation follows the inspected code and explains meaningful trade-offs.
- No file-writing behavior is introduced before its policies and implementation scope are approved.
- The proposed increment has concrete checks for successful behavior, cancellation, errors, and preservation of source files/unsaved text where applicable.
- Native interaction and performance measurements are identified separately from unit tests and compilation. The existing reader supports regular UTF-8 files up to 2 MiB; the 1C regression suite remains a prerequisite for subsequent reader changes.
- Only one bounded task remains in this file, and all continuation documents agree about current capabilities and authorization.

## Verification

For this proposed documentation/planning task, inspect local links, review the handoff against ROADMAP.md and the actual code, and run `git diff --check`. Application builds/tests are needed only if separately authorized source changes occur; planning alone does not establish runtime behavior.

Existing implementation verification commands, for reference when preparing the next handoff:

```sh
sh Scripts/build.sh --local-manifest-libs
SWIFTPM_CUSTOM_LIBS_DIR="$PWD/.build/swiftpm-local-libs" xcrun swift test --jobs 2 --disable-xctest
git diff --check
```

Use the existing tools and two build jobs. The helper prepares ignored local SwiftPM libraries needed on the reference machine. Use normal compiler-cache permission handling if necessary; do not install or repair tools as part of planning.

## Non-goals

Application implementation, Milestone 3/runtime work, live Codex calls, new dependencies, installation or toolchain repairs, macOS/global configuration changes, app launch, commits, and pushes.
