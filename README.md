# Vavrio

**Room to code. Clarity to build.**

Vavrio is a student-led, AI-assisted project to build a lightweight, native macOS IDE with an independently reusable Swift runtime for AI coding agents. Its first product goal is one inspectable coding-change workflow: understand what ran, review what changed, preserve your own edits, and verify the result on a limited-memory Mac.

**Status: Vavrio 0.2.0 is a working single-file editing prototype on the reference Mac.** Open a supported local UTF-8 file, edit it, undo/redo, and explicitly save it with ⌘S. Unsaved changes prompt Save/Discard/Cancel before switching files, closing, or quitting. All 37 reader/encoder/writer/session tests pass. The developer confirmed native Open/Edit/Undo/Redo/Save/reopen and unsaved Cancel/Discard checks on 2026-10-31. [STATUS.md](STATUS.md) records evidence and limits. Save As, new documents, the agent runtime, CLI host, and Codex integration remain future work.

Milestones 1A/1B, the [1C BOM fidelity correction](https://github.com/Viswanath70105/Vavrio/commit/8fcf7a1af762f67e5916c2735882ae564cc4d786), and [2A byte-faithful serialization](https://github.com/Viswanath70105/Vavrio/commit/e8e95b98b8c25ac5d0dfdfc8adc10f425fa59545) are complete and published. A 22-scenario replacement investigation informed the guarded existing-file writer now used by the prototype. The writer and native editing changes are locally verified, installed, and published in prototype checkpoint `ae2ea87` after an explicit commit/push request. [NEXT_TASK.md](NEXT_TASK.md) records the cleanup audit and proposes separating application lifecycle from the native editor window. Save As remains deferred in [ROADMAP.md](ROADMAP.md).

## Why Vavrio?

Your editor should leave room for your browser, documentation, and other tools. AI assistance should let you inspect the work happening in your project and stay in control of consequential actions.

Vavrio is being designed around a 2020 Apple M1 MacBook Pro with 8 GB unified memory. This is a design constraint, not a performance claim. The long-term architecture has two parts serving the first workflow:

- **Native IDE:** text editing, file management, project navigation, agent controls, and an execution inspector.
- **Independent runtime:** task lifecycle, structured events, tool traces, approval state, and resource-aware scheduling, usable by a CLI or another application.

The first complete demonstration will fix a deliberately failing test in a small project, show available execution evidence, review and safely apply changes, and report verification. Workspace selection and basic changed-file review are part of that goal. Broader IDE features follow demonstrated need. A reproducible demo, measured workloads, and a small pilot with independent developers will test whether the result is useful; adoption and performance advantages are not established yet.

## What transparent execution could look like

Suppose you ask an agent to fix a failing test. In the planned workflow, you could follow:

1. **Inspect:** see which files it reads and which test command it runs.
2. **Review:** inspect the proposed diff and a request for approval before applying it.
3. **Decide:** approve or reject the change; record the decision alongside the action.
4. **Verify:** inspect the follow-up test result, errors, and available timing or resource measurements.

This is an illustrative goal, not an implemented feature. Visibility and approval gates depend on supported agent interfaces. Required approvals must block the corresponding action; missing or truncated events must be identified. Transparency covers observable execution, not private model reasoning.

## Planned architecture

```text
Native IDE (Swift / AppKit) ───┐
                             ├──> Agent runtime library ───> Agent adapter ───> Codex
Independent CLI host ────────┘             │
                                          └──> Local resource measurements
```

The IDE will own editing and presentation. The runtime will own execution state and supervision, with no dependency on the IDE, AppKit, or SwiftUI. An independent CLI host will demonstrate reuse.

The native application uses Swift Package Manager and Apple system frameworks, with no third-party dependencies. The existing-file editing/save prototype is verified locally; Save As and representative editing workload measurements remain in Milestone 2. A small Codex feasibility experiment will inform the standalone mock runtime before its APIs are fixed; full integration remains later. Codex is the first planned real integration, using documented interfaces and its existing harness. The interface choice remains provisional.

Resource awareness means measuring local conditions, bounding queues and trace buffers, and applying conservative concurrency policies. It does not guarantee hard memory limits or reveal remote model memory. Logs must minimize sensitive data, and performance claims will require reproducible benchmarks. See [VISION.md](VISION.md) for the full architecture and open questions.

## Current status and roadmap

| Milestone | Intended outcome | Status |
| --- | --- | --- |
| 0 | Documentation and architecture foundation | Complete |
| 1 | Native editor foundation and local file viewing | 1A/1B and the 1C correction complete and published |
| 1A | Native AppKit editor foundation | Complete on the reference Mac; documented local build workaround |
| 1B | Open and view a local UTF-8 code/text file | Complete; 10 reader tests and developer-reported native checks passed |
| 1C | Correct the audit's UTF-8 BOM fidelity defect | Complete and published; build and expanded 14-test reader suite passed |
| 2 | Edit and safely save a file | Existing-file prototype verified; Save As and workload baselines remain |
| 3 | Codex feasibility experiment, then standalone mock runtime and CLI | Planned; 3A/3B |
| 4 | Execution event inspector in the IDE | Planned |
| 5 | First complete coding-change workflow with Codex and basic diff review | Planned |
| 6 | Resource-aware scheduling and benchmarking | Planned |
| 7 | Reliability, documentation, and open-source preparation | Planned |

These milestones are provisional, with no promised delivery dates. [ROADMAP.md](ROADMAP.md) defines acceptance criteria and non-goals; [STATUS.md](STATUS.md) records verified progress, local toolchain details, and limitations.

## Building Vavrio

The package declares macOS 14 or later and Swift 6 language mode, with no third-party dependencies. Compatibility has only been exercised on the reference Mac running macOS 26.5.2; macOS 14 has not been tested.

On a toolchain without the manifest-interface issue, build and launch from the repository root:

```sh
sh Scripts/build.sh
./.build/debug/Vavrio
```

The build helper uses the Apple toolchain selected by `xcrun` and limits Swift Package Manager to two build jobs. It accepts `--help` and rejects unknown options.

After quitting, run `./.build/debug/Vavrio` again from the repository root to reopen the current command-line development build. For normal Finder/Spotlight launching, use the local application bundle described below. A rebuild is needed after source changes, not after every quit.

**Workaround for the reference Mac:** its installed Command Line Tools have incompatible PackageDescription public/private interfaces, so plain `swift build` fails to compile the manifest. Use the explicit local-library option:

```sh
sh Scripts/build.sh --local-manifest-libs
./.build/debug/Vavrio
```

This option refreshes a project-local copy of the selected toolchain's ManifestAPI and PluginAPI directories under ignored `.build/swiftpm-local-libs`, excluding private interfaces from that copy. It uses the documented `SWIFTPM_CUSTOM_LIBS_DIR` override only for the build command. No download, installation, shell-profile edit, or modification to the installed tools occurs. It uses the system shell, `xcrun`, and Apple's supplied `rsync`, with no additional dependencies. Discard generated build output after changing installed toolchains so old copied files do not carry over. The executable runs directly without the build-time override. See [STATUS.md](STATUS.md) for the diagnosed compatibility failure and verification evidence.

## Local macOS application

Vavrio now has a selected minimal dark icon and a local development app bundle. The reference Mac has a verified copy at `/Applications/Vavrio.app`, the developer confirmed opening works and selected the warm off-white mark on a near-black tile. The installed version is 0.2.0 (build 5), using edge-to-edge dark artwork and a larger symbol; the developer confirmed it fills the Dock box correctly. Open **Vavrio** from Applications or search for it in Spotlight; the installed app launches without a terminal or build-time environment override. The running app can be kept in the Dock through its Options menu.

To package the current source using the reference Mac's existing tools:

```sh
sh Scripts/package-app.sh --local-manifest-libs
```

On a healthy toolchain, omit `--local-manifest-libs`. The script calls the existing two-job development build, makes standard/Retina icon sizes from [Assets/VavrioIcon-minimal-dark.png](Assets/VavrioIcon-minimal-dark.png), creates a fresh `Vavrio.app` under ignored `.build/app-packages`, and applies/verifies a local ad-hoc signature. [Resources/Info.plist](Resources/Info.plist) supplies the bundle identity, version, icon name, and macOS 14 minimum. The PNG source and generation prompt are documented in [Assets/README.md](Assets/README.md).

The script prints the exact generated bundle path. To install or refresh it manually, quit Vavrio and use Finder to copy that `Vavrio.app` into Applications, reviewing any replacement prompt. The package script never installs, replaces, or launches an app automatically. Each build goes to a fresh directory so existing bundles are preserved.

The installed app is a snapshot: rebuilding source alone does not update Applications. Run the package command and replace the installed bundle after future code changes. This is a debug development build for local use on the reference Apple Silicon Mac. It is not a Developer ID-signed/notarized distribution, universal binary, or automatic updater; no signing account, downloaded tool, or system security-setting change was needed. macOS 14 remains declared but untested.

## Opening, editing, and saving a file

Use File → Open or Command-O to choose one code/text file. Edit as plain text, use Command-Z / Shift-Command-Z for undo/redo, and choose Save or Command-S to write changes. The title shows the filename and the window indicates unsaved changes. Save/Discard/Cancel protects unsaved edits before replacement, close, or quit. Failed opens/saves retain the current document and edits. Save is explicit; there is no autosave, Save As, new-document command, syntax highlighting, or project browser.

Supported input is a regular UTF-8 file up to **2 MiB (2,097,152 bytes, including any byte-order mark)**. At most one initial UTF-8 BOM is omitted from display and retained for saving; subsequent U+FEFF characters remain text. Existing line endings are retained; newly entered text follows the native text editor's insertion behavior without whole-file newline normalization. Invalid UTF-8 and NUL-containing data are rejected. Symlinks to regular files remain viewable, while special files and folders are rejected. The limit is provisional; near-limit/long-line layout performance remains unmeasured.

Saving initially supports existing local, current-user-owned, single-link regular files with owner read/write permission. It refuses selected symlinks, special permission bits, extended ACLs on the file or immediate parent, unsupported flags, resource-fork/compression metadata, and unavailable or excessive xattrs (256 KiB bound). Ordinary/executable modes, ownership, exact creation time, supported flags, and supported xattrs are checked before/after replacement. An unsupported file can still be viewed and edited for copying elsewhere; its Save control is disabled with a reason.

The writer compares target identity, complete original bytes, metadata, and parent identity against the opened snapshot. It verifies an original copy in private same-volume staging, modifies only staged bytes, rechecks the target, then replaces and verifies the result. Detected external changes refuse Save and retain edits. File coordination and checks cannot prevent an uncooperative process from changing the file between the final check and replacement. There is no atomic compare-and-swap or power-loss durability guarantee. An uncertain outcome keeps edits/recovery information and blocks retry until a fresh open; no automatic rollback or force overwrite occurs.

Filesystem work runs off the main actor, with one document operation at a time. Cancel Open and a logical 10-second timeout reject late load results while retaining the worker slot until synchronous I/O returns. Neither promises interruption of a stalled filesystem call. Edits made while a save runs remain dirty if they differ from the saved snapshot. The app does not watch for external changes; reopen to refresh after preserving any edits you need.

## Verification

The suite uses Swift Testing supplied with the installed tools, with no third-party dependency. After building with the local-library workaround above, run from the repository root:

```sh
SWIFTPM_CUSTOM_LIBS_DIR="$PWD/.build/swiftpm-local-libs" xcrun swift test --jobs 2 --disable-xctest
```

On a healthy toolchain, omit the environment override. The latest run passed **37 tests**, covering reader/encoder fidelity and errors, save/metadata round trips, stale/unsupported targets, preparation failures, uncertain outcomes, cleanup warnings, sentinel preservation, dirty-state byte comparisons, failed opens, late-load cancellation/timeout, and newer edits during saving. An isolated test explicitly demonstrates the remaining final-check/replacement race.

The later build-5 width correction passed an unshown AppKit geometry check at 480/900/1440 points, including constrained horizontal scrolling. The developer confirmed the left margin and first characters remain visible after resizing and sideways trackpad scrolling.

On 2026-10-31 the developer confirmed native Open/Edit/Undo/Redo/Save/reopen and unsaved Cancel-on-quit/Discard-on-open behavior in the installed 0.2.0 app. Inspection of the edited fixture verified its saved `Prototype` text, original UTF-8 BOM, Unicode, and two CRLF endings. Earlier 1B picker/viewing/error checks and 1A scratchpad resource observations remain historical evidence. Native close-button/Save-from-unsaved-dialog/error-path checks, representative workload measurements, crash recovery, and macOS 14 execution have not been newly verified. [STATUS.md](STATUS.md) records the evidence; [ROADMAP.md](ROADMAP.md) defines the remaining full-milestone criteria.

## Exploring the repository

| Document | Purpose |
| --- | --- |
| [VISION.md](VISION.md) | Product goals, architecture boundaries, technical risks, and MVP scope |
| [ROADMAP.md](ROADMAP.md) | Small milestones with learning objectives and verification criteria |
| [STATUS.md](STATUS.md) | Observed progress, environment evidence, and next steps |
| [NEXT_TASK.md](NEXT_TASK.md) | One bounded implementation task, acceptance checks, and continuation prompt |
| [AGENTS.md](AGENTS.md) | Repository instructions for AI-assisted development |

## Development workflow

The developer uses Astra for planning and difficult design decisions, then Sol for implementation. [AGENTS.md](AGENTS.md) records that workflow; [NEXT_TASK.md](NEXT_TASK.md) carries the current task across sessions. These are working preferences, not model capability or subscription guarantees. The developer owns scope, reviews, and native interaction checks; generated code still needs reproducible verification. Keep model usage focused by implementing one reviewed task at a time and bringing concrete unresolved decisions back to planning.

## Get involved

Vavrio is being developed in public as a practical study of Swift, native macOS development, and AI infrastructure. Feedback on the design, resource constraints, and roadmap is welcome. Keep proposed changes small and aligned with the current milestone. Changes should have clear scope, reproducible verification, and documented limitations.

## License

A project license has not yet been selected. A LICENSE file will be added after an explicit decision.
