import AppKit
import Testing
@testable import Vavrio

/// Only the synchronous reader waits; all controller waits have a deadline.
private final class ReadGate: @unchecked Sendable {
    private let lock = NSLock()
    private let releaseSignal = DispatchSemaphore(value: 0)
    private var armed = false
    private var entered = false
    func arm() { lock.withLock { armed = true; entered = false } }
    var hasEntered: Bool { lock.withLock { entered } }
    func release() { releaseSignal.signal() }
    func read(_ url: URL) throws -> TextFile {
        let pause = lock.withLock {
            if !armed { return false }
            armed = false; entered = true; return true
        }
        if pause, releaseSignal.wait(timeout: .now() + 5) != .success {
            throw CocoaError(.fileReadUnknown)
        }
        return try TextFileReader.read(url)
    }
}

@Suite(.serialized)
@MainActor
struct WorkspaceRecoveryTests {
    private func wait(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(4)
        while !condition() {
            guard ContinuousClock.now < deadline else {
                Issue.record("Timed out waiting for controller state")
                throw CocoaError(.userCancelled)
            }
            try await Task.sleep(for: .milliseconds(2))
        }
    }
    private func fixture(_ body: (URL) async throws -> Void) async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Vavrio Recovery \(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        for name in ["a.md", "b.md", "c.md"] {
            try Data((name + "\n" + String(repeating: "line\n", count: 200)).utf8).write(to: root.appendingPathComponent(name))
        }
        try await body(root)
    }
    private func open(_ app: EditorWindowController, _ url: URL) async throws -> EditorDocument {
        app.openURL(url)
        try await wait { !app.busy && !app.transitioning }
        return try #require(app.active)
    }
    private func edit(_ document: EditorDocument, _ value: String) {
        let view = document.textView
        document.undoManager.beginUndoGrouping()
        let range = NSRange(location: 0, length: (view.string as NSString).length)
        if view.shouldChangeText(in: range, replacementString: value) {
            view.replaceCharacters(in: range, with: value); view.didChangeText()
        }
        document.undoManager.endUndoGrouping()
        view.breakUndoCoalescing()
    }
    private func enabled(_ app: EditorWindowController, _ action: Selector) -> Bool {
        app.validateMenuItem(NSMenuItem(title: "test", action: action, keyEquivalent: ""))
    }

    @Test func cleanReloadAdoptsBaselineResetsUndoAndSaves() async throws {
        try await fixture { root in
            let app = EditorWindowController(reloadDecision: { _ in Issue.record("Clean reload prompted"); return false })
            let url = root.appendingPathComponent("a.md")
            let doc = try await open(app, url)
            let original = doc.session.text
            edit(doc, "temporary"); app.undoDocument(nil)
            #expect(doc.session.text == original && !doc.session.isDirty)
            doc.textView.setSelectedRange(NSRange(location: 2, length: 1))
            doc.textView.layoutManager?.ensureLayout(for: doc.textView.textContainer!)
            doc.scrollView.contentView.scroll(to: NSPoint(x: 0, y: 100))
            try Data("external\r\n".utf8).write(to: url)
            app.reloadDocument(nil)
            try await wait { !app.busy }
            #expect(doc.session.text == "external\r\n")
            #expect(doc.textView.string == doc.session.text)
            #expect(doc.textView.selectedRange() == NSRange(location: 0, length: 0))
            #expect(doc.scrollView.contentView.bounds.origin == .zero)
            #expect(!doc.undoManager.canUndo && !doc.undoManager.canRedo)
            edit(doc, "next save")
            app.saveDocument(nil)
            try await wait { !app.busy }
            #expect(!doc.session.isDirty)
            #expect(try String(contentsOf: url, encoding: .utf8) == "next save")
        }
    }

    @Test(arguments: [false, true])
    func dirtyReloadConfirmationAndDeferredAdoption(approve: Bool) async throws {
        try await fixture { root in
            let gate = ReadGate()
            defer { gate.release() }
            var prompts = 0
            let app = EditorWindowController(read: gate.read, reloadDecision: { _ in prompts += 1; return approve })
            let url = root.appendingPathComponent("a.md")
            let doc = try await open(app, url)
            edit(doc, "keep edits\n" + String(repeating: "line\n", count: 200))
            doc.textView.setSelectedRange(NSRange(location: 3, length: 2))
            doc.textView.layoutManager?.ensureLayout(for: doc.textView.textContainer!)
            doc.scrollView.contentView.scroll(to: NSPoint(x: 0, y: 100))
            let origin = doc.scrollView.contentView.bounds.origin
            let baseline = doc.session.file?.originalData
            try Data("external".utf8).write(to: url)
            gate.arm(); app.reloadDocument(nil)
            #expect(app.transitioning)
            try await wait { prompts == 1 && !app.transitioning }
            if approve { try await wait { gate.hasEntered } }
            #expect(doc.session.text.hasPrefix("keep edits"))
            #expect(doc.session.file?.originalData == baseline)
            #expect(doc.undoManager.canUndo)
            #expect(doc.textView.selectedRange() == NSRange(location: 3, length: 2))
            #expect(doc.scrollView.contentView.bounds.origin == origin)
            if approve {
                gate.release(); try await wait { !app.busy }
                #expect(doc.textView.string == "external" && !doc.session.isDirty)
                #expect(!doc.undoManager.canUndo)
            } else { #expect(!app.busy && !gate.hasEntered) }
        }
    }

    @Test(arguments: ["missing", "invalid", "large"])
    func failedReloadRetainsNativeState(kind: String) async throws {
        try await fixture { root in
            var alerts: [String] = []
            let app = EditorWindowController(reloadDecision: { _ in true }, presentAlert: { title, message in alerts.append(title + message) })
            let url = root.appendingPathComponent("a.md")
            let doc = try await open(app, url)
            edit(doc, "wanted edits")
            doc.textView.setSelectedRange(NSRange(location: 2, length: 2))
            let baseline = doc.session.file?.originalData
            if kind == "missing" { try FileManager.default.removeItem(at: url) }
            else { try (kind == "invalid" ? Data([0xFF]) : Data(repeating: 65, count: TextFileReader.maximumByteCount + 1)).write(to: url) }
            app.reloadDocument(nil)
            try await wait { !app.transitioning && !app.busy }
            #expect(doc.textView.string == "wanted edits")
            #expect(doc.session.file?.originalData == baseline && doc.session.isDirty)
            #expect(doc.undoManager.canUndo)
            #expect(doc.textView.selectedRange() == NSRange(location: 2, length: 2))
            #expect(alerts.count == 1 && alerts[0].contains(url.path))
        }
    }

    @Test(arguments: ["cancel", "timeout", "complete", "edit", "undo"])
    func readOwnershipAndCommandGates(action: String) async throws {
        try await fixture { root in
            let gate = ReadGate()
            defer { gate.release() }
            var alerts = 0
            let app = EditorWindowController(read: gate.read,
                readTimeout: action == "timeout" ? .milliseconds(100) : .seconds(10),
                reloadDecision: { _ in true }, presentAlert: { _, _ in alerts += 1 })
            let a = try await open(app, root.appendingPathComponent("a.md"))
            let b = try await open(app, root.appendingPathComponent("b.md"))
            app.select(a)
            edit(a, "local"); app.undoDocument(nil) // Clean, but has redo history.
            let baseline = a.session.file?.originalData
            try Data("external".utf8).write(to: a.url!)
            gate.arm(); app.reloadDocument(nil)
            try await wait { gate.hasEntered }
            app.openURL(b.url!) // Same path selection must precede the busy gate.
            #expect(app.active === b && b.textView.isEditable)
            edit(b, "unrelated edits"); app.undoDocument(nil); app.redoDocument(nil)
            #expect(b.session.text == "unrelated edits")
            let responder = app.window?.firstResponder
            for selector in [#selector(EditorWindowController.newDocument(_:)),
                             #selector(EditorWindowController.saveAsDocument(_:)),
                             #selector(EditorWindowController.saveDocument(_:)),
                             #selector(EditorWindowController.reloadDocument(_:)),
                             #selector(EditorWindowController.openDocument(_:)),
                             #selector(EditorWindowController.openFolder(_:)),
                             #selector(EditorWindowController.refreshFolder(_:)),
                             #selector(EditorWindowController.closeDocument(_:))] {
                #expect(!enabled(app, selector))
            }
            app.saveDocument(nil); app.reloadDocument(nil); app.closeDocument(nil)
            app.openURL(root.appendingPathComponent("c.md")); app.refreshFolder(nil)
            #expect(app.documents.count == 2)
            #expect(app.requestApplicationTermination { _ in Issue.record("Unexpected termination reply") } == .terminateCancel)
            #expect(!app.windowShouldClose(try #require(app.window)))
            #expect(try String(contentsOf: b.url!, encoding: .utf8) != "unrelated edits")
            if action == "cancel" { app.cancelRead(nil) }
            if action == "timeout" { try await wait { !a.session.isLoading } }
            if action == "edit" || action == "undo" {
                app.select(a)
                if action == "edit" { edit(a, "during reload") }
                else { app.redoDocument(nil); app.undoDocument(nil) }
                app.select(b)
            }
            if action == "cancel" || action == "timeout" {
                #expect(app.busy && a.session.isWorking && !a.session.isLoading)
                #expect(!enabled(app, #selector(EditorWindowController.cancelRead(_:))))
            }
            gate.release(); try await wait { !app.busy }
            #expect(app.active === b && app.window?.firstResponder === responder)
            #expect(b.session.text == "unrelated edits" && b.session.isDirty)
            #expect(alerts == 0)
            if action == "complete" { #expect(a.session.text == "external" && !a.undoManager.canRedo) }
            else {
                #expect(a.session.file?.originalData == baseline)
                #expect(a.textView.string == a.session.text)
                #expect(a.session.text != "external")
            }
            #expect(enabled(app, #selector(EditorWindowController.saveDocument(_:))))
        }
    }

    @Test(arguments: [false, true])
    func abandonedInitialOpenPreservesSelection(switched: Bool) async throws {
        try await fixture { root in
            let gate = ReadGate(); defer { gate.release() }
            let app = EditorWindowController(read: gate.read, presentAlert: { _, _ in Issue.record("Cancellation showed alert") })
            let a = try await open(app, root.appendingPathComponent("a.md"))
            let b = try await open(app, root.appendingPathComponent("b.md"))
            app.select(a)
            gate.arm(); app.openURL(root.appendingPathComponent("c.md"))
            try await wait { gate.hasEntered }
            #expect(app.active?.textView.isEditable == false)
            if switched { app.select(b) }
            app.cancelRead(nil)
            #expect(app.documents.count == 3 && app.busy)
            gate.release(); try await wait { !app.busy }
            #expect(app.documents.count == 2)
            #expect(app.active === (switched ? b : a))
        }
    }

    @Test func recoveryReferenceAndUncertaintySurviveUntilSuccessfulReload() async throws {
        try await fixture { root in
            let app = EditorWindowController(reloadDecision: { _ in true }, presentAlert: { _, _ in })
            let a = try await open(app, root.appendingPathComponent("a.md"))
            let baseline = try #require(a.session.file)
            let recovery = root.appendingPathComponent("recovery")
            try FileManager.default.createDirectory(at: recovery, withIntermediateDirectories: false)
            let sentinel = recovery.appendingPathComponent("keep")
            try Data("untouched".utf8).write(to: sentinel)
            edit(a, "wanted edits")
            _ = await a.session.save { _, _ in .uncertain(.verification("test"), recoveryDirectory: recovery) }
            #expect(a.session.uncertainSave && !a.session.canSave)
            #expect(enabled(app, #selector(EditorWindowController.revealRecoveryFolder(_:))))
            #expect(enabled(app, #selector(EditorWindowController.reloadDocument(_:))))
            try Data([0xFF]).write(to: a.url!)
            app.reloadDocument(nil); try await wait { !app.busy && !app.transitioning }
            #expect(a.session.uncertainSave && a.session.text == "wanted edits")
            try baseline.originalData.write(to: a.url!)
            app.reloadDocument(nil); try await wait { !app.busy && !app.transitioning }
            #expect(!a.session.uncertainSave && !a.session.isDirty)
            #expect(a.session.recoveryDirectory == recovery)
            edit(a, "later")
            _ = await a.session.save { _, _ in .notWritten(.conflict, recoveryDirectory: nil) }
            #expect(a.session.recoveryDirectory == recovery)
            #expect(a.session.status.contains("Replacement did not occur"))
            let cleanup = root.appendingPathComponent("cleanup")
            _ = await a.session.save { file, _ in .saved(file, cleanupWarning: cleanup) }
            #expect(a.session.recoveryDirectory == cleanup)
            #expect(a.session.status.hasPrefix("Saved."))
            _ = await a.session.save { file, _ in .saved(file, cleanupWarning: nil) }
            #expect(a.session.recoveryDirectory == cleanup)
            _ = try await open(app, root.appendingPathComponent("b.md"))
            #expect(!enabled(app, #selector(EditorWindowController.revealRecoveryFolder(_:))))
            #expect(try String(contentsOf: sentinel, encoding: .utf8) == "untouched")
        }
    }
    @Test func reloadUpdatesReaderAndSaveEligibility() async throws {
        try await fixture { root in
            let app = EditorWindowController()
            let doc = try await open(app, root.appendingPathComponent("a.md"))
            app.toggleReader(nil)
            try Data("# Fresh heading".utf8).write(to: doc.url!)
            try FileManager.default.setAttributes([.posixPermissions: 0o400], ofItemAtPath: doc.url!.path)
            defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: doc.url!.path) }
            app.reloadDocument(nil)
            try await wait { !app.busy }
            #expect(doc.session.file?.saveEligibility.baseline == nil)
            edit(doc, "edited read-only file")
            #expect(!enabled(app, #selector(EditorWindowController.saveDocument(_:))))
            #expect(enabled(app, #selector(EditorWindowController.reloadDocument(_:))))
            @MainActor func textViews(_ view: NSView) -> [NSTextView] {
                if let text = view as? NSTextView { return [text] }
                return view.subviews.flatMap { textViews($0) }
            }
            let content = try #require(app.window?.contentView)
            try await wait {
                textViews(content).contains { $0 !== doc.textView && $0.string == "edited read-only file\n" }
            }
        }
    }

    @Test func failedInitialOpenAndErrorModalKeepCorrectDocument() async throws {
        try await fixture { root in
            let gate = ReadGate(); defer { gate.release() }
            var app: EditorWindowController!
            var a: EditorDocument!
            var alerts = 0
            app = EditorWindowController(read: gate.read, presentAlert: { _, message in
                alerts += 1
                #expect(message.contains("missing.md"))
                #expect(app.transitioning && !a.textView.isEditable)
                #expect(!enabled(app, #selector(EditorWindowController.toggleReader(_:))))
                #expect(!enabled(app, #selector(EditorWindowController.reloadDocument(_:))))
                app.openURL(root.appendingPathComponent("c.md"))
                app.closeDocument(nil)
            })
            a = try await open(app, root.appendingPathComponent("a.md"))
            let b = try await open(app, root.appendingPathComponent("b.md"))
            app.select(a)
            gate.arm(); app.openURL(root.appendingPathComponent("missing.md"))
            try await wait { gate.hasEntered }
            app.select(b)
            gate.release(); try await wait { !app.busy && !app.transitioning }
            #expect(alerts == 1 && app.documents.count == 2)
            #expect(app.active === b && b.textView.isEditable)
        }
    }

    @Test func claimedSaveBlocksTabSwitchAndMissingRecoveryRevealReportsPath() async throws {
        try await fixture { root in
            var messages: [String] = []
            let app = EditorWindowController(presentAlert: { _, message in messages.append(message) })
            let a = try await open(app, root.appendingPathComponent("a.md"))
            let b = try await open(app, root.appendingPathComponent("b.md"))
            edit(b, "saved b")
            app.saveDocument(nil)
            #expect(app.busy)
            app.select(a); app.openURL(a.url!)
            #expect(app.active === b)
            app.reloadDocument(nil); app.closeDocument(nil)
            try await wait { !app.busy }
            #expect(!b.session.isDirty && app.documents.count == 2)
            edit(b, "more edits")
            let missing = root.appendingPathComponent("missing-recovery")
            _ = await b.session.save { _, _ in .notWritten(.conflict, recoveryDirectory: missing) }
            app.revealRecoveryFolder(nil)
            #expect(app.transitioning)
            try await wait { !app.transitioning }
            #expect(messages.count == 1 && messages[0].contains(missing.path))
            #expect(!FileManager.default.fileExists(atPath: missing.path))
            #expect(b.session.text == "more edits" && b.session.recoveryDirectory == missing)
        }
    }

}
