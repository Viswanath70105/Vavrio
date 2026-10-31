# Vavrio — Provisional Roadmap

These milestones describe a learning and implementation sequence, not delivery promises or deadlines. VISION.md defines product intent and boundaries; STATUS.md records verified progress. Starting a new implementation milestone requires developer approval of its concrete scope. Revise this sequence when evidence justifies a change.

Every milestone ends with an engineering summary covering the result, choices, verification, limitations, and what the developer learned. Use meaningful automated tests for behavior and manual checks for native interaction; do not treat compilation alone as feature verification.

The 2026-10-30 planning update prioritizes one complete, inspectable coding-change workflow on the reference Mac. Each milestone may be divided into smaller approved tasks; NEXT_TASK.md carries only the current task. The developer's preferred workflow is Astra for planning/design decisions and Sol for implementation. This revision is a plan, not approval to implement all of it.

Reliability checks belong with the feature they exercise. Test file failures during document work, stale approvals and cancellation races during runtime work, and output floods during event delivery. Collect resource baselines as workloads become available. Milestone 7 consolidates release evidence rather than starting correctness work. Seek a simple independent macOS build/test check before broad contributor onboarding; do not install local tools or configure external CI without the necessary authorization.

## Milestone 0 — Repository documentation and architecture foundation

**Goal:** Establish the working vision, dependency boundaries, mentorship protocol, provisional milestones, and an honest progress record.

**Learning objectives:** Understand the difference between a product vision, architecture constraint, implementation plan, and verified capability; learn how repository instructions support continuity.

**Acceptance criteria:**

- The original foundation deliverables are AGENTS.md, professor_ara.md, VISION.md, ROADMAP.md, and STATUS.md. Subsequent publication preparation may add repository-facing files without changing this milestone’s original scope.
- AGENTS.md links to the correct documents and includes the session mentorship instruction.
- Vision, roadmap, status, and mentor protocol agree about scope, permissions, and architecture.
- Future capabilities are distinguished from existing work, and toolchain build compatibility remains marked unverified.
- The original documentation-only milestone creates no application source or Package.swift and performs no Git initialization, installation, or environment change. Git preparation is authorized separately below.

**Non-goals:** Implementing or running an application, runtime, or integration. The developer subsequently selected Vavrio as the official name.

### Publication preparation — authorized follow-up to Milestone 0

Update the documentation to Vavrio, add a README and Swift/macOS .gitignore, preserve the five foundation documents, review the publication contents, initialize Git, create an initial local commit, and configure the verified GitHub remote. Verify repository hygiene and stop for explicit approval before pushing. This follow-up does not authorize Milestone 1 or software installation. No publication is complete until a push succeeds.

## Milestone 1 — Native editor foundation and local file viewing

**Goal:** Open an existing code/text file from the developer's Mac and read it inside Vavrio, using Swift and the installed tools.

**Completion rule:** Both 1A and 1B must be implemented and verified before Milestone 1 is complete. The original scratchpad scope is retained as 1A; its existing verification remains valid. The developer approved this roadmap revision on 2026-10-29. STATUS.md records implementation progress separately from the agreed scope.

### Milestone 1A — Native AppKit editor foundation

**Goal:** Build and launch the smallest native scratchpad window.

**Learning objectives:** Swift package structure, macOS application lifecycle, the event loop, AppKit views, text configuration, and build versus runtime verification.

**Acceptance criteria:**

- An approved Swift package builds for Apple Silicon using Swift Package Manager, with no third-party dependencies.
- A native window contains a scrollable plain-text, monospaced NSTextView.
- Keyboard focus, typing, selection, copy/paste, undo/redo, scrolling, and normal quit behavior are manually verified.
- The deployment target is explicitly selected and recorded. Any compatibility failure is documented before an installation or tool update is proposed.
- Record a reproducible initial idle CPU/memory observation, including measurement limitations; do not declare a performance victory from one sample.

**Non-goals for 1A:** File opening/saving, syntax highlighting, project navigation, AI calls, runtime scaffolding, app distribution, or a background service. Git publication preparation is handled separately and does not expand this implementation scope.

### Milestone 1B — Open and view a local file

**Goal:** Choose one existing UTF-8 code/text file on the Mac and read its contents in Vavrio.

**Learning objectives:** Native file selection, file URLs, explicit text decoding, read failures, file identity in the UI, and read-only text interaction.

**Acceptance criteria:**

- File → Open and Command-O present a native macOS file picker for one existing file.
- A supported UTF-8 code/text file is displayed as monospaced plain text, with its filename visible. Unicode content and paths with spaces are covered by verification.
- The initial viewer supports regular files up to 2 MiB, including any UTF-8 byte-order mark. Invalid UTF-8, NUL-containing data, special files, and larger files produce a visible error. This is an explicit scope limit, not a performance guarantee.
- Opened file contents are read-only: scrolling, selection, and copying work; editing and saving those contents are deferred to Milestone 2. Opening/viewing does not write to the source file.
- Cancelling the picker preserves the current view. Read or unsupported-encoding failures are visible and preserve any file already displayed; decoding must not silently replace invalid input with garbled text.
- Meaningful file-reading checks cover supported content, failure behavior, and unchanged source-file contents using temporary fixtures. Manually verify the native picker, filename display, reading, scrolling, selection/copying, cancellation, and error presentation.
- The developer demonstrates the intended end-to-end task: choose an existing code file on their Mac and read it inside Vavrio. Record supported-file limitations honestly; the 1A scratchpad resource observation does not establish file-loading performance.

**Non-goals for 1B:** Editing or saving opened files, syntax highlighting, a folder/workspace browser, multiple documents or tabs, large-file optimization, AI calls, runtime scaffolding, app distribution, or a background service.

## Milestone 1C — Audit correction: UTF-8 BOM fidelity

**Goal:** Correct the reproduced double-BOM removal without expanding the read-only viewer. This is a follow-up to completed 1A/1B.

**Status:** Implemented and verified locally on 2026-10-30 after explicit developer authorization. The regression failed before the fix with three expected byte-comparison issues; the final suite passes all 14 tests and the documented build succeeds. Strict decoding uses the macOS 14-compatible `String(validatingCString:)` API because `String(validating:as:)` requires macOS 15. STATUS.md records the evidence. No fresh UI check was performed. The subsequent developer-authorized publication pushed the correction as `8fcf7a1` and independently verified the remote hash; STATUS.md records that evidence. Milestone 2A serialization and the later existing-file prototype are verified locally; NEXT_TASK.md carries the next bounded Save As proposal.

**Learning objectives:** Strict decoding, invisible Unicode characters, byte-level regression tests, and distinguishing displayed text from file bytes.

**Acceptance criteria:**

- Reproduce the failure with two leading BOM sequences; remove at most the first sequence and preserve the remaining text exactly.
- Cover zero, one, and repeated BOMs, BOM-only data, an interior U+FEFF, and malformed UTF-8 after a BOM. Confirm unchanged source bytes and retain the existing size/type/encoding checks.
- The reader suite and documented build pass; update known-issue status only after verification. STATUS.md records the completed bounded correction; NEXT_TASK.md carries the next proposed task.

**Non-goals:** Saving, UI changes, load cancellation, performance optimization, runtime work, installations, or publication.

## Milestone 2 — Edit and safely save a file

**Goal:** Extend the single-file viewer from 1B to reliably edit and save one UTF-8 plain-text file through native interactions.

**Learning objectives:** File URLs, encodings, document state, errors, unsaved edits, and safe persistence.

**Acceptance criteria:**

- Enable editing, Save, and Save As for a single UTF-8 file, including Unicode content and paths with spaces. Retain and recheck the file-opening/viewing behavior delivered in 1B.
- Unsaved changes trigger a consistent save/discard/cancel decision when opening a replacement, closing, or quitting. Cancelled dialogs and failed saves preserve the active document and its dirty state.
- Read, encoding, and write failures are visible; failed saves do not mark the document clean or intentionally truncate the original file.
- Persistence uses an appropriate safe replacement strategy. Validate round-trip content and failure behavior with temporary test files, plus manual checks of native dialogs.
- Decide and document BOM preservation, newline handling for existing and newly entered text, symlink targets, executable permissions/relevant metadata, and external file changes before implementing writes. Evaluate NSDocument against a small explicit document model; keep document persistence separate from agent supervision.
- An external modification detected before a save produces a visible conflict decision. Define the detection method and its race limitations; safe replacement alone does not establish conflict prevention. If editing continues during an asynchronous save, completion must not mark newer edits clean.
- Define loading state and a bounded cancellation/recovery policy; do not promise that Swift task cancellation interrupts a synchronous file operation. Tests cover state transitions that can be isolated; manual checks cover dialogs and native behavior.
- Record file-loading/editing baselines for representative source, near-limit long lines, many short lines, and complex Unicode. Document responsiveness limitations and preserve a justified supported-file bound; do not require a renderer rewrite without measurements.

**Non-goals:** A full workspace browser, multi-document tabs, large-file optimization, language tooling, or agent patch application.

### Milestone 2 increments — updated 2026-10-31

The developer authorized 2A, then the 2B investigation, then requested a working Open/Edit/Save prototype and explicitly chose a small single-file session. This extended the approved scope to the guarded writer and existing-file native editing lifecycle. The installed 0.2.0 (build 5) app passes 37 automated tests and the developer's native Open/Edit/Undo/Redo/Save/reopen and unsaved Cancel/Discard checks. Today's prototype goal is met; full Milestone 2 remains incomplete.

1. **2A — Byte-faithful text serialization: complete and published in `e8e95b9`.** Original bytes/BOM retention, exact in-memory round trips, and edited-text validation remain covered. The encoder rejects NUL, oversized bytes, and ambiguous leading U+FEFF without a recorded BOM.
2. **2B — Guarded existing-file replacement: implemented and locally verified.** A 22-scenario investigation informed save baselines, conservative metadata/ACL eligibility, private verified-copy staging, target rechecks, exact post-verification, and uncertain/cleanup outcomes. The implementation uses `.usingNewMetadataOnly` on a metadata-verified original copy because default replacement rounded creation-time nanoseconds; STATUS.md records the observed correction. A controlled test demonstrates the residual final-check/replacement race. Unsupported files remain viewable. No absolute concurrent-writer or power-loss guarantee is claimed.
3. **2C — Native edit/save lifecycle: existing-file prototype verified; remaining criteria pending.** The developer approved DocumentSession instead of NSDocument for the prototype. Editing, undo/redo, Save, dirty state, Save/Discard/Cancel, logical load cancellation/timeout, and stale completion protection are implemented. Native core-loop and Cancel/Discard checks passed; close-button/Save-from-unsaved-dialog/error-path checks and representative source/long-line/many-line/Unicode workload baselines remain. Save As to a new destination is the next proposed bounded task in NEXT_TASK.md; existing-destination overwrite requires a later decision. NSDocument should be reconsidered before broader document features.

These increments do not replace the full acceptance criteria above. The prototype changes are local and installed; no commit/push is authorized from completion. Further implementation needs its own approval.

### Local macOS packaging interlude — developer-requested 2026-10-30

Before 2B, the developer requested an original icon and a local Applications installation. A repeatable package script now builds a fresh ad-hoc-signed Vavrio.app using the existing Swift/Apple tools, with bundle metadata and a generated ICNS. The verified bundle was installed in /Applications and launched; the developer confirmed it works, then selected the dark minimal icon and authorized removing the other project icon drafts. The selected logo is installed; a subsequent Dock screenshot prompted edge-to-edge artwork and a larger symbol, installed in build 3 and developer-confirmed to fill the Dock box correctly. At that point 2A remained intact and 2B had not begun. The subsequent 0.2.0 prototype refresh is recorded separately in STATUS.md. The packaging interlude itself did not add editing/saving, automatic updates, distribution signing/notarization, a developer account, or an external release.

## Milestone 3 — Codex feasibility, standalone runtime, and CLI host

### Milestone 3A — Constrain the design with a real protocol experiment

**Goal:** Check the first adapter's assumptions before freezing runtime APIs or building the inspector.

**Learning objectives:** Process/protocol boundaries, compatibility, authentication prerequisites, and observed versus assumed execution guarantees.

**Acceptance criteria:**

- Recheck official interfaces and the chosen executable/version. Document experimental status, prerequisites, and installation/access limits. An app-bundled alpha CLI found by the audit is not a portable distribution contract.
- First validate a minimal local protocol handshake and available schema. After authorization for any live model usage, run a bounded task in a disposable workspace and observe lifecycle events, actual approval policy, rejection, interruption, and process exit.
- Record which operations can be gated and which event/data fields are unavailable. If required review-before-apply behavior cannot be enforced directly, assess an isolated workspace plus reviewed patch application; never silently downgrade the product guarantee.
- Keep only a small experiment and sanitized protocol fixtures needed by the next task. Record unresolved outcomes as blockers for the dependent design, not as successful integration. Do not introduce a permanent daemon or another language runtime by default.

**Non-goals:** A finished adapter, paid calls without authorization, credentials in fixtures, new installation without approval, or production-readiness claims.

### Milestone 3B — Deterministic mock runtime and independent CLI

**Goal:** Establish a reusable Swift runtime package that works without the IDE or a real agent.

**Learning objectives:** Package boundaries, lifecycle state machines, asynchronous event delivery, cancellation, deterministic testing, and separation of host policy from presentation.

**Acceptance criteria:**

- A separate runtime package has no IDE, AppKit, or SwiftUI dependency. An independent CLI host runs deterministic mock tasks using it.
- Tests cover successful completion, failure, cancellation races, event identity/order, approval pending/accept/decline, duplicate responses, and stale approvals after cancellation or operation changes. No mock action runs before its required approval.
- Start with one active task and a bounded pending queue. Bound event/output buffering and report truncation or overflow honestly; output pressure must not lose authoritative completion or approval state.
- Distinguish stop requested, termination confirmed, and uncertain/disconnected outcomes. Define ownership and cleanup of launched work; a UI disappearing is not proof that its task stopped.
- The CLI can show task events and respond to approvals without UI code, credentials, network calls, or a real agent installation.
- Document observable event meanings and lifecycle guarantees. Use transient traces initially unless a bounded, security-conscious persistence design is explicitly approved.

**Non-goals:** Real Codex integration, parallel agents, a universal adapter framework, a daemon, durable distributed workflows, or hard resource limits.

## Milestone 4 — Execution event inspector in the IDE

**Goal:** Present the same mock runtime events inside the native app.

**Learning objectives:** UI updates on the appropriate executor, asynchronous state presentation, bounded views, and separating event evidence from chat text.

**Acceptance criteria:**

- Start and cancel a mock task from the IDE; inspect ordered lifecycle and tool events with identifiable status and relevant details.
- Present mock approval requests, send scoped decisions through the runtime, and clear stale or cancelled prompts.
- Editing remains responsive during a controlled burst of mock events. Bound retained/displayed output and identify incomplete or truncated traces. Record event-burst and host-memory measurements, including the workload and limits.
- Confirm that the CLI remains independently usable and that task state is not owned solely by the inspector UI.

**Non-goals:** Private model reasoning, real AI execution, a polished diff editor, project navigation, or persistent telemetry collection.

## Milestone 5 — First complete coding-change workflow

**Goal:** Integrate the first real adapter and demonstrate one useful change from request to reviewed result, while preserving the runtime's independent use.

**Learning objectives:** Documented process/protocol integration, version compatibility, authentication boundaries, capability mapping, and enforceable approvals.

**Acceptance criteria:**

- Review current official interfaces and validate the chosen one against the installed Codex version. Record the interface, prerequisites, and compatibility assumptions; reuse Codex's harness.
- Run a bounded task in a disposable test project from the CLI and IDE. Map the available lifecycle, tool, result, error, and cancellation information without inventing missing events.
- Select and display an explicit workspace root. Provide a basic changed-files list and readable diff so a multi-file agent change can be reviewed even though the editor remains single-document.
- Validate approvals against actual Codex policy and execution behavior. Required actions remain blocked until an authorized decision; rejection and interruption have documented outcomes.
- Demonstrate the chosen review-before-apply workflow for proposed file changes. If the interface cannot enforce it directly, evaluate isolation and patch application before claiming support; handle unsaved-document conflicts explicitly.
- Handle a missing executable, authentication failure, malformed/unrecognized events, and process exit without leaking secrets or leaving misleading active state.
- Review what our traces and upstream Codex logs retain. Document gaps and data handling. Keep deterministic mock tests for repeatable coverage.
- Demonstrate fixing a deliberately failing test, reviewing and accepting the resulting change, and inspecting verification output. Separately demonstrate rejecting a change and preserving an unsaved local edit during a conflict. Record a reproducible task recipe and whole-workflow resource observations; do not claim every failure outcome from one happy-path demo.

**Non-goals:** Reimplementing the agent harness, undocumented protocol dependence, multiple real providers, private reasoning access, or unrestricted autonomous actions. Any necessary software installation requires separate approval.

## Milestone 6 — Resource-aware scheduling and benchmarking

**Goal:** Use reliable local measurements to guide conservative task admission and concurrency.

**Learning objectives:** Process accounting, system memory pressure, sampling limits, queue policies, and reproducible performance experiments.

**Acceptance criteria:**

- Label each available measurement by source and scope; represent unavailable process-tree or remote-inference information as unavailable.
- Establish configurable task concurrency and bounded queue policies, initially defaulting to one active task. Test policies using deterministic injected resource samples.
- Demonstrate a documented policy for deferring new work under resource pressure. Do not depend on unsupported pause/resume behavior or claim hard memory enforcement.
- Record reproducible idle, active-task, and event-burst workloads on the reference machine, with versions, configuration, measured overhead, and limitations.
- Derive initial budgets from evidence and report unsuccessful results as well as successful ones. Separate host, child-process, and system observations where possible.

**Non-goals:** Kernel-enforced memory quotas, remote model-memory measurement, local model hosting, distributed scheduling, or automatic multi-agent swarms.

## Milestone 7 — Reliability, documentation, and open-source preparation

**Goal:** Make the implemented scope understandable, recoverable where designed, and suitable for review by other developers.

**Learning objectives:** Failure-oriented testing, compatibility documentation, security review, licensing decisions, and release discipline.

**Acceptance criteria:**

- Recheck process crashes, cancellation races, stale approvals, file conflicts, output floods, and sensitive-log handling across the integrated product; preserve the component tests introduced earlier and document supported recovery behavior.
- Document setup, build, test, CLI use, package APIs, architecture, and known limitations with commands verified against the supported environment.
- Decide the initial packaging, signing, and supported macOS policy through a scoped plan. Reassess the sandbox strategy and permission boundaries.
- Review dependencies/licenses and credential/trace handling before selecting a project license or preparing a public release.
- Confirm an independent consumer can build and exercise the runtime without the IDE, and report benchmark conditions honestly.
- Prepare a reproducible demo and a small pilot targeting three independent developers. Record task completion, points of confusion, setup friction, and voluntary repeat use. Use that evidence to choose the next feature; neither code generation nor a finished roadmap establishes usefulness or demand.

**Non-goals:** Guaranteed security, feature parity with mature IDEs, cloud services, or automatic publication. Public repository creation, publication, and release actions require explicit authorization.
