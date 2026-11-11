import AppKit
import Testing
@testable import Vavrio

struct WorkspaceNavigationTests {
    @Test func searchRanksNamesPathsAndOpenDocuments() {
        let items = [
            NavigationItem(id: "exact", title: "README.md", detail: "docs/README.md"),
            NavigationItem(id: "prefix", title: "readme-notes.md", detail: "notes/readme-notes.md"),
            NavigationItem(id: "path", title: "intro.md", detail: "readme/intro.md"),
            NavigationItem(id: "open", title: "README.md", detail: "other/README.md", isOpenDocument: true),
            NavigationItem(id: "unicode", title: "Café.md", detail: "notes/Café.md")
        ]
        #expect(NavigationSearch.ranked(items, query: " README.md ").map(\.id).prefix(2) == ["open", "exact"])
        #expect(NavigationSearch.ranked(items, query: "readme").map(\.id) == ["open", "exact", "prefix", "path"])
        #expect(NavigationSearch.ranked(items, query: "cafe").first?.id == "unicode")
        #expect(NavigationSearch.ranked(items, query: "rdm").contains { $0.id == "exact" })
        #expect(NavigationSearch.ranked(items, query: "docs readme").map(\.id) == ["exact"])
        #expect(NavigationSearch.ranked(items, query: "missing").isEmpty)
        #expect(NavigationSearch.ranked(items, query: "", limit: 2).count == 2)
        #expect(NavigationSearch.ranked(items, query: "", limit: 0).isEmpty)
    }
    @Test func scanFiltersHiddenSymlinksAndNonMarkdownAndHonorsBounds() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Vavrio Navigation \(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let nested = root.appendingPathComponent("notes")
        let hidden = root.appendingPathComponent(".hidden")
        for url in [nested, hidden] { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false) }
        for path in ["README.md", "notes/UPPER.MD", "notes/source.swift", ".secret.md", ".hidden/private.md"] {
            try Data("content".utf8).write(to: root.appendingPathComponent(path))
        }
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("alias.md"), withDestinationURL: root.appendingPathComponent("README.md"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("loop"), withDestinationURL: root)
        let scan = WorkspaceNavigation.scan(root)
        #expect(Set(scan.files.map(\.relativePath)) == ["README.md", "notes/UPPER.MD"])
        #expect(!scan.truncated && scan.unreadableDirectories == 0)
        let limited = WorkspaceNavigation.scan(root, maximumFiles: 1)
        #expect(limited.files.count == 1 && limited.truncated)
        #expect(WorkspaceNavigation.scan(root, maximumEntries: 0).files.isEmpty)
        #expect(WorkspaceNavigation.scan(root, timeBudget: .zero).truncated)
        #expect(WorkspaceNavigation.scan(root.appendingPathComponent("missing")).unreadableDirectories > 0)
    }
}

private final class NavigationScanGate: @unchecked Sendable {
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private var calls = 0
    var count: Int { lock.withLock { calls } }
    func release() { semaphore.signal() }
    func scan(_ url: URL) -> WorkspaceFileScan {
        let call = lock.withLock { calls += 1; return calls }
        if call == 1 { _ = semaphore.wait(timeout: .now() + 5) }
        return WorkspaceNavigation.scan(url)
    }
}

@Suite(.serialized)
@MainActor
struct NavigationControllerTests {
    private func wait(_ predicate: () -> Bool) async throws {
        let end = ContinuousClock.now + .seconds(5)
        while !predicate() {
            guard ContinuousClock.now < end else { throw CocoaError(.userCancelled) }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
    private func fixture(_ body: (URL) async throws -> Void) async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Vavrio Palette \(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        for name in ["first.md", "second.md"] { try Data(name.utf8).write(to: root.appendingPathComponent(name)) }
        try await body(root)
    }
    @Test func commandPaletteHonorsGatesAndExecutesAfterDismissal() async throws {
        let app = EditorWindowController()
        #expect(app.commandItems().first { $0.title == "Save" }?.enabled == false)
        app.commandPalette(nil)
        let palette = try #require(app.navigationPalette)
        #expect(app.transitioning)
        app.newDocument(nil) // Modal command gate.
        #expect(app.documents.isEmpty)
        palette.setQuery("New Markdown")
        palette.choose()
        try await wait { app.navigationPalette == nil && !app.transitioning }
        #expect(app.documents.count == 1 && app.active?.session.isUntitled == true)
        #expect(app.commandItems().first { $0.title == "Save" }?.enabled == true)
        app.commandPalette(nil)
        app.navigationPalette?.cancel()
        try await wait { !app.transitioning }
        #expect(app.documents.count == 1)
    }
    @Test func quickOpenFindsFilesAndReusesTabs() async throws {
        try await fixture { (root: URL) async throws -> Void in
            let app = EditorWindowController()
            app.openWorkspace(root)
            app.quickOpen(nil)
            let palette = try #require(app.navigationPalette)
            palette.setQuery("second")
            try await wait { palette.matches.contains { $0.title == "second.md" } }
            palette.choose()
            try await wait { !app.transitioning && !app.busy }
            let doc = try #require(app.active)
            #expect(doc.displayName == "second.md")
            app.quickOpen(nil)
            let again = try #require(app.navigationPalette)
            again.setQuery("second")
            #expect(again.matches.first?.isOpenDocument == true)
            again.choose()
            try await wait { !app.transitioning }
            #expect(app.documents.count == 1 && app.active === doc)
        }
    }
    @Test func cancelledScanDoesNotAccumulateWorkers() async throws {
        try await fixture { (root: URL) async throws -> Void in
            let gate = NavigationScanGate()
            defer { gate.release() }
            let app = EditorWindowController(scanFiles: gate.scan)
            app.newDocument(nil)
            app.openWorkspace(root)
            app.quickOpen(nil)
            try await wait { gate.count == 1 }
            app.navigationPalette?.cancel()
            try await wait { !app.transitioning }
            app.quickOpen(nil)
            let palette = try #require(app.navigationPalette)
            #expect(palette.matches.contains { $0.isOpenDocument })
            try await Task.sleep(for: .milliseconds(30))
            #expect(gate.count == 1)
            gate.release()
            try await wait { gate.count == 2 && palette.matches.contains { $0.title == "first.md" } }
            palette.cancel()
            try await wait { !app.transitioning }
        }
    }
    @Test func nativeFindAndNavigationShortcutsAreWired() throws {
        let previous = NSApplication.shared.mainMenu
        defer { NSApplication.shared.mainMenu = previous }
        let app = AppDelegate()
        app.configureMenu()
        let navigation = try #require(NSApplication.shared.mainMenu?.items.first { $0.submenu?.title == "Navigate" }?.submenu)
        #expect(navigation.items.first?.keyEquivalent == "p")
        #expect(navigation.items.last?.keyEquivalentModifierMask == [.command, .shift])
        #expect(!app.editor.validateMenuItem(NSMenuItem(title: "Find", action: #selector(EditorWindowController.findDocument(_:)), keyEquivalent: "f")))
        app.editor.newDocument(nil)
        let doc = try #require(app.editor.active)
        #expect(doc.textView.usesFindBar && doc.textView.isIncrementalSearchingEnabled)
        app.editor.findDocument(nil)
        #expect(doc.scrollView.isFindBarVisible)
        #expect(app.editor.validateMenuItem(NSMenuItem(title: "Find", action: #selector(EditorWindowController.findDocument(_:)), keyEquivalent: "f")))
        let edit = try #require(NSApplication.shared.mainMenu?.items.first { $0.submenu?.title == "Edit" }?.submenu)
        #expect(edit.items.first { $0.title == "Find Next" }?.tag == NSTextFinder.Action.nextMatch.rawValue)
    }
    @Test func queryChangesChooseBestResultButUpdatesPreserveSelection() {
        let palette = NavigationPalette(title: "Test", placeholder: "Search")
        let items = [NavigationItem(id: "a", title: "alpha.md", detail: ""),
                     NavigationItem(id: "b", title: "beta.md", detail: ""),
                     NavigationItem(id: "disabled", title: "a", detail: "", enabled: false)]
        palette.update(items, status: "")
        #expect(palette.selectedID == "a")
        palette.setQuery("beta")
        #expect(palette.selectedID == "b")
        palette.setQuery("")
        #expect(palette.selectedID == "a")
        _ = palette.control(NSSearchField(), textView: NSTextView(), doCommandBy: #selector(NSResponder.moveDown(_:)))
        #expect(palette.selectedID == "b")
        palette.update(items + [NavigationItem(id: "c", title: "charlie.md", detail: "")], status: "updated")
        #expect(palette.selectedID == "b")
        palette.setQuery("no match")
        #expect(palette.selectedID == nil)
    }
    @Test func resultListAcceptsReturnAndRefreshRequiresFolder() async throws {
        try await fixture { (root: URL) async throws -> Void in
            let app = EditorWindowController()
            let refresh = NSMenuItem(title: "Refresh", action: #selector(EditorWindowController.refreshFolder(_:)), keyEquivalent: "")
            #expect(!app.validateMenuItem(refresh))
            app.openWorkspace(root)
            #expect(app.validateMenuItem(refresh))
            let palette = NavigationPalette(title: "Test", placeholder: "Search")
            palette.update([NavigationItem(id: "selected", title: "File", detail: "")], status: "")
            @MainActor func findTable(_ view: NSView) -> NSTableView? {
                if let table = view as? NSTableView { return table }
                for child in view.subviews { if let table = findTable(child) { return table } }
                return nil
            }
            let content = try #require(palette.panel.contentView)
            let table = try #require(findTable(content))
            var selected: String?
            palette.onFinish = { selected = $0 }
            let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: palette.panel.windowNumber, context: nil, characters: "\r", charactersIgnoringModifiers: "\r",
                isARepeat: false, keyCode: 36))
            table.keyDown(with: event)
            #expect(selected == "selected")
        }
    }

}
