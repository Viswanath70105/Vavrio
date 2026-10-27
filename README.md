# Vavrio

A native macOS IDE and an independent AI coding-agent runtime, designed around observable execution, human control, and careful use of local resources.

> **Work in progress — documentation foundation only.** No application, runtime, CLI host, or Codex integration has been implemented. There is no runnable build or release yet, and toolchain build compatibility has not been verified.

## Why Vavrio?

AI-assisted development should make it easier to understand what is happening in your project: which tools an agent invoked, what changes it proposed, what required approval, and what local resources its work consumed. That visibility should remain useful on a computer with limited memory.

Vavrio is a student-led engineering project exploring this goal through two complementary products:

- **Native IDE:** a Swift macOS application for text editing, file management, project navigation, agent task controls, and execution inspection.
- **Independent agent runtime:** a reusable Swift component for task lifecycle, structured events, tool traces, approval state, and resource-aware scheduling, usable without the IDE.

The reference development machine is a 2020 Apple M1 MacBook Pro with 8 GB unified memory. It shapes our design choices; it does not establish a performance result. Claims about speed, memory use, and scheduling effectiveness will require reproducible measurements.

## Planned architecture

```text
Native IDE (Swift / AppKit) ───┐
                             ├──> Agent runtime library ───> Agent adapter ───> Codex
Independent CLI host ────────┘             │
                                          └──> Local resource measurements
```

The IDE will own document editing and presentation. The runtime will own execution state and supervision, with no dependency on the IDE, AppKit, or SwiftUI. An independent command-line host will demonstrate that other tools can use the runtime.

Implementation is planned around Swift Package Manager, Apple system frameworks, and minimal dependencies. The first UI milestone is an AppKit scratchpad using the native text system. Runtime development will begin with deterministic mock tasks before introducing real AI calls.

Codex is the first planned coding-agent integration. We intend to reuse its existing harness through documented interfaces rather than rebuild its agent loop. The interface choice remains provisional; see [VISION.md](VISION.md) for the integration direction and open questions.

## What transparency and resource awareness mean

Execution transparency concerns information exposed through supported interfaces: lifecycle events, tool invocations and results, proposed file changes, approval requests and decisions, errors, and available usage data. It does **not** mean access to private model reasoning. Missing or truncated information must be visible as such.

Resource awareness means measuring available local signals, bounding queues and trace buffers, and applying conservative concurrency policies. It does not promise hard memory limits or visibility into remote model memory. Approval controls must gate actual execution, and logs must minimize sensitive data.

## Current status and roadmap

Milestone 0, the documentation and architecture foundation, is complete. Repository publication is being prepared separately from application implementation.

| Milestone | Intended outcome | Status |
| --- | --- | --- |
| 0 | Documentation and architecture foundation | Complete |
| 1 | Native AppKit scratchpad | Planned; next implementation milestone |
| 2 | Open, edit, and save a text file | Planned |
| 3 | Standalone runtime, deterministic mock tasks, and CLI host | Planned |
| 4 | Execution event inspector in the IDE | Planned |
| 5 | Real Codex integration | Planned |
| 6 | Resource-aware scheduling and benchmarking | Planned |
| 7 | Reliability, documentation, and open-source preparation | Planned |

These milestones are provisional, with no promised delivery dates. Early publication makes the design and learning process reviewable; it does not mean the later release-readiness work is complete.

See [ROADMAP.md](ROADMAP.md) for acceptance criteria and non-goals, and [STATUS.md](STATUS.md) for verified progress and limitations.

## Exploring the repository

| Document | Purpose |
| --- | --- |
| [VISION.md](VISION.md) | Product goals, architecture boundaries, technical risks, and MVP scope |
| [ROADMAP.md](ROADMAP.md) | Small milestones with learning objectives and verification criteria |
| [STATUS.md](STATUS.md) | Observed progress, environment evidence, and next steps |
| [AGENTS.md](AGENTS.md) | Repository instructions for AI-assisted development |
| [professor_ara.md](professor_ara.md) | The project's engineering mentorship and communication protocol |

Professor Ara is a teaching persona used to explain design trade-offs, support independent judgment, and distinguish implemented behavior from verified results. The protocol does not imply transferred conversation history or memories.

## Development approach

The project is being built as a practical study of native macOS development, Swift, systems programming, and AI infrastructure. Changes should remain small, explainable, and verifiable. Architecture discussions, careful issue reports, and feedback on assumptions are welcome; substantial implementation proposals should align with the current milestone first.

The initial environment assessment detected Swift 6.1.2, Swift Package Manager, Git, LLDB, and the macOS 15.5 SDK through Apple Command Line Tools on macOS 26.5.2. No build or launch test has been performed. There is no Package.swift yet, so build and test instructions will be added with the first implementation milestone. Full Xcode has not been established as a prerequisite for that prototype.

## License

A project license has not yet been selected. A LICENSE file will be added after an explicit decision.
