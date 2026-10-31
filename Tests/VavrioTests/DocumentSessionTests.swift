import Foundation
import Testing
@testable import Vavrio

private actor SaveGate {
    private var entered = false
    private var enteredWaiter: CheckedContinuation<Void, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?
    func pause() async {
        entered = true; enteredWaiter?.resume(); enteredWaiter = nil
        await withCheckedContinuation { releaseWaiter = $0 }
    }
    func waitForEntry() async {
        if !entered { await withCheckedContinuation { enteredWaiter = $0 } }
    }
    func release() { releaseWaiter?.resume(); releaseWaiter = nil }
}

@MainActor
struct DocumentSessionTests {
    private func fixture(_ body: (URL, URL) async throws -> Void) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Vavrio Session \(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("source.swift")
        try Data("café\n".utf8).write(to: file)
        try await body(directory, file)
    }
    @Test func tracksByteChangesAndReturnToSavedText() async throws {
        try await fixture { (_, url) async throws -> Void in
            let session = DocumentSession()
            #expect(await session.open(url))
            #expect(!session.isDirty)
            session.edit("cafe\u{301}\n")
            #expect(session.isDirty) // String equality alone would miss this spelling change.
            session.edit("café\n")
            #expect(!session.isDirty)
        }
    }
    @Test func newerEditsRemainDirtyAfterSave() async throws {
        try await fixture { (_, url) async throws -> Void in
            let session = DocumentSession()
            #expect(await session.open(url))
            session.edit("saved version\n")
            let gate = SaveGate()
            let task = Task {
                await session.save { snapshot, text in
                    await gate.pause()
                    return await TextFileWriter.replace(snapshot, with: text)
                }
            }
            await gate.waitForEntry()
            #expect(session.isSaving)
            session.edit("newer edits\n")
            await gate.release()
            guard case .saved? = await task.value else { Issue.record("Save failed"); return }
            #expect(try Data(contentsOf: url) == Data("saved version\n".utf8))
            #expect(session.text == "newer edits\n")
            #expect(session.isDirty && session.canSave)
            guard case .saved? = await session.save() else { Issue.record("Second save failed"); return }
            #expect(!session.isDirty)
            #expect(try Data(contentsOf: url) == Data("newer edits\n".utf8))
        }
    }
    @Test func failedOpenRetainsExistingEdits() async throws {
        try await fixture { (directory, url) async throws -> Void in
            let session = DocumentSession()
            #expect(await session.open(url))
            session.edit("keep these edits")
            #expect(!(await session.open(directory.appendingPathComponent("missing"))))
            #expect(session.file?.url == url)
            #expect(session.text == "keep these edits" && session.isDirty)
            #expect(!session.isWorking)
        }
    }
    @Test(arguments: ["cancel", "edit", "timeout"])
    func lateLoadsCannotReplacePreservedDocument(action: String) async throws {
        try await fixture { (directory, url) async throws -> Void in
            let session = DocumentSession()
            #expect(await session.open(url))
            let other = directory.appendingPathComponent("other")
            try Data("other file".utf8).write(to: other)
            let entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
            let task = Task {
                await session.open(other, timeout: action == "timeout" ? .milliseconds(5) : .seconds(10)) { path in
                    entered.signal(); release.wait()
                    return try TextFileReader.read(path)
                }
            }
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                DispatchQueue.global().async { entered.wait(); continuation.resume() }
            }
            if action == "cancel" { session.cancelLoading() }
            if action == "edit" { session.edit("new edit during load") }
            if action == "timeout" { try await Task.sleep(for: .milliseconds(30)) }
            #expect(session.isWorking)
            if action != "edit" {
                #expect(!session.isLoading)
                #expect(!(await session.open(url))) // No abandoned-worker accumulation.
            }
            release.signal()
            #expect(!(await task.value))
            #expect(session.file?.url == url)
            #expect(!session.isWorking)
            #expect(session.text == (action == "edit" ? "new edit during load" : "café\n"))
        }
    }
    @Test(arguments: [false, true])
    func failedAndUncertainSavesRetainEdits(uncertain: Bool) async throws {
        try await fixture { (_, url) async throws -> Void in
            let session = DocumentSession()
            #expect(await session.open(url))
            session.edit("keep these edits")
            _ = await session.save { _, _ in
                uncertain ? .uncertain(.verification("test"), recoveryDirectory: nil)
                    : .notWritten(.conflict, recoveryDirectory: nil)
            }
            #expect(session.isDirty && session.text == "keep these edits")
            #expect(session.canSave == !uncertain)
            #expect(session.uncertainSave == uncertain)
            #expect(try Data(contentsOf: url) == Data("café\n".utf8))
        }
    }
}
