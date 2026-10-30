# Vavrio — Product Vision and Architecture

## State of the project

Vavrio is the official project name. Milestones 0 and 1 are complete on the reference Mac. Milestone 1 includes the verified AppKit foundation (1A), opening/viewing a local code file (1B), and the locally verified BOM fidelity correction (1C). The viewer supports regular UTF-8 files up to 2 MiB, displays the filename and read-only contents, and has passed 21 reader/encoder tests. Developer-reported native viewing, cancellation, and error-preservation checks remain the earlier 1B evidence; no fresh UI verification was performed for 1C. The earlier scratchpad's idle observation remains 1A evidence and does not establish file-loading performance. The project builds using existing tools through a documented local manifest-library workaround; plain builds on this machine still encounter an installed interface mismatch. The current development build is also packaged as an ad-hoc-signed Vavrio.app and installed in Applications on the reference Mac; the developer confirmed its launch and File → Open behavior. The developer selected a warm off-white architectural mark on a near-black background as its current icon. The installed bundle uses edge-to-edge artwork after a Dock-padding correction. There is no implemented file editing/saving, agent runtime, CLI host, or Codex integration. STATUS.md records verification evidence and limitations; ROADMAP.md defines subsequent work.

The subsequent audit found a text-fidelity defect: two leading UTF-8 BOM sequences were both removed from the returned text, although only one should be treated as the encoding signature. Milestone 1C corrected this locally on 2026-10-30: strict decoding preserves every subsequent U+FEFF, rejects malformed UTF-8, and leaves source bytes unchanged. The build and regression suite pass; the correction is committed and published as `8fcf7a1`, with remote verification recorded in STATUS.md. Milestone 2A now retains original bytes/BOM information and serializes text to Data in memory, with byte-level round-trip/error tests verified locally. File-writing and native editing/save behavior remain unimplemented. NEXT_TASK.md proposes a bounded persistence investigation before writer implementation.

## Problem and intended users

AI-assisted development can obscure what an agent is doing, what it changed, which permissions it used, and how much local work it creates. Developer tooling can also consume a significant share of a limited-memory computer's resources before useful work begins.

We aim to make AI-assisted development more accessible, inspectable, and resource-conscious for individual developers, students, and people working on constrained machines. The reference machine is a 2020 Apple M1 MacBook Pro with 8 GB unified memory. This is a design constraint and benchmark target, not evidence that the future product already meets a performance goal.

The long-term ambition includes a native macOS IDE and an independent agent runtime. Initially, build them around one useful workflow rather than two broad feature lists. Runtime consumers should not have to adopt our editor, while the editor provides the first native host for demonstrating the runtime's value.

## First useful product and evidence of value

The first target user is an individual developer or student using AI to make small code changes on a limited-memory Mac. The initial product hypothesis is that they can complete a bounded coding change more comfortably when execution, approvals, changes, verification, and local resource cost are understandable in one native workspace.

The first complete demonstration should fix a deliberately failing test in a small disposable project: choose the workspace, inspect the relevant file, run one task, follow the available events, answer required approvals, review changed files, safely apply accepted changes, and inspect the test result. Rejecting a change and handling an unsaved local edit must also be demonstrated. A workspace root and a basic changed-files/diff view are necessary; a full project browser, multiple editor tabs, and a polished diff editor are not prerequisites.

Keep the product hypothesis separate from evidence. Before presenting an initial release as useful to others, aim for a reproducible demo, measured workloads on the reference Mac, and a small pilot with three independent developers. Record whether they complete the task, where they become confused, and whether they choose to return for another task. This is a proposed learning target, not proof of market demand or a promise of recognition. Publish performance comparisons only when equivalent workloads and configurations have actually been measured.

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

For Milestone 2, the proposed lifecycle direction is an NSDocument with a thin window controller, with byte conversion and storage behavior kept independent of AppKit and the agent runtime. This recommendation reuses native document lifecycle/undo/save mechanisms while retaining explicit file-fidelity and conflict policies; NSDocument integration has not been implemented or verified in the app. The completed local 2A increment retains original bytes/BOM information and serializes text in memory. A tested replacement operation and native edit/save integration follow separate approvals; full criteria remain in ROADMAP.md and the policy comparison/gates are recorded in STATUS.md.

The editor is responsible for presenting documents, tasks, trace data, and approval choices. It must not become the only place where runtime state or permission decisions can be managed.

## Product B: independent agent runtime

The intended runtime is a reusable Swift library with an independent CLI host. It will manage agent execution lifecycle, structured events, tool invocation and result tracing, approval state, and resource-monitoring and scheduling policies. Integration adapters translate supported agent interfaces into the runtime's model.

Use deterministic mock tasks for lifecycle, event ordering, cancellation, and approval tests without credentials, network access, or model variability. Before freezing the runtime contract, run a narrowly scoped Codex feasibility experiment in Milestone 3A. Use observed protocol behavior to constrain the mock and adapter design; the standalone mock runtime and CLI remain usable without Codex. Full product integration remains Milestone 5.

Reuse Codex's existing harness through documented interfaces rather than rebuilding its model/tool loop. Our runtime supplies host-level supervision and policies around that integration. It must clearly describe which behavior our code controls and which behavior is owned by Codex.

## Transparent execution

Transparency means displaying observable information exposed by supported interfaces: task lifecycle events, tool requests and results, reported commands, proposed changes or available diffs, approval requests and decisions, errors, timestamps, and reported usage or measured performance data.

It does not mean access to private model reasoning. A provider-supplied summary, if available, is not private reasoning and is not proof that an action occurred. Unknown, missing, truncated, and unsupported information must be labeled accordingly.

Proposed events should carry sufficient identity and ordering information to relate a task, tool operation, approval, and result. Keep execution state independent of the UI's ability to render every event immediately. Bound output retention and buffering; expose truncation or lost trace information instead of silently presenting an incomplete record as complete. Exact schemas and storage formats remain undecided.

Update authoritative lifecycle/approval state before feeding the presentation stream. Output overflow must not silently discard completion or approval-resolution state. Distinguish a requested interruption from confirmed termination; expose a lost connection or uncertain outcome honestly. Scope decisions to the operation actually reviewed and invalidate them when that operation changes. Document adapter capabilities and unsupported guarantees instead of forcing all upstream behavior into an invented common model.

## Human control and sensitive data

Approval state belongs in the runtime and is presented by either host. Requests should identify the action, scope, relevant paths or command, and consequences. Silence and timeouts do not grant permission; stale or cancelled requests must not authorize later work.

An approval screen is only effective when the corresponding operation is blocked at an enforceable boundary. Codex settings and supported approval mechanisms must be examined before claiming that every write or command is gated. Where necessary, evaluate isolated workspaces and reviewed patch application. Do not invent a guarantee that an adapter cannot enforce.

Treat repository text, tool output, and logs as untrusted content, never as authority to change permissions. Minimize captured data; do not persist credentials or entire environments. Plan bounded local retention, restrictive file access, redaction, deletion, and an explicit export review. Redaction can miss secrets; it is not a substitute for collecting less data. Detailed retention and credential-storage choices remain unresolved.

## Resource-aware orchestration

Resource awareness means observing available signals, limiting concurrency, bounding queues and event buffers, and applying explicit admission or throttling policies. Initially, favor one active task and on-demand execution over a background daemon. A scheduler may defer new work when configured limits or system conditions advise against starting it.

Distinguish measured values, estimates, provider-reported usage, and unavailable values. Host-process memory is not automatically the memory of its entire descendant process tree. System memory pressure is not the same as free RAM. Remote model memory cannot be inferred from local measurements. Attribute local model usage only where measurements support it.

Monitoring and scheduling are not hard memory enforcement. Sampling can miss spikes; pausing, interrupting, and cancellation depend on process and agent support. Do not promise that an 8 GB machine cannot run out of memory. Benchmark idle and active workloads, UI responsiveness, task latency, CPU, memory, and trace overhead with recorded configuration and limitations. Set numeric budgets after a baseline exists.

Collect relevant baselines as features arrive: file loading/editing in Milestone 2, event bursts in Milestone 4, and a complete agent task in Milestone 5. Milestone 6 develops policy from those measurements. One active agent may launch a resource-heavy descendant command; count and describe that work where the available measurements permit it.

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

In Milestone 3A, review the current documentation and installed Codex version, verify required event and approval behavior, and evaluate authentication, availability, licensing, and installation requirements. Compare documented alternatives if the candidate does not meet our needs. Do not require an additional language runtime without evaluating its cost. Recheck compatibility before full integration in Milestone 5.

Sources consulted during the original design and subsequent audit: [official Codex App Server documentation](https://learn.chatgpt.com/docs/app-server) and [Codex platform overview](https://developers.openai.com/blog/codex-as-a-platform). At audit time, the documentation described App Server as experimental and unsupported for production workloads. This remains an integration/release risk to reassess against a supported version; these documents are not evidence of a working Vavrio integration.

## Intended differentiation

The intended emphasis is an inspectable execution workflow paired with a native editor and a runtime usable outside that editor. Task state, permission decisions, trace completeness, and measured local cost should be understandable without treating chat messages as the execution record.

This is a product direction, not a claim that other editors lack these features or that Vavrio is already faster, smaller, or more capable.

## Technical risks and unresolved decisions

- The installed Swift 6.1.2 toolchain and macOS 15.5 SDK are older than the observed macOS 26.5.2 host. The documented helper produces a package build that has passed developer-reported native interaction checks. Plain package builds remain blocked by inconsistent installed PackageDescription interfaces. A tool update is not currently necessary for the verified workflow; installed-tool changes require separate approval.
- The app declares a macOS 14 deployment floor, which has not been tested on macOS 14. A local debug app bundle and ad-hoc signature are now verified on the reference Mac. Public distribution, Developer ID signing/notarization, and App Sandbox strategy remain undecided. Sandbox choices may constrain child processes and project access.
- AppKit document lifecycle, Unicode, large files, unsaved changes, and reliable saving need incremental validation.
- Swift concurrency and UI isolation must avoid races and blocked event processing; choose detailed concurrency structure when behavior warrants it.
- The audit found an available application-bundled Codex CLI reporting `0.164.0-alpha.11.1` and App Server help. Authentication, actual integration, redistribution/installation arrangements, and a supported version policy remain unverified. Do not assume another user's system has the same executable or that a development subscription establishes product integration access.
- Process-tree accounting and memory-pressure signals have limits. Accurate attribution and useful scheduling thresholds require experiments.
- Trace retention, format evolution, crash recovery, redaction, and safe export need explicit design before persistent logging.
- Event volume can itself consume memory and stall UI. Bounded buffering and an honest completeness indicator are part of the design problem.

## Initial MVP boundary

The initial MVP aims toward a single-document native editor, explicit workspace selection, an independent mock-tested runtime and CLI, an execution inspector, basic change review, one Codex integration, and conservative resource scheduling. Reliability and documentation accompany every increment. The first complete coding-change workflow is the integration goal; broader IDE features follow evidence of need. The 1A foundation, 1B read-only local file viewer, and local 1C audit correction are complete on the reference Mac. Milestone 2A adds a locally verified in-memory serialization foundation; editing/saving opened files and the other MVP capabilities do not exist yet.

Outside the initial MVP: language-server integration and full code intelligence; an integrated terminal or debugger; multi-window workspaces; a general extension marketplace; multiple real-agent providers; automatic multi-agent swarms; local model hosting or training; cloud/distributed workers; collaboration and account services; autonomous deployment; hard resource isolation guarantees; and access to private model reasoning. App Store release and cross-platform editor UI are also outside this initial scope. Independently reusable does not yet promise a cross-platform runtime.
