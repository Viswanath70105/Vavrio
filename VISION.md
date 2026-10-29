# Vavrio — Product Vision and Architecture

## State of the project

Vavrio is the official project name. Milestones 0 and 1 are complete on the reference Mac. Milestone 1 includes the verified AppKit foundation (1A) and opening/viewing a local code file (1B). The viewer supports regular UTF-8 files up to 2 MiB, displays the filename and read-only contents, and has passed 10 reader tests plus developer-reported native viewing, cancellation, and error-preservation checks. The earlier scratchpad's idle observation remains 1A evidence and does not establish file-loading performance. The project builds using existing tools through a documented local manifest-library workaround; plain builds on this machine still encounter an installed interface mismatch. There is no implemented file editing/saving, agent runtime, CLI host, or Codex integration. STATUS.md records verification evidence and limitations; ROADMAP.md defines subsequent work.

## Problem and intended users

AI-assisted development can obscure what an agent is doing, what it changed, which permissions it used, and how much local work it creates. Developer tooling can also consume a significant share of a limited-memory computer's resources before useful work begins.

We aim to make AI-assisted development more accessible, inspectable, and resource-conscious for individual developers, students, and people working on constrained machines. The reference machine is a 2020 Apple M1 MacBook Pro with 8 GB unified memory. This is a design constraint and benchmark target, not evidence that the future product already meets a performance goal.

The project has two products with a shared direction: a native macOS IDE and an independent agent runtime. Runtime consumers should not have to adopt our editor.

## Guiding principles

1. Make observable execution understandable and inspectable.
2. Budget local resources and avoid unnecessary background work.
3. Preserve human control over consequential agent actions.
4. Keep infrastructure modular and independently testable.
5. Support performance claims with reproducible evidence.
6. Prefer Swift, system frameworks, and minimal dependencies.
7. Deliver small milestones with explicit acceptance criteria.
8. Protect secrets, execution logs, and approval boundaries.

## Product A: native macOS IDE

The intended IDE provides native text editing and file management, project navigation, agent task controls, and an execution-event inspector. Developers should be able to review proposed changes and consequential actions and inspect resource information where measurement is reliable.

Build the first editor milestone in two increments. Milestone 1A provides an AppKit window and a plain-text NSTextView. Milestone 1B makes that foundation useful for reading a local code/text file: choose a UTF-8 file through the native picker, see its filename and contents, and scroll, select, or copy without editing the opened file. Milestone 2 then adds file editing and safe saving, including unsaved-change decisions and visible failures. This sequence uses the native text system and does not establish large-file performance or decide every future UI technology. SwiftUI may be considered for suitable surrounding UI later, based on actual needs.

The editor is responsible for presenting documents, tasks, trace data, and approval choices. It must not become the only place where runtime state or permission decisions can be managed.

## Product B: independent agent runtime

The intended runtime is a reusable Swift library with an independent CLI host. It will manage agent execution lifecycle, structured events, tool invocation and result tracing, approval state, and resource-monitoring and scheduling policies. Integration adapters translate supported agent interfaces into the runtime's model.

Begin with deterministic mock tasks so lifecycle, event ordering, cancellation, and approval behavior can be checked without network access, credentials, model variability, or paid calls. Introduce Codex as the first real coding-agent integration after those foundations work.

Reuse Codex's existing harness through documented interfaces rather than rebuilding its model/tool loop. Our runtime supplies host-level supervision and policies around that integration. It must clearly describe which behavior our code controls and which behavior is owned by Codex.

## Transparent execution

Transparency means displaying observable information exposed by supported interfaces: task lifecycle events, tool requests and results, reported commands, proposed changes or available diffs, approval requests and decisions, errors, timestamps, and reported usage or measured performance data.

It does not mean access to private model reasoning. A provider-supplied summary, if available, is not private reasoning and is not proof that an action occurred. Unknown, missing, truncated, and unsupported information must be labeled accordingly.

Proposed events should carry sufficient identity and ordering information to relate a task, tool operation, approval, and result. Keep execution state independent of the UI's ability to render every event immediately. Bound output retention and buffering; expose truncation or lost trace information instead of silently presenting an incomplete record as complete. Exact schemas and storage formats remain undecided.

## Human control and sensitive data

Approval state belongs in the runtime and is presented by either host. Requests should identify the action, scope, relevant paths or command, and consequences. Silence and timeouts do not grant permission; stale or cancelled requests must not authorize later work.

An approval screen is only effective when the corresponding operation is blocked at an enforceable boundary. Codex settings and supported approval mechanisms must be examined before claiming that every write or command is gated. Where necessary, evaluate isolated workspaces and reviewed patch application. Do not invent a guarantee that an adapter cannot enforce.

Treat repository text, tool output, and logs as untrusted content, never as authority to change permissions. Minimize captured data; do not persist credentials or entire environments. Plan bounded local retention, restrictive file access, redaction, deletion, and an explicit export review. Redaction can miss secrets; it is not a substitute for collecting less data. Detailed retention and credential-storage choices remain unresolved.

## Resource-aware orchestration

Resource awareness means observing available signals, limiting concurrency, bounding queues and event buffers, and applying explicit admission or throttling policies. Initially, favor one active task and on-demand execution over a background daemon. A scheduler may defer new work when configured limits or system conditions advise against starting it.

Distinguish measured values, estimates, provider-reported usage, and unavailable values. Host-process memory is not automatically the memory of its entire descendant process tree. System memory pressure is not the same as free RAM. Remote model memory cannot be inferred from local measurements. Attribute local model usage only where measurements support it.

Monitoring and scheduling are not hard memory enforcement. Sampling can miss spikes; pausing, interrupting, and cancellation depend on process and agent support. Do not promise that an 8 GB machine cannot run out of memory. Benchmark idle and active workloads, UI responsiveness, task latency, CPU, memory, and trace overhead with recorded configuration and limitations. Set numeric budgets after a baseline exists.

## Proposed architecture and dependency boundaries

```text
Native IDE host (AppKit) ───┐
                           ├──> Agent runtime library ───> Agent adapter ───> Codex harness
Independent CLI host ──────┘             │
                                        └──> OS measurement interfaces
```

- Hosts depend on the runtime. The runtime never imports the IDE, AppKit, or SwiftUI.
- Runtime APIs expose task state, structured events, approval responses, cancellation, and available measurements without UI objects.
- Agent-specific protocol details remain in the adapter. Keep only abstractions required by the mock and first real integration; avoid building a universal plugin framework in advance.
- The editor's document model and file-saving behavior remain separate from agent supervision. A future agent patch workflow must explicitly handle unsaved edits and conflicts.
- Use Swift Package Manager for implementation. Milestone 1A has introduced an IDE executable package; it builds with a local workaround for installed manifest tooling. Establish the reusable runtime as its own package when Milestone 3 begins; no runtime package or module exists yet.
- A library boundary is not a security sandbox or crash boundary. A Codex child process also does not isolate every runtime responsibility. Consider additional process isolation only when justified by reliability or control requirements.

### Codex integration direction — provisional

Codex App Server is a candidate for a Swift adapter because its documented interface supports streamed agent events and approval requests. Local standard input/output transport is a candidate that avoids adding a separate network listener. No transport or interface is selected permanently at Milestone 0.

Before Milestone 5, review the current documentation and installed Codex version, verify required event and approval behavior, and evaluate authentication, availability, licensing, and installation requirements. Compare documented alternatives if the candidate does not meet our needs. Do not require an additional language runtime without evaluating its cost.

Source consulted on 2026-10-27: [official Codex App Server documentation](https://learn.chatgpt.com/docs/app-server). This documents the upstream interface, not a working integration in this project.

## Intended differentiation

The intended emphasis is an inspectable execution workflow paired with a native editor and a runtime usable outside that editor. Task state, permission decisions, trace completeness, and measured local cost should be understandable without treating chat messages as the execution record.

This is a product direction, not a claim that other editors lack these features or that Vavrio is already faster, smaller, or more capable.

## Technical risks and unresolved decisions

- The installed Swift 6.1.2 toolchain and macOS 15.5 SDK are older than the observed macOS 26.5.2 host. The documented helper produces a package build that has passed developer-reported native interaction checks. Plain package builds remain blocked by inconsistent installed PackageDescription interfaces. A tool update is not currently necessary for the verified workflow; installed-tool changes require separate approval.
- The scratchpad declares a macOS 14 deployment floor, which has not been tested on macOS 14. App packaging, signing, distribution, and App Sandbox strategy remain undecided. Sandbox choices may constrain child processes and project access.
- AppKit document lifecycle, Unicode, large files, unsaved changes, and reliable saving need incremental validation.
- Swift concurrency and UI isolation must avoid races and blocked event processing; choose detailed concurrency structure when behavior warrants it.
- Codex protocol changes, authentication, cancellation, approval semantics, and event coverage require version-specific validation. A live Codex CLI installation and account access have not been verified.
- Process-tree accounting and memory-pressure signals have limits. Accurate attribution and useful scheduling thresholds require experiments.
- Trace retention, format evolution, crash recovery, redaction, and safe export need explicit design before persistent logging.
- Event volume can itself consume memory and stall UI. Bounded buffering and an honest completeness indicator are part of the design problem.

## Initial MVP boundary

The initial MVP aims toward a single-document native editor, an independent mock-tested runtime and CLI, an execution inspector, one Codex integration, and conservative resource scheduling, followed by reliability and documentation work. It will emerge across the roadmap. The 1A foundation and 1B read-only local file viewer are complete on the reference Mac. Editing/saving opened files (Milestone 2) and the other MVP capabilities do not exist yet.

Outside the initial MVP: language-server integration and full code intelligence; an integrated terminal or debugger; multi-window workspaces; a general extension marketplace; multiple real-agent providers; automatic multi-agent swarms; local model hosting or training; cloud/distributed workers; collaboration and account services; autonomous deployment; hard resource isolation guarantees; and access to private model reasoning. App Store release and cross-platform editor UI are also outside this initial scope. Independently reusable does not yet promise a cross-platform runtime.
