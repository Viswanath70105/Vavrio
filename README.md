# Vavrio

Vavrio is a native macOS Markdown workspace built with Swift and AppKit.
Create or open Markdown files in tabs, edit independently, and read common Markdown alongside the source.

## Usage

- Quick Open: ⌘P. Search open tabs and Markdown filenames/paths under the current folder; use arrows and Return to select, Escape to cancel.
- Command Palette: ⇧⌘P. Search workspace commands, with shortcuts and availability shown. Commands use the same save/recovery gates as menus. New queries select the highest-ranked available result; background updates preserve your selection. Return/Escape also work after clicking the result list.
- Find: ⌘F. Open the native editor find bar; ⌘G / ⇧⌘G find next/previous.
- Open Folder: ⇧⌘O. Expand folders and select `.md` files.
- Open File: ⌘O. Reopening the same path selects its existing tab.
- New: ⌘N. Creates an editable untitled Markdown tab without writing to disk.
- Save: ⌘S. Saves the active document explicitly; untitled documents first ask for a new destination. An empty untitled document can be saved deliberately, or closed without prompting.
- Save As: ⇧⌘S. Creates a new `.md` file and follows it in the same tab, preserving undo history, selection, and scrolling. The original file is untouched. Existing destinations are never replaced, including files created by another process during the operation.
- Undo/Redo: ⌘Z / ⇧⌘Z. Each document retains its own history.
- Close Tab: × or ⌘W. Dirty documents offer Save/Discard/Cancel.
- Refresh reloads the explorer listing without rereading or closing documents; it is disabled until a folder is open.
- File → Reload from Disk rereads the active document. Dirty or uncertain documents require confirmation; Cancel is the default. Copy wanted edits first. Successful reload replaces text, clears undo/redo, and resets selection and scrolling to the start.
- File → Reveal Recovery Folder reveals the latest recorded recovery or cleanup directory for the active document when no operation or dialog is pending. A missing directory produces an error; it is never recreated or deleted.
- Reader toggles the rendered pane and follows unsaved edits.

Switching tabs retains text, selection, scrolling and undo history. Closing a tab does not delete its file.
The explorer omits hidden entries and symlinks. Folder changes leave existing tabs open.

Quick Open scans on demand without reading file contents or watching the filesystem. It skips hidden entries, symbolic links, and package descendants. Each scan is bounded to 10,000 visited entries, 2,000 Markdown files, and a cooperative two-second time budget, with up to 100 ranked results displayed. Exact/prefix filename matches lead path and fuzzy subsequence matches; open tabs are prioritized. Partial scans and unreadable entries are reported. Cancellation does not interrupt a stalled filesystem call, and only one scan worker is retained at a time. Reopen Quick Open to rescan. These bounds are resource policies, not measured latency guarantees.

Navigation sheets are unavailable during document operations or another modal transition. While a navigation sheet is open, editor changes and conflicting commands are blocked. Native Find remains available in editable documents during reads and saves, consistent with existing edit-during-operation behavior.

## Build and run

The package declares macOS 14 and Swift 6. Reference-machine checks used an Apple M1 Mac with 8 GB memory;
macOS 14 compatibility and a resource advantage have not been established.
No third-party dependencies are required.

```sh
sh Scripts/build.sh
./.build/debug/Vavrio
```

The reference toolchain has incompatible SwiftPM manifest interfaces. Use the existing local workaround:

```sh
sh Scripts/build.sh --local-manifest-libs
./.build/debug/Vavrio
```

This copies installed manifest libraries under ignored `.build`, omitting private interfaces.
It does not download software or modify the installed toolchain. Builds use two jobs.

## Tests and packaging

```sh
SWIFTPM_CUSTOM_LIBS_DIR="$PWD/.build/swiftpm-local-libs" xcrun swift test --jobs 2 --disable-xctest
sh Scripts/package-app.sh --local-manifest-libs
git diff --check
```

On a healthy toolchain, omit the environment override and packaging workaround flag.
Packaging produces a fresh ad-hoc-signed development bundle under `.build/app-packages`.
It does not install or launch the app. Applications replacement requires authorization and a manual quit.
This is not a notarized public distribution or automatic updater.

## File behavior and limitations

Supported input is a regular UTF-8 file up to **2 MiB (2,097,152 bytes, including any byte-order mark)**. At most one initial UTF-8 BOM is omitted from display and retained for saving; subsequent U+FEFF characters remain text. Existing line endings are retained; newly entered text follows the native text editor's insertion behavior without whole-file newline normalization. Invalid UTF-8 and NUL-containing data are rejected. Symlinks to regular files remain viewable, while special files and folders are rejected. The limit is provisional; near-limit/long-line layout performance remains unmeasured.

Saving initially supports existing local, current-user-owned, single-link regular files with owner read/write permission. It refuses selected symlinks, special permission bits, extended ACLs on the file or immediate parent, unsupported flags, resource-fork/compression metadata, and unavailable or excessive xattrs (256 KiB bound). Ordinary/executable modes, ownership, exact creation time, supported flags, and supported xattrs are checked before/after replacement. An unsupported file can still be viewed and edited for Save As to a new file or copying elsewhere; its Save control is disabled with a reason.

The writer compares target identity, complete original bytes, metadata, and parent identity against the opened snapshot. It verifies an original copy in private same-volume staging, modifies only staged bytes, rechecks the target, then replaces and verifies the result. Detected external changes refuse Save and retain edits. File coordination and checks cannot prevent an uncooperative process from changing the file between the final check and replacement. There is no atomic compare-and-swap or power-loss durability guarantee. An uncertain outcome keeps edits/recovery information and blocks retry until a successful Reload from Disk; no automatic rollback or force overwrite occurs.

Document filesystem work runs off the main actor, with one outstanding document operation across the workspace. During Open or Reload, loaded tabs remain selectable and editable, including undo/redo and copying. New documents, opens, reloads, saves, folder changes/Refresh, tab/window closing, and quitting remain blocked until the reader returns. Saves retain their existing restrictions on tab switching; edits during a save remain dirty if they differ from its saved snapshot. Confirmation and error sheets block switching and editing.

Cancel Read targets the outstanding read even after switching tabs. Cancellation and a logical 10-second timeout reject late results while retaining the worker slot until synchronous I/O returns; neither interrupts a stalled filesystem call. Failed, cancelled, timed-out, or superseded reloads retain the current text, baseline, undo history, and view state. Any edit or undo/redo during a reload prevents adoption, even if the text returns to its earlier value. Background completion does not select its tab.

The app does not watch for external changes. Opening an already-open path selects its tab; use File → Reload from Disk to refresh its contents. Conflict refusals leave edits intact without replacement. Uncertain saves may already have changed disk contents and block Save; copy wanted edits before reloading. The latest returned recovery/cleanup directory remains available across reloads and later saves until the tab closes or another directory replaces it. A directory is not a guarantee of a complete backup, and Vavrio never automatically restores or deletes it.


New and Save As use a separate creation writer: private same-volume staging, verified UTF-8 bytes, and exclusive publication to a previously absent destination. Files receive current-user ownership and owner-only read/write permissions (`0600`). Source timestamps, executable bits, tags, and extended attributes are not copied. System-created metadata, including macOS provenance when present, is inspected and verified unchanged across publication. Local storage, an existing supported parent directory, and no extended parent ACL are required. Unsupported parent protection settings are refused. Existing BOM policy is retained; new untitled documents use UTF-8 without a BOM. The same 2 MiB and encoding restrictions apply.

Save As is available for clean, dirty, save-ineligible, conflicted, and uncertain documents. The current path and paths associated with other open tabs are refused even if absent. Successful creation adopts a fresh baseline; edits made during writing remain unsaved. A definite failure preserves the existing association and editor state. A post-publication verification failure records the attempted path, keeps the original association (or untitled state), and blocks ordinary Save. Save As can preserve the text at a different new path; reuse of the recorded uncertain destination is refused until that uncertainty is resolved. Reload remains tied to the original associated file and is unavailable for untitled documents. No automatic rollback, destination deletion, or power-loss durability guarantee is provided.

Dirty untitled documents offer Save/Discard/Cancel on close or quit. Save-ineligible or uncertain documents offer Save As instead. Cancelling the destination panel or encountering a failed/uncertain creation keeps the document open. The document lifecycle remains explicit in DocumentSession; NSDocument migration is deferred until broader features such as autosave or restoration are considered.

The reader supports headings, emphasis, code, bullets/task lists, quotes and HTTP(S) links.
Tables remain monospaced Markdown; images and relative-link navigation are unsupported.
Rendering is debounced by 200 ms and limited to 200,000 characters; the source remains complete.
Autosave, file management and tab restoration are not implemented.

## Architecture

- AppDelegate owns application startup, menus and termination delegation.
- EditorWindowController owns the workspace window, commands and close/quit decisions.
- EditorDocument retains each native editor, scroll view and undo manager.
- DocumentSession owns text, baseline and asynchronous operation state.
- Foundation/Darwin storage code owns encoding, eligibility and persistence independently of AppKit.
- MarkdownBrowser and MarkdownReader own their respective native UI behavior.

The longer-term direction is a native IDE with an independently reusable AI-agent runtime.
That runtime is not implemented; it must remain independent of AppKit and usable by a CLI without an always-running service.

Contributor instructions are in [AGENTS.md](AGENTS.md). Icon provenance remains in [Assets](Assets/README.md).
The retained replacement probe is an investigation with useful future Save As evidence, not production storage code.

## License

A project license has not yet been selected.

The workspace recovery native acceptance checklist is in [Tests/NativeWorkspaceRecovery.md](Tests/NativeWorkspaceRecovery.md). Automated AppKit tests do not establish visible native behavior or performance.
