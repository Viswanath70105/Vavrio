# Current task — Markdown reader and workspace usability

Authorized 2026-11-03: developer reported build 6 works, requested closable tabs, a Markdown reader, and improved file selection.

Outcome: visible close buttons on each tab; clearer native folder explorer; optional rendered Markdown reading pane alongside source.

Scope: per-tab × routed through existing unsaved decisions; source-list rows with icons and native selection, keyboard file selection, folder-row expansion, and active-tab selection synchronization; one shared native reader with debounced unsaved-text updates. Storage policy remains unchanged.

Non-goals: file deletion, New/Save As, full CommonMark/GitHub rendering, remote images, HTML execution, watchers/indexing, runtime work, installation, commits and pushes.

Reader supports ATX headings, inline bold/italic/code/strikethrough, bullet/task lists, quotes, fenced code and HTTP(S) links. Ordered lists remain readable as text. Tables retain monospaced Markdown source; images, relative-link navigation, deeply nested blocks and full Markdown compatibility are not implemented. Preview is capped at 200,000 characters; full editable source remains available. Hiding Reader cancels pending rendering. CPU/memory advantage is not measured.

Acceptance: close inactive clean tab without deleting disk file or affecting active dirty tab; dirty closes retain Save/Discard/Cancel; source edits/undo remain isolated; reader displays latest text without changing source; explorer selection follows tab selection. Native visible checks remain for close-button dialogs, folder navigation, reader layout and links.

Verification:

```sh
SWIFTPM_CUSTOM_LIBS_DIR="$PWD/.build/swiftpm-local-libs" xcrun swift test --jobs 2 --disable-xctest
sh Scripts/package-app.sh --local-manifest-libs
git diff --check
```

Status: implemented; final 41-test suite passed. Build, bundle signature/plist validation and whitespace checks passed. Development app: `.build/app-packages/package.SA2kY2/Vavrio.app` (0.3.1 build 7). Visible native checks remain. Installed-app refresh still requires authorization and a confirmed manual quit.
