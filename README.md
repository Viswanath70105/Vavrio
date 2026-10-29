# Vavrio

**Room to code. Clarity to build.**

Vavrio is a student-led project to build a lightweight, native macOS IDE with an independently reusable Swift runtime for AI coding agents. The goal is to keep development comfortable on limited-memory Macs while making agent actions visible and reviewable.

**Status: Milestone 1 is complete: both 1A and 1B are verified on the reference Mac.** You can choose an existing supported UTF-8 code/text file from your Mac, see its filename and read-only contents, and scroll, select, or copy. All 10 file-reader tests pass; the developer manually verified native opening/viewing, read-only behavior, cancellation, and an invalid-UTF-8 error preserving the existing view. The build uses the documented no-download workaround. [STATUS.md](STATUS.md) records the evidence and the earlier 1A idle observation. There is no file editing/saving, agent runtime, CLI host, or Codex integration yet.

## Why Vavrio?

Your editor should leave room for your browser, documentation, and other tools. AI assistance should let you inspect the work happening in your project and stay in control of consequential actions.

Vavrio is being designed around a 2020 Apple M1 MacBook Pro with 8 GB unified memory. This is a design constraint, not a performance claim. The two planned products are:

- **Native IDE:** text editing, file management, project navigation, agent controls, and an execution inspector.
- **Independent runtime:** task lifecycle, structured events, tool traces, approval state, and resource-aware scheduling, usable by a CLI or another application.

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

The native application uses Swift Package Manager and Apple system frameworks, with no third-party dependencies. Milestone 1B provides read-only local file viewing; Milestone 2 will add editing and safe saving of those files. The runtime starts later with deterministic mock tasks. Codex is the first planned real integration, using its documented interfaces and existing harness. The interface choice remains provisional.

Resource awareness means measuring local conditions, bounding queues and trace buffers, and applying conservative concurrency policies. It does not guarantee hard memory limits or reveal remote model memory. Logs must minimize sensitive data, and performance claims will require reproducible benchmarks. See [VISION.md](VISION.md) for the full architecture and open questions.

## Current status and roadmap

| Milestone | Intended outcome | Status |
| --- | --- | --- |
| 0 | Documentation and architecture foundation | Complete |
| 1 | Native editor foundation and local file viewing | Complete on the reference Mac; both increments verified |
| 1A | Native AppKit editor foundation | Complete on the reference Mac; documented local build workaround |
| 1B | Open and view a local UTF-8 code/text file | Complete; 10 reader tests and developer-reported native checks passed |
| 2 | Edit and safely save a file | Planned |
| 3 | Standalone runtime, deterministic mock tasks, and CLI host | Planned |
| 4 | Execution event inspector in the IDE | Planned |
| 5 | Real Codex integration | Planned |
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

After quitting, run `./.build/debug/Vavrio` again from the repository root to reopen the current build. A rebuild is needed after source changes, not after every quit. This development executable is not installed in Applications.

**Workaround for the reference Mac:** its installed Command Line Tools have incompatible PackageDescription public/private interfaces, so plain `swift build` fails to compile the manifest. Use the explicit local-library option:

```sh
sh Scripts/build.sh --local-manifest-libs
./.build/debug/Vavrio
```

This option refreshes a project-local copy of the selected toolchain's ManifestAPI and PluginAPI directories under ignored `.build/swiftpm-local-libs`, excluding private interfaces from that copy. It uses the documented `SWIFTPM_CUSTOM_LIBS_DIR` override only for the build command. No download, installation, shell-profile edit, or modification to the installed tools occurs. It uses the system shell, `xcrun`, and Apple's supplied `rsync`, with no additional dependencies. Discard generated build output after changing installed toolchains so old copied files do not carry over. The executable runs directly without the build-time override. See [STATUS.md](STATUS.md) for the diagnosed compatibility failure and verification evidence.

## Viewing a file

Use File → Open or Command-O to choose one code/text file. The window title shows the filename and **Read Only**. Scroll, select, and copy normally; typing, pasting, and saving are unavailable. Cancelling Open or encountering a read/encoding error preserves the current file view. There is no syntax highlighting or project browser.

Supported input is a regular UTF-8 file up to **2 MiB (2,097,152 bytes, including any byte-order mark)**. A leading UTF-8 byte-order mark is omitted from display; line endings are preserved in the decoded string. Invalid UTF-8 and NUL-containing data are rejected with an error rather than converted. Symlinks to regular files are supported. Special files and folders are rejected. The limit is a provisional scope choice, not a measured responsiveness or memory guarantee; long-line and large-file layout performance is unverified.

The reader uses a read-only descriptor, checks the actual opened file type and size, and bounds reads even if the file grows. Reading runs off the main actor; one Open request is active at a time. The app reads a file once and does not watch for external changes. Reopen a file to refresh it; changes made by another process during reading are not coordinated. The app does not write to the opened file. This remains an unbundled development executable, with editing/saving deferred to Milestone 2 and distribution undecided.

## Verification

The file-reader suite uses Swift Testing supplied with the installed tools, with no third-party dependency. After building with the local-library workaround above, run from the repository root:

```sh
SWIFTPM_CUSTOM_LIBS_DIR="$PWD/.build/swiftpm-local-libs" xcrun swift test --jobs 2 --disable-xctest
```

On a healthy toolchain, omit the environment override. The tests cover Unicode/path handling, line endings, empty files, byte-order marks, invalid text, the exact size boundary, missing and special files, symlinks, and unchanged source bytes. Native picker, read-only selection/copying, scrolling, cancellation/error preservation, and quitting require manual checks; compilation and reader tests alone do not verify them.

The developer reported the 1B native picker, existing-code-file display, filename, scrolling, selection/copying, read-only behavior, cancellation preservation, and invalid-UTF-8 alert/preservation checks passed on 2026-10-29. They also closed the app and its process exited 0. The 2026-10-28 temporary scratchpad's editable-text checks and resource samples remain historical 1A evidence. The current 1B viewer is intentionally read-only; its file-loading/layout performance has not been benchmarked. [STATUS.md](STATUS.md) records the evidence and limitations; [ROADMAP.md](ROADMAP.md) defines milestone acceptance criteria.

## Exploring the repository

| Document | Purpose |
| --- | --- |
| [VISION.md](VISION.md) | Product goals, architecture boundaries, technical risks, and MVP scope |
| [ROADMAP.md](ROADMAP.md) | Small milestones with learning objectives and verification criteria |
| [STATUS.md](STATUS.md) | Observed progress, environment evidence, and next steps |
| [AGENTS.md](AGENTS.md) | Repository instructions for AI-assisted development |
| [professor_ara.md](professor_ara.md) | The project's engineering mentorship and communication protocol |

## Get involved

Vavrio is being developed in public as a practical study of Swift, native macOS development, and AI infrastructure. Feedback on the design, resource constraints, and roadmap is welcome. Keep proposed changes small and aligned with the current milestone. Professor Ara's mentorship protocol supports learning through explanations, trade-offs, and verifiable results.

## License

A project license has not yet been selected. A LICENSE file will be added after an explicit decision.
