# Workspace recovery: native acceptance

Status: pending visible native interaction. Automated controller tests are separate evidence.

Automated evidence, 2026-11-11: the implementation working tree passed 54 Swift
Testing tests using `SWIFTPM_CUSTOM_LIBS_DIR="$PWD/.build/swiftpm-local-libs" xcrun
swift test --jobs 2 --disable-xctest`; the app compiled as part of that run.
`git diff --check` passed. The nine added test functions include parameterized
reload decisions, read outcomes, and initial-open selection cases. No visible
native scenarios or resource measurements were performed in this session.
Use a development build and disposable local fixtures. Do not replace the installed app.
If an installed Vavrio must be closed, the developer quits it manually.

Record date, macOS/toolchain, build revision or working-tree state, fixture sizes,
and Pass/Fail/Not run for each case. Record observed behavior and reproduction steps
for failures. These are qualitative checks, not latency or resource measurements.

| Case | Expected result | Result |
| --- | --- | --- |
| Clean reload after an external edit | Latest disk text; selection/scroll at start; undo/redo cleared; subsequent Save succeeds | Not run |
| Dirty reload, Return/Escape/Cancel | Cancel is default; text, undo, selection and scrolling retained | Not run |
| Dirty reload, explicit discard | Text changes only after successful read; correct file identified | Not run |
| Reload deleted or invalid UTF-8 file | Error names file; existing edits, baseline and undo survive | Not run |
| Several tabs; switch/edit while read pending | Loaded tabs usable; Cancel Read targets the pending read; completion keeps selected tab/focus | Not run |
| Cancel/timeout on a controlled slow read | Late data rejected; file/close commands remain blocked until worker returns; no delayed cancellation alert | Not run |
| Conflict and uncertain-save guidance | Distinct messages; uncertain Save blocked; Reload and copy guidance understandable | Not run |
| Recovery folder present/missing | Correct folder revealed; missing path reported without creation/deletion | Not run |
| Duplicate filenames in different folders | Path tooltips distinguish tabs; reload targets selected document | Not run |
| Close/quit with multiple dirty documents | Save/Discard/Cancel act on the correct documents; Cancel preserves remaining work | Not run |
| Narrow/wide window, reader on/off | Controls usable; editor and reader resize; source unchanged | Not run |
| Small file, near-2-MiB file, one long line, several tabs | Record typing, scrolling, tab switching and reader responsiveness; no claims of measured performance | Not run |

Controlled slow reads and uncertain save outcomes are covered by injected automated
fixtures. If they cannot be reproduced safely through the native build, mark their
native rows Not run rather than substituting compilation or automated tests.
Do not use production documents or induce storage failures on valuable files.
