import AppKit
import Testing
@testable import Vavrio

@Suite(.serialized)
@MainActor
struct MarkdownWorkspaceTests {
    @Test func browserFiltersAndDoesNotTraverseDirectoriesOrLinks() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        for name in ["a.md", "B.MD", "code.swift", ".hidden.md"] {
            try Data("text".utf8).write(to: root.appendingPathComponent(name))
        }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("folder"), withIntermediateDirectories: false)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link.md"), withDestinationURL: root.appendingPathComponent("a.md"))
        let entries = try MarkdownEntry.read(root)
        #expect(entries.map { $0.url.lastPathComponent } == ["folder", "a.md", "B.MD"])
        #expect(entries.first?.isDirectory == true)
    }

    @Test func tabsRetainEditsUndoSelectionAndIndependentSaves() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let a = root.appendingPathComponent("a.md"), b = root.appendingPathComponent("b.md")
        try Data("alpha\n".utf8).write(to: a)
        try Data("beta\n".utf8).write(to: b)
        let app = EditorWindowController()
        defer { app.window?.orderOut(nil) }
        app.openURL(a)
        while app.busy { await Task.yield() }
        let first = try #require(app.active)
        func edit(_ document: EditorDocument, _ text: String) {
            let view = document.textView
            document.undoManager.beginUndoGrouping()
            let range = NSRange(location: 0, length: (view.string as NSString).length)
            if view.shouldChangeText(in: range, replacementString: text) {
                view.replaceCharacters(in: range, with: text)
                view.didChangeText()
            }
            document.undoManager.endUndoGrouping()
            view.breakUndoCoalescing()
        }
        edit(first, "alpha edited\n")
        #expect(first.undoManager.canUndo)
        first.textView.setSelectedRange(NSRange(location: 3, length: 2))
        app.openURL(b)
        while app.busy { await Task.yield() }
        let second = try #require(app.active)
        edit(second, "beta edited\n")
        app.openURL(a)
        #expect(app.documents.count == 2)
        #expect(app.active === first)
        #expect(first.textView.selectedRange() == NSRange(location: 3, length: 2))
        #expect(first.session.text == "alpha edited\n")
        #expect(first.session.isDirty && second.session.isDirty)
        #expect(first.undoManager.canUndo)
        #expect(first.textView.undoManager === first.undoManager)
        app.undoDocument(nil)
        #expect(first.textView.string == "alpha\n")
        #expect(first.session.text == "alpha\n")
        #expect(second.session.text == "beta edited\n")
        app.redoDocument(nil)
        #expect(first.session.text == "alpha edited\n")
        guard case .saved? = await first.session.save() else { Issue.record("Save failed"); return }
        #expect(!first.session.isDirty && second.session.isDirty)
        #expect(try String(contentsOf: a, encoding: .utf8) == "alpha edited\n")
        #expect(try String(contentsOf: b, encoding: .utf8) == "beta\n")
        edit(first, String(repeating: "Markdown line\n", count: 300))
        first.textView.layoutManager?.ensureLayout(for: first.textView.textContainer!)
        first.scrollView.contentView.scroll(to: NSPoint(x: 0, y: 200))
        first.scrollView.reflectScrolledClipView(first.scrollView.contentView)
        let scrollOrigin = first.scrollView.contentView.bounds.origin
        #expect(scrollOrigin.y > 0)
        app.select(second)
        app.select(first)
        #expect(first.scrollView.contentView.bounds.origin == scrollOrigin)
        for width in [640.0, 1200.0, 900.0] {
            app.window?.setContentSize(NSSize(width: width, height: 600))
            app.window?.contentView?.layoutSubtreeIfNeeded()
            #expect(first.textView.frame.width > 200)
            #expect(first.textView.frame.width <= first.scrollView.contentSize.width + 1)
        }
    }
    @Test func readerFormatsMarkdownWithoutChangingSource() async throws {
        _ = NSApplication.shared
        let source = "# Heading\r\nA **bold** and *italic* word, `code`.\r\n- item\r\n> quote\r\n```swift\r\nlet a = 1\r\n```\r\n[site](https://example.com) [local](file:///tmp/test)"
        let result = MarkdownReader.render(source)
        #expect(result.string.contains("Heading\nA bold and italic word, code."))
        #expect(result.string.contains("• item"))
        #expect(result.string.contains("let a = 1"))
        #expect(!result.string.contains("```"))
        let heading = try #require(result.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        #expect(heading.pointSize > 20)
        let bold = (result.string as NSString).range(of: "bold")
        let boldFont = try #require(result.attribute(.font, at: bold.location, effectiveRange: nil) as? NSFont)
        #expect(NSFontManager.shared.traits(of: boldFont).contains(.boldFontMask))
        let local = (result.string as NSString).range(of: "local")
        #expect(result.attribute(.link, at: local.location, effectiveRange: nil) == nil)
        let reader = MarkdownReader()
        reader.update("# Old")
        reader.update("# Current unsaved text")
        try await Task.sleep(for: .milliseconds(300))
        #expect(reader.textView.string == "Current unsaved text\n")
        reader.clear()
        #expect(!reader.textView.string.contains("Current unsaved text"))
    }

    @Test func closesInactiveCleanTabWithoutDeletingFileOrOtherEdits() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = EditorWindowController()
        for name in ["a.md", "b.md"] {
            let url = root.appendingPathComponent(name)
            try Data(name.utf8).write(to: url)
            app.openURL(url)
            while app.busy { await Task.yield() }
        }
        let active = try #require(app.active)
        active.session.edit("unsaved")
        let close = NSButton(); close.tag = 0
        app.closeTab(close)
        #expect(app.documents.count == 1)
        #expect(app.active === active)
        #expect(active.session.text == "unsaved" && active.session.isDirty)
        #expect(try String(contentsOf: root.appendingPathComponent("a.md"), encoding: .utf8) == "a.md")
        app.toggleReader(nil)
        app.toggleReader(nil)
        #expect(active.session.text == "unsaved")
    }

}
