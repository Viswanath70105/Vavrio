import AppKit
import Testing
@testable import Vavrio

@Suite(.serialized)
@MainActor
struct WindowLifecycleTests {
    private func fixture(_ body: (URL) async throws -> Void) async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        for name in ["a.md", "b.md"] { try Data("original".utf8).write(to: root.appendingPathComponent(name)) }
        try await body(root)
    }
    private func open(_ controller: EditorWindowController, _ url: URL) async {
        controller.openURL(url)
        while controller.busy { await Task.yield() }
    }
    @Test(arguments: ["save", "discard", "cancel"])
    func dirtyTabDecision(choice: String) async throws {
        try await fixture { (root: URL) async throws -> Void in
            var prompted = false
            let controller = EditorWindowController { _ in
                prompted = true
                return choice == "save" ? .save : choice == "discard" ? .discard : .cancel
            }
            let url = root.appendingPathComponent("a.md")
            await open(controller, url)
            controller.active?.session.edit("edited")
            controller.closeDocument(nil)
            // A new request must be refused while the tab decision is pending.
            #expect(controller.requestApplicationTermination { _ in Issue.record("Unexpected reply") } == .terminateCancel)
            while !prompted { await Task.yield() }
            while controller.active?.session.isWorking == true { await Task.yield() }
            await Task.yield()
            #expect(controller.documents.count == (choice == "cancel" ? 1 : 0))
            #expect(try String(contentsOf: url, encoding: .utf8) == (choice == "save" ? "edited" : "original"))
        }
    }
    @Test(arguments: [true, false])
    func multipleDocumentTermination(cancelLast: Bool) async throws {
        try await fixture { (root: URL) async throws -> Void in
            var answers = 0
            let controller = EditorWindowController { _ in
                answers += 1
                if answers == 1 { return .save }
                return cancelLast ? .cancel : .discard
            }
            for name in ["a.md", "b.md"] {
                await open(controller, root.appendingPathComponent(name))
                controller.active?.session.edit("edited")
            }
            var replies: [Bool] = []
            #expect(controller.requestApplicationTermination { replies.append($0) } == .terminateLater)
            #expect(controller.requestApplicationTermination { _ in Issue.record("Duplicate reply") } == .terminateCancel)
            while replies.isEmpty { await Task.yield() }
            #expect(replies == [!cancelLast])
            #expect(answers == 2)
            #expect(controller.documents.count == 2)
            #expect(controller.documents[1].session.isDirty)
            #expect(try String(contentsOf: root.appendingPathComponent("a.md"), encoding: .utf8) == "edited")
            #expect(try String(contentsOf: root.appendingPathComponent("b.md"), encoding: .utf8) == "original")
            if !cancelLast {
                #expect(controller.requestApplicationTermination { _ in Issue.record("Repeated prompt") } == .terminateNow)
            }
        }
    }
    @Test func openBlocksCloseAndApprovedWindowCloseDoesNotReprompt() async throws {
        try await fixture { (root: URL) async throws -> Void in
            var prompts = 0
            let controller = EditorWindowController { _ in prompts += 1; return .discard }
            let window = try #require(controller.window)
            controller.openURL(root.appendingPathComponent("a.md"))
            #expect(!controller.windowShouldClose(window))
            #expect(controller.requestApplicationTermination { _ in Issue.record("Unexpected reply") } == .terminateCancel)
            while controller.busy { await Task.yield() }
            controller.active?.session.edit("unsaved")
            #expect(!controller.windowShouldClose(window))
            while prompts == 0 { await Task.yield() }
            await Task.yield()
            #expect(controller.requestApplicationTermination { _ in Issue.record("Repeated prompt") } == .terminateNow)
            #expect(prompts == 1)
        }
    }
    @Test func menusTargetRetainedController() {
        _ = NSApplication.shared
        let oldMenu = NSApplication.shared.mainMenu
        defer { NSApplication.shared.mainMenu = oldMenu }
        let app = AppDelegate()
        app.configureMenu()
        let file = NSApplication.shared.mainMenu?.items.first { $0.submenu?.title == "File" }?.submenu
        let save = file?.items.first { $0.keyEquivalent == "s" }
        #expect(save?.target === app.editor)
        #expect(save?.action == #selector(EditorWindowController.saveDocument(_:)))
        if let save { #expect(!app.editor.validateMenuItem(save)) }
        #expect(file?.items.first { $0.keyEquivalent == "w" }?.target === app.editor)
    }
}
