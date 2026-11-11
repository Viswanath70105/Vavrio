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


## New and Save As acceptance

Automated evidence, 2026-11-11: 73 Swift Testing tests passed with two jobs and
the documented local manifest-library workaround, including 19 new test functions
with parameterized creation, collision, recovery, and lifecycle cases. The app
compiled as part of the test run; `git diff --check` passed. Creation tests observed
system-added `com.apple.provenance`; the writer preserves and verifies staged
metadata across publication without copying source metadata. No visible native
interaction or performance measurements were performed for this milestone.

Status: pending visible native interaction. Use disposable files and the development
build; do not replace the installed app without a new authorization and manual quit.
The earlier recovery checklist above also remains pending.

| Case | Expected result | Result |
| --- | --- | --- |
| New (⌘N), multiple untitled tabs | Distinct titles; editable independent documents; no file creation | Not run |
| Save empty untitled document | New empty .md file; same tab follows its path | Not run |
| Save panel and ⇧⌘S | Correct directory/name suggestions; .md and .MD accepted; explicit incompatible extensions refused | Not run |
| Cancel panel | Text, path, undo history, and dirty state unchanged | Not run |
| Existing file/directory/symlink destination | Refused without replacing the destination | Not run |
| First save and Save As | Title, represented path, explorer selection updated; selection, scroll and undo retained | Not run |
| Editing during creation | Saved snapshot is consistent; newer edits remain dirty | Not run |
| Save As after ineligible/conflicted/uncertain save | New destination used; original untouched; recovery guidance identifies both paths where applicable | Not run |
| Close/quit mixed documents | Save/Save As, Discard and Cancel affect correct tabs; cancelled panels keep work open | Not run |
| Reader and nested explorer | New text renders; new file appears and is selected without changing workspace root or tab | Not run |

Controlled race, uncertainty, and injected failure tests are automated evidence,
not proof of visible native panel behavior. Resource usage remains unmeasured.


## Keyboard navigation acceptance

Automated evidence, 2026-11-11: all 79 Swift Testing tests passed with two jobs
and the documented local manifest workaround, including six new navigation tests.
Coverage includes ranking, scan exclusions/bounds, command modal gates, Quick Open
tab reuse, one-worker cancellation behavior, menu shortcuts, and native Find-bar
visibility. `git diff --check` passed. An offscreen AppKit render showed result-row
layout but did not reliably capture native controls; it is not visual acceptance.

Status: pending visible native interaction. Automated palette/controller tests and
offscreen layout inspection do not establish real keyboard/focus behavior.

| Case | Expected result | Result |
| --- | --- | --- |
| ⌘P with no folder | Open and untitled tabs searchable; guidance to open a folder | Not run |
| ⌘P with workspace | Filename/path results; duplicate names distinguished by paths; Return opens or selects | Not run |
| Quick Open keyboard | Arrow navigation, Return choice, Escape dismissal; editor focus restored | Not run |
| ⇧⌘P commands | Shortcuts visible; unavailable commands inert; chosen command executes after dismissal | Not run |
| Cancellation and partial scans | No late results enter a dismissed sheet; partial/unreadable status honest | Not run |
| ⌘F, ⌘G, ⇧⌘G | Native find bar and next/previous matches act on active source editor | Not run |
| Dark/light appearance and long paths | Search text, selection, path labels and footer readable | Not run |


## 0.4.0 release verification

2026-11-11: all 81 Swift Testing tests passed using two jobs and the local
manifest-library workaround. Added regression coverage for query-driven selection,
selection retention on asynchronous updates, Return from the result list, and
Refresh availability. Build 10 passed build, package signature, plist, and
whitespace checks. Visible native acceptance and resource measurements remain
pending; release packaging is not evidence that those checks passed.
