import AppKit
import Darwin
import Testing
@testable import Vavrio

private actor CreationGate {
    var entered = false
    private var continuation: CheckedContinuation<Void, Never>?
    func pause() async { entered = true; await withCheckedContinuation { continuation = $0 } }
    func release() { continuation?.resume(); continuation = nil }
}

@Suite(.serialized)
@MainActor
struct NewDocumentTests {
    private func wait(_ predicate: () async -> Bool) async throws {
        let end = ContinuousClock.now + .seconds(5)
        while !(await predicate()) {
            guard ContinuousClock.now < end else { throw CocoaError(.userCancelled) }
            try await Task.sleep(for: .milliseconds(2))
        }
    }
    private func fixture(_ body: (URL) async throws -> Void) async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Vavrio New \(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        try await body(root)
    }
    private func edit(_ doc: EditorDocument, _ text: String) {
        doc.undoManager.beginUndoGrouping()
        let range = NSRange(location: 0, length: (doc.textView.string as NSString).length)
        if doc.textView.shouldChangeText(in: range, replacementString: text) {
            doc.textView.replaceCharacters(in: range, with: text); doc.textView.didChangeText()
        }
        doc.undoManager.endUndoGrouping(); doc.textView.breakUndoCoalescing()
    }
    private func enabled(_ app: EditorWindowController, _ action: Selector) -> Bool {
        app.validateMenuItem(NSMenuItem(title: "test", action: action, keyEquivalent: ""))
    }
    @Test func independentUntitledTabsAndEmptyClose() async throws {
        let app = EditorWindowController(decision: { _ in Issue.record("Empty close prompted"); return .cancel })
        app.newDocument(nil)
        let first = try #require(app.active)
        #expect(first.url == nil && first.displayName == "Untitled")
        #expect(first.session.canEdit && !first.session.isDirty)
        #expect(enabled(app, #selector(EditorWindowController.saveDocument(_:))))
        #expect(!enabled(app, #selector(EditorWindowController.reloadDocument(_:))))
        edit(first, "first"); #expect(first.session.isDirty)
        app.newDocument(nil)
        let second = try #require(app.active)
        #expect(second.id != first.id && second.displayName == "Untitled 2")
        edit(second, "second")
        app.select(first); app.undoDocument(nil)
        #expect(first.session.text.isEmpty && !first.session.isDirty)
        #expect(second.session.text == "second")
        app.closeDocument(nil)
        try await wait { !app.transitioning }
        #expect(app.documents.count == 1 && app.active === second)
    }
    @Test func explicitlySavesEmptyUntitled() async throws {
        try await fixture { (root: URL) async throws -> Void in
            let url = root.appendingPathComponent("empty.md")
            let app = EditorWindowController(presentAlert: { title, message in Issue.record("Unexpected alert: \(title): \(message)") }, chooseDestination: { _ in url })
            app.newDocument(nil); let doc = try #require(app.active)
            app.saveDocument(nil); try await wait { !app.busy && !app.transitioning }
            #expect(doc.url == url && doc.displayName == "empty.md")
            #expect(try Data(contentsOf: url).isEmpty)
            #expect(!doc.session.isUntitled && !doc.session.isDirty)
            #expect(app.window?.representedURL == url)
        }
    }
    @Test func saveAsPreservesEditorAndSourceMetadataIsNotCopied() async throws {
        try await fixture { (root: URL) async throws -> Void in
            let original = root.appendingPathComponent("source.md"), destination = root.appendingPathComponent("copy.MD")
            let bytes = Data([0xEF, 0xBB, 0xBF]) + Data("original\r\n".utf8)
            try bytes.write(to: original); #expect(chmod(original.path, 0o751) == 0)
            let value = Data("tag".utf8)
            #expect(value.withUnsafeBytes { setxattr(original.path, "com.vavrio.source", $0.baseAddress, $0.count, 0, 0) } == 0)
            let app = EditorWindowController(presentAlert: { title, message in Issue.record("Unexpected alert: \(title): \(message)") }, chooseDestination: { _ in destination })
            app.openURL(original); try await wait { !app.busy }
            let doc = try #require(app.active), id = doc.id
            edit(doc, String(repeating: "edited\r\n", count: 200))
            doc.textView.setSelectedRange(NSRange(location: 2, length: 3))
            doc.textView.layoutManager?.ensureLayout(for: doc.textView.textContainer!)
            doc.scrollView.contentView.scroll(to: NSPoint(x: 0, y: 100))
            let scroll = doc.scrollView.contentView.bounds.origin
            app.saveAsDocument(nil); try await wait { !app.busy }
            #expect(app.active === doc && doc.id == id && doc.url == destination)
            #expect(doc.undoManager.canUndo && doc.textView.selectedRange() == NSRange(location: 2, length: 3))
            #expect(doc.scrollView.contentView.bounds.origin == scroll)
            #expect(doc.session.file?.hasUTF8BOM == true)
            #expect((doc.session.file?.saveEligibility.baseline?.metadata.mode ?? 0) & 0o7777 == 0o600)
            #expect(doc.session.file?.saveEligibility.baseline?.attributes["com.vavrio.source"] == nil)
            #expect(try Data(contentsOf: original) == bytes)
            app.undoDocument(nil); #expect(doc.session.isDirty)
            app.saveDocument(nil); try await wait { !app.busy }
            #expect(try Data(contentsOf: destination) == bytes)
            #expect(try Data(contentsOf: original) == bytes)
        }
    }
    @Test(arguments: ["cancel", "existing", "same", "other-tab", "extension"])
    func refusedDestinationsKeepAssociation(kind: String) async throws {
        try await fixture { (root: URL) async throws -> Void in
            let a = root.appendingPathComponent("a.md"), b = root.appendingPathComponent("b.md")
            try Data("a".utf8).write(to: a); try Data("b".utf8).write(to: b)
            var chosen: URL? = nil
            var alerts = 0
            let app = EditorWindowController(presentAlert: { _, _ in alerts += 1 }, chooseDestination: { _ in chosen })
            if kind == "other-tab" { app.openURL(b); try await wait { !app.busy }; try FileManager.default.removeItem(at: b) }
            app.openURL(a); try await wait { !app.busy }
            let doc = try #require(app.active); edit(doc, "unsaved")
            chosen = kind == "cancel" ? nil : kind == "same" ? a : kind == "extension" ? root.appendingPathComponent("wrong.txt") : b
            app.saveAsDocument(nil); try await wait { !app.busy }
            #expect(doc.url == a && doc.session.text == "unsaved" && doc.session.isDirty)
            #expect(doc.undoManager.canUndo)
            #expect(alerts == (kind == "cancel" ? 0 : 1))
            #expect(try String(contentsOf: a, encoding: .utf8) == "a")
            if kind == "other-tab" { #expect(!FileManager.default.fileExists(atPath: b.path)) }
        }
    }
    @Test func editsDuringCreationRemainDirtyAndCommandsAreBlocked() async throws {
        try await fixture { (root: URL) async throws -> Void in
            let gate = CreationGate()
            let url = root.appendingPathComponent("new.md")
            let app = EditorWindowController(presentAlert: { title, message in Issue.record("Unexpected alert: \(title): \(message)") }, chooseDestination: { _ in url }, createFile: { destination, text, bom in
                await gate.pause()
                return await TextFileCreator.create(destination, text: text, hasUTF8BOM: bom)
            })
            app.newDocument(nil); let doc = try #require(app.active); edit(doc, "snapshot")
            app.saveDocument(nil)
            do { try await wait { await gate.entered } }
            catch { await gate.release(); throw error }
            #expect(doc.textView.isEditable)
            for action in [#selector(EditorWindowController.newDocument(_:)), #selector(EditorWindowController.saveDocument(_:)),
                           #selector(EditorWindowController.saveAsDocument(_:)), #selector(EditorWindowController.closeDocument(_:))] {
                #expect(!enabled(app, action))
            }
            app.newDocument(nil); app.closeDocument(nil); #expect(app.documents.count == 1)
            edit(doc, "later edits")
            await gate.release(); try await wait { !app.busy }
            #expect(try String(contentsOf: url, encoding: .utf8) == "snapshot")
            #expect(doc.session.text == "later edits" && doc.session.isDirty)
        }
    }
    @Test func uncertainFirstSaveCanEscapeToDifferentDestination() async throws {
        try await fixture { (root: URL) async throws -> Void in
            let attempted = root.appendingPathComponent("uncertain.md"), next = root.appendingPathComponent("next.md")
            let session = DocumentSession(untitledName: "Untitled")
            session.edit("wanted")
            _ = await session.saveAs(attempted) { url, _, _ in .uncertain(destination: url, .storage(.verification("test")), recoveryDirectory: root) }
            #expect(session.isUntitled && session.file == nil && session.isDirty)
            #expect(!session.canInvokeSave && session.canSaveAs && session.uncertainDestination == attempted)
            #expect(session.status.contains(attempted.path) && !session.status.contains("Reload from Disk"))
            guard case .notCreated(_, .reservedDestination, _)? = await session.saveAs(attempted) else {
                Issue.record("Uncertain destination was reusable"); return
            }
            guard case .created? = await session.saveAs(next) else { Issue.record("Escape failed"); return }
            #expect(session.file?.url == next && !session.uncertainSave && !session.isDirty)
            #expect(session.recoveryDirectory == root)
        }
    }
    @Test(arguments: ["save", "cancel-panel", "discard", "cancel", "failure"])
    func untitledCloseDecisions(kind: String) async throws {
        try await fixture { (root: URL) async throws -> Void in
            let url = root.appendingPathComponent("new.md")
            if kind == "failure" { try Data("existing".utf8).write(to: url) }
            let app = EditorWindowController(decision: { _ in kind == "discard" ? .discard : kind == "cancel" ? .cancel : .save },
                presentAlert: { _, _ in }, chooseDestination: { _ in kind == "cancel-panel" ? nil : url })
            app.newDocument(nil); let doc = try #require(app.active); edit(doc, "wanted")
            app.closeDocument(nil); try await wait { !app.transitioning && !app.busy }
            let closed = kind == "save" || kind == "discard"
            #expect(app.documents.isEmpty == closed)
            if !closed { #expect(doc.session.text == "wanted" && doc.session.isDirty) }
            if kind == "save" { #expect(try String(contentsOf: url, encoding: .utf8) == "wanted") }
            if kind == "failure" { #expect(try String(contentsOf: url, encoding: .utf8) == "existing") }
        }
    }
    @Test(arguments: ["ineligible", "conflict", "uncertain"])
    func savesExistingProblemDocumentsElsewhere(kind: String) async throws {
        try await fixture { (root: URL) async throws -> Void in
            let original = root.appendingPathComponent("original.md"), destination = root.appendingPathComponent("rescued.md")
            try Data("original".utf8).write(to: original)
            if kind == "ineligible" { #expect(chmod(original.path, 0o400) == 0) }
            let session = DocumentSession()
            #expect(await session.open(original) == .loaded)
            session.edit("wanted edits")
            if kind == "conflict" {
                try Data("external".utf8).write(to: original)
                guard case .notWritten? = await session.save() else { Issue.record("Expected conflict"); return }
            }
            if kind == "uncertain" {
                _ = await session.save { _, _ in .uncertain(.verification("test"), recoveryDirectory: root) }
                let failed = root.appendingPathComponent("attempt.md")
                _ = await session.saveAs(failed) { url, _, _ in .uncertain(destination: url, .storage(.verification("test")), recoveryDirectory: root) }
                #expect(session.file?.url == original)
                #expect(session.status.contains(original.path) && session.status.contains(failed.path))
            }
            guard case .created? = await session.saveAs(destination) else { Issue.record("Save As failed"); return }
            #expect(session.file?.url == destination && !session.isDirty && !session.uncertainSave)
            #expect(try String(contentsOf: destination, encoding: .utf8) == "wanted edits")
            #expect(try String(contentsOf: original, encoding: .utf8) == (kind == "conflict" ? "external" : "original"))
        }
    }
    @Test func mixedDocumentQuitSavesUntitledAndCancelsOnLastDocument() async throws {
        try await fixture { (root: URL) async throws -> Void in
            let saved = root.appendingPathComponent("created.md"), existing = root.appendingPathComponent("existing.md")
            try Data("original".utf8).write(to: existing)
            var decisions = 0
            let app = EditorWindowController(decision: { _ in decisions += 1; return decisions == 1 ? .save : .cancel },
                presentAlert: { title, message in Issue.record("\(title): \(message)") }, chooseDestination: { _ in saved })
            app.newDocument(nil); let untitled = try #require(app.active); edit(untitled, "new text")
            app.openURL(existing); try await wait { !app.busy }
            let backed = try #require(app.active); edit(backed, "existing edits")
            var reply: Bool?
            #expect(app.requestApplicationTermination { reply = $0 } == .terminateLater)
            try await wait { reply != nil }
            #expect(reply == false && app.documents.count == 2)
            #expect(untitled.url == saved && !untitled.session.isDirty)
            #expect(backed.session.isDirty && backed.session.text == "existing edits")
            #expect(try String(contentsOf: existing, encoding: .utf8) == "original")
        }
    }
    @Test func menuShortcutsAndPanelExtensionValidation() throws {
        let app = AppDelegate()
        let previous = NSApplication.shared.mainMenu
        defer { NSApplication.shared.mainMenu = previous }
        app.configureMenu()
        let menu = try #require(NSApplication.shared.mainMenu?.items.first { $0.submenu?.title == "File" }?.submenu)
        let new = try #require(menu.items.first { $0.title == "New" })
        let saveAs = try #require(menu.items.first { $0.title == "Save As…" })
        #expect(new.keyEquivalent == "n" && new.target === app.editor)
        #expect(saveAs.keyEquivalent == "s" && saveAs.keyEquivalentModifierMask == [.command, .shift])
        let validator = SaveDestinationValidator(), panel = NSSavePanel()
        panel.nameFieldStringValue = "wrong.txt"
        #expect(throws: FileCreationFailure.self) {
            try validator.panel(panel, validate: URL(fileURLWithPath: "/tmp/wrong.txt.md"))
        }
    }
    @Test func explorerRefreshFindsNewNestedDocumentWithoutOpeningIt() async throws {
        try await fixture { (root: URL) async throws -> Void in
            let nested = root.appendingPathComponent("nested")
            try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: false)
            let browser = MarkdownBrowser()
            var opened = 0
            browser.onOpen = { _ in opened += 1 }
            browser.open(root)
            let outline = try #require(browser.view.documentView as? NSOutlineView)
            try await wait { outline.numberOfRows == 1 }
            let destination = nested.appendingPathComponent("new.md")
            guard case .created = await TextFileCreator.create(destination, text: "new", hasUTF8BOM: false) else {
                Issue.record("Fixture creation failed"); return
            }
            browser.refresh(selecting: destination)
            try await wait { outline.selectedRow >= 0 }
            #expect(browser.rootURL == root && opened == 0)
            let node = try #require(outline.item(atRow: outline.selectedRow) as? MarkdownBrowser.Node)
            #expect(node.entry.url.standardizedFileURL == destination.standardizedFileURL)
        }
    }

}
