# Vavrio — Provisional Roadmap

These milestones describe a learning and implementation sequence, not delivery promises or deadlines. VISION.md defines product intent and boundaries; STATUS.md records verified progress. Starting a new implementation milestone requires developer approval of its concrete scope. Revise this sequence when evidence justifies a change.

Every milestone ends with an engineering summary covering the result, choices, verification, limitations, and what the developer learned. Use meaningful automated tests for behavior and manual checks for native interaction; do not treat compilation alone as feature verification.

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

## Milestone 1 — Native AppKit scratchpad

**Goal:** Build and launch the smallest native editor window using Swift and the installed tools.

**Learning objectives:** Swift package structure, macOS application lifecycle, the event loop, AppKit views, text configuration, and build versus runtime verification.

**Acceptance criteria:**

- An approved Swift package builds for Apple Silicon using Swift Package Manager, with no third-party dependencies.
- A native window contains a scrollable plain-text, monospaced NSTextView.
- Keyboard focus, typing, selection, copy/paste, undo/redo, scrolling, and normal quit behavior are manually verified.
- The deployment target is explicitly selected and recorded. Any compatibility failure is documented before an installation or tool update is proposed.
- Record a reproducible initial idle CPU/memory observation, including measurement limitations; do not declare a performance victory from one sample.

**Non-goals:** File opening/saving, syntax highlighting, project navigation, AI calls, runtime scaffolding, app distribution, or a background service. Git publication preparation is handled separately and does not expand this implementation scope.

## Milestone 2 — Basic file opening, editing, and saving

**Goal:** Reliably edit one UTF-8 plain-text file through native open/save interactions.

**Learning objectives:** File URLs, encodings, document state, errors, unsaved edits, and safe persistence.

**Acceptance criteria:**

- Open, edit, Save, and Save As work for a single UTF-8 file, including Unicode content and paths with spaces.
- Unsaved changes trigger an appropriate save/discard/cancel decision when replacing the document or closing it.
- Read, encoding, and write failures are visible; failed saves do not mark the document clean or intentionally truncate the original file.
- Persistence uses an appropriate safe replacement strategy. Validate round-trip content and failure behavior with temporary test files, plus manual checks of native dialogs.
- Document the newline/encoding policy and the current policy for external file changes; do not silently claim conflict handling that is absent.

**Non-goals:** A full workspace browser, multi-document tabs, large-file optimization, language tooling, or agent patch application.

## Milestone 3 — Standalone runtime, deterministic mock tasks, and CLI host

**Goal:** Establish a reusable Swift runtime package that works without the IDE or a real agent.

**Learning objectives:** Package boundaries, lifecycle state machines, asynchronous event delivery, cancellation, deterministic testing, and separation of host policy from presentation.

**Acceptance criteria:**

- A separate runtime package has no IDE, AppKit, or SwiftUI dependency. An independent CLI host runs deterministic mock tasks using it.
- Tests cover successful completion, failure, cancellation, event identity/order, and approval pending/accept/decline behavior. No mock action runs before its required approval.
- Start with one active task. Bound event/output buffering and report truncation or overflow honestly.
- The CLI can show task events and respond to approvals without UI code, credentials, network calls, or a real agent installation.
- Document observable event meanings and lifecycle guarantees. Use transient traces initially unless a bounded, security-conscious persistence design is explicitly approved.

**Non-goals:** Real Codex integration, parallel agents, a universal adapter framework, a daemon, durable distributed workflows, or hard resource limits.

## Milestone 4 — Execution event inspector in the IDE

**Goal:** Present the same mock runtime events inside the native app.

**Learning objectives:** UI updates on the appropriate executor, asynchronous state presentation, bounded views, and separating event evidence from chat text.

**Acceptance criteria:**

- Start and cancel a mock task from the IDE; inspect ordered lifecycle and tool events with identifiable status and relevant details.
- Present mock approval requests, send scoped decisions through the runtime, and clear stale or cancelled prompts.
- Editing remains responsive during a controlled burst of mock events. Bound retained/displayed output and identify incomplete or truncated traces.
- Confirm that the CLI remains independently usable and that task state is not owned solely by the inspector UI.

**Non-goals:** Private model reasoning, real AI execution, a polished diff editor, project navigation, or persistent telemetry collection.

## Milestone 5 — Real Codex integration

**Goal:** Replace the mock integration path with the first real agent adapter while preserving the runtime's independent use.

**Learning objectives:** Documented process/protocol integration, version compatibility, authentication boundaries, capability mapping, and enforceable approvals.

**Acceptance criteria:**

- Review current official interfaces and validate the chosen one against the installed Codex version. Record the interface, prerequisites, and compatibility assumptions; reuse Codex's harness.
- Run a bounded task in a disposable test project from the CLI and IDE. Map the available lifecycle, tool, result, error, and cancellation information without inventing missing events.
- Validate approvals against actual Codex policy and execution behavior. Required actions remain blocked until an authorized decision; rejection and interruption have documented outcomes.
- Demonstrate the chosen review-before-apply workflow for proposed file changes. If the interface cannot enforce it directly, evaluate isolation and patch application before claiming support; handle unsaved-document conflicts explicitly.
- Handle a missing executable, authentication failure, malformed/unrecognized events, and process exit without leaking secrets or leaving misleading active state.
- Review what our traces and upstream Codex logs retain. Document gaps and data handling. Keep deterministic mock tests for repeatable coverage.

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

- Exercise process crashes, cancellation races, stale approvals, file conflicts, output floods, and sensitive-log handling; document supported recovery behavior.
- Document setup, build, test, CLI use, package APIs, architecture, and known limitations with commands verified against the supported environment.
- Decide the initial packaging, signing, and supported macOS policy through a scoped plan. Reassess the sandbox strategy and permission boundaries.
- Review dependencies/licenses and credential/trace handling before selecting a project license or preparing a public release.
- Confirm an independent consumer can build and exercise the runtime without the IDE, and report benchmark conditions honestly.

**Non-goals:** Guaranteed security, feature parity with mature IDEs, cloud services, or automatic publication. Public repository creation, publication, and release actions require explicit authorization.
