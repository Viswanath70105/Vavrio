# Vavrio

**Room to code. Clarity to build.**

Vavrio is a student-led, AI-assisted project to build a lightweight, native macOS IDE with an independently reusable Swift runtime for AI coding agents. Its first product goal is one inspectable coding-change workflow: understand what ran, review what changed, preserve your own edits, and verify the result on a limited-memory Mac.

**Status: Milestones 1A/1B and the 1C BOM fidelity correction are verified on the reference Mac.** You can choose an existing supported UTF-8 code/text file from your Mac, see its filename and read-only contents, and scroll, select, or copy. All 21 reader/encoder tests pass; the developer previously manually verified native opening/viewing, read-only behavior, cancellation, and an invalid-UTF-8 error preserving the existing view for 1B. The build uses the documented no-download workaround. [STATUS.md](STATUS.md) records the evidence and the earlier 1A idle observation. There is no file editing/saving, agent runtime, CLI host, or Codex integration yet.

**Audit correction verified and published in 1C:** opening a file now omits at most one initial UTF-8 BOM and preserves subsequent U+FEFF characters. Regression tests cover repeated BOMs, BOM-only files, interior U+FEFF, invalid UTF-8, and unchanged source bytes. This correction is published in [commit 8fcf7a1](https://github.com/Viswanath70105/Vavrio/commit/8fcf7a1af762f67e5916c2735882ae564cc4d786). Milestone 2A is also complete and published in [e8e95b9](https://github.com/Viswanath70105/Vavrio/commit/e8e95b98b8c25ac5d0dfdfc8adc10f425fa59545) alongside the app-packaging source: the reader retains original bytes/BOM information, and an in-memory encoder passes byte-faithful round-trip and error checks. [NEXT_TASK.md](NEXT_TASK.md) proposes the next persistence investigation; editing and file writes remain unimplemented.

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

The native application uses Swift Package Manager and Apple system frameworks, with no third-party dependencies. The 1C reader correction is verified locally; Milestone 2 will add editing and safe saving. A small Codex feasibility experiment will inform the standalone mock runtime before its APIs are fixed; full integration remains later. Codex is the first planned real integration, using documented interfaces and its existing harness. The interface choice remains provisional.

Resource awareness means measuring local conditions, bounding queues and trace buffers, and applying conservative concurrency policies. It does not guarantee hard memory limits or reveal remote model memory. Logs must minimize sensitive data, and performance claims will require reproducible benchmarks. See [VISION.md](VISION.md) for the full architecture and open questions.

## Current status and roadmap

| Milestone | Intended outcome | Status |
| --- | --- | --- |
| 0 | Documentation and architecture foundation | Complete |
| 1 | Native editor foundation and local file viewing | 1A/1B and the 1C correction complete and published |
| 1A | Native AppKit editor foundation | Complete on the reference Mac; documented local build workaround |
| 1B | Open and view a local UTF-8 code/text file | Complete; 10 reader tests and developer-reported native checks passed |
| 1C | Correct the audit's UTF-8 BOM fidelity defect | Complete and published; build and expanded 14-test reader suite passed |
| 2 | Edit and safely save a file | In progress; 2A serialization verified locally; file writes/native editing unimplemented |
| 3 | Codex feasibility experiment, then standalone mock runtime and CLI | Planned; 3A/3B |
| 4 | Execution event inspector in the IDE | Planned |
| 5 | First complete coding-change workflow with Codex and basic diff review | Planned |
| 6 | Resource-aware scheduling and benchmarking | Planned |
| 7 | Reliability, documentation, and open-source preparation | Planned |

These milestones are provisional, with no promised delivery dates. [ROADMAP.md](ROADMAP.md) defines acceptance criteria and non-goals; [STATUS.md](STATUS.md) records verified progress, local toolchain details, and limitations.

## Building the viewer

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

Vavrio now has a selected minimal dark icon and a local development app bundle. The reference Mac has a verified copy at `/Applications/Vavrio.app`, the developer confirmed opening works and selected the warm off-white mark on a near-black tile. The installed version is 0.1.0 (build 3), using edge-to-edge dark artwork and a larger symbol; the developer confirmed it fills the Dock box correctly. Open **Vavrio** from Applications or search for it in Spotlight; the installed app launches without a terminal or build-time environment override. The running app can be kept in the Dock through its Options menu.

To package the current source using the reference Mac's existing tools:

```sh
sh Scripts/package-app.sh --local-manifest-libs
```

On a healthy toolchain, omit `--local-manifest-libs`. The script calls the existing two-job development build, makes standard/Retina icon sizes from [Assets/VavrioIcon-minimal-dark.png](Assets/VavrioIcon-minimal-dark.png), creates a fresh `Vavrio.app` under ignored `.build/app-packages`, and applies/verifies a local ad-hoc signature. [Resources/Info.plist](Resources/Info.plist) supplies the bundle identity, version, icon name, and macOS 14 minimum. The PNG source and generation prompt are documented in [Assets/README.md](Assets/README.md).

The script prints the exact generated bundle path. To install or refresh it manually, quit Vavrio and use Finder to copy that `Vavrio.app` into Applications, reviewing any replacement prompt. The package script never installs, replaces, or launches an app automatically. Each build goes to a fresh directory so existing bundles are preserved.

The installed app is a snapshot: rebuilding source alone does not update Applications. Run the package command and replace the installed bundle after future code changes. This is a debug development build for local use on the reference Apple Silicon Mac. It is not a Developer ID-signed/notarized distribution, universal binary, or automatic updater; no signing account, downloaded tool, or system security-setting change was needed. macOS 14 remains declared but untested.

## Viewing a file

Use File → Open or Command-O to choose one code/text file. The window title shows the filename and **Read Only**. Scroll, select, and copy normally; typing, pasting, and saving are unavailable. Cancelling Open or encountering a read/encoding error preserves the current file view. There is no syntax highlighting or project browser.

Supported input is a regular UTF-8 file up to **2 MiB (2,097,152 bytes, including any byte-order mark)**. At most one initial UTF-8 byte-order mark is omitted from display; subsequent U+FEFF characters are preserved. Line endings are preserved in the decoded string. Invalid UTF-8 and NUL-containing data are rejected with an error rather than converted. Symlinks to regular files are supported. Special files and folders are rejected. The limit is a provisional scope choice, not a measured responsiveness or memory guarantee; long-line and large-file layout performance is unverified.

The reader uses a read-only descriptor, checks the actual opened file type and size, and bounds reads even if the file grows. Reading runs off the main actor; one Open request is active at a time. The app reads a file once and does not watch for external changes. Reopen a file to refresh it; changes made by another process during reading are not coordinated. The app does not write to the opened file. Both the raw development executable and the locally installed app bundle use this same read-only behavior, with editing/saving deferred to later Milestone 2 increments and distribution undecided.

## Verification

The file-reader suite uses Swift Testing supplied with the installed tools, with no third-party dependency. After building with the local-library workaround above, run from the repository root:

```sh
SWIFTPM_CUSTOM_LIBS_DIR="$PWD/.build/swiftpm-local-libs" xcrun swift test --jobs 2 --disable-xctest
```

On a healthy toolchain, omit the environment override. The reader/encoder tests cover Unicode/path handling, line endings, empty files, repeated byte-order marks, invalid text, byte-faithful in-memory round trips, snapshot preservation, serialization errors, exact UTF-8 size boundaries, missing and special files, symlinks, and unchanged source bytes. Native picker, read-only selection/copying, scrolling, cancellation/error preservation, and quitting require manual checks; compilation and reader tests alone do not verify them.

The developer reported the 1B native picker, existing-code-file display, filename, scrolling, selection/copying, read-only behavior, cancellation preservation, and invalid-UTF-8 alert/preservation checks passed on 2026-10-29. They also closed the app and its process exited 0. The 2026-10-28 temporary scratchpad's editable-text checks and resource samples remain historical 1A evidence. The current 1B viewer is intentionally read-only; its file-loading/layout performance has not been benchmarked. [STATUS.md](STATUS.md) records the evidence and limitations; [ROADMAP.md](ROADMAP.md) defines milestone acceptance criteria.

## Exploring the repository

| Document | Purpose |
| --- | --- |
| [VISION.md](VISION.md) | Product goals, architecture boundaries, technical risks, and MVP scope |
| [ROADMAP.md](ROADMAP.md) | Small milestones with learning objectives and verification criteria |
| [STATUS.md](STATUS.md) | Observed progress, environment evidence, and next steps |
| [NEXT_TASK.md](NEXT_TASK.md) | One bounded implementation task, acceptance checks, and continuation prompt |
| [AGENTS.md](AGENTS.md) | Repository instructions for AI-assisted development |
| [professor_ara.md](professor_ara.md) | The project's engineering mentorship and communication protocol |

## Development workflow

The developer uses Astra for planning and difficult design decisions, then Sol for implementation. [AGENTS.md](AGENTS.md) records that workflow; [NEXT_TASK.md](NEXT_TASK.md) carries the current task across sessions. These are working preferences, not model capability or subscription guarantees. The developer owns scope, reviews, and native interaction checks; generated code still needs reproducible verification. Keep model usage focused by implementing one reviewed task at a time and bringing concrete unresolved decisions back to planning.

## Get involved

Vavrio is being developed in public as a practical study of Swift, native macOS development, and AI infrastructure. Feedback on the design, resource constraints, and roadmap is welcome. Keep proposed changes small and aligned with the current milestone. Professor Ara's mentorship protocol supports learning through explanations, trade-offs, and verifiable results.

## License

A project license has not yet been selected. A LICENSE file will be added after an explicit decision.
