import Foundation

/// One document's state. Filesystem adapters are asynchronous; UI stays in AppKit.
@MainActor
final class DocumentSession {
    private(set) var file: TextFile?
    private(set) var text = ""
    private(set) var revision: UInt64 = 0
    private(set) var isWorking = false
    private(set) var isLoading = false
    private(set) var isSaving = false
    private(set) var uncertainSave = false
    private(set) var status = "Open a UTF-8 file to start."
    var didChange: (() -> Void)?
    private var loadToken: UUID?
    private var abandonedLoadMessage = "Open cancelled."

    var isDirty: Bool {
        guard let file else { return false }
        return uncertainSave || !text.utf8.elementsEqual(file.text.utf8)
    }
    var canEdit: Bool { file != nil }
    var canSave: Bool {
        file?.saveEligibility.baseline != nil && !isWorking && !uncertainSave && isDirty
    }
    func edit(_ value: String) {
        text = value
        revision &+= 1
        didChange?()
    }
    func cancelLoading(timedOut: Bool = false) {
        guard isLoading else { return }
        loadToken = nil
        isLoading = false
        abandonedLoadMessage = timedOut ? "Open timed out." : "Open cancelled."
        status = abandonedLoadMessage + " Waiting for the file reader to finish before another file operation."
        didChange?()
    }

    @discardableResult
    func open(_ url: URL, timeout: Duration = .seconds(10),
              read: @escaping @Sendable (URL) throws -> TextFile = TextFileReader.read) async -> Bool {
        guard !isWorking else { return false }
        let token = UUID()
        let initialRevision = revision
        loadToken = token; isWorking = true; isLoading = true
        status = "Opening \(url.lastPathComponent)…"
        didChange?()
        let timer = Task { [weak self] in
            do { try await Task.sleep(for: timeout) } catch { return }
            guard self?.loadToken == token else { return }
            self?.cancelLoading(timedOut: true)
        }
        let result = await Task.detached(priority: .userInitiated) { Result { try read(url) } }.value
        timer.cancel()
        isWorking = false; isLoading = false
        guard loadToken == token else {
            status = abandonedLoadMessage + " The previous document is retained."
            didChange?(); return false
        }
        loadToken = nil
        guard revision == initialRevision else {
            status = "The document changed while opening. Your edits were retained; open the other file again when ready."
            didChange?(); return false
        }
        switch result {
        case .success(let snapshot):
            file = snapshot; text = snapshot.text; revision &+= 1; uncertainSave = false
            if case .ineligible(let reason) = snapshot.saveEligibility {
                status = reason.localizedDescription + " You can copy your edits."
            } else { status = "Opened. Changes are saved only with Save (⌘S)." }
            didChange?(); return true
        case .failure(let error):
            status = "Couldn’t open \(url.lastPathComponent): \(error.localizedDescription)"
            didChange?(); return false
        }
    }

    func save(write: @escaping @Sendable (TextFile, String) async -> FileSaveResult = {
        await TextFileWriter.replace($0, with: $1)
    }) async -> FileSaveResult? {
        guard canSave, let snapshot = file else { return nil }
        let savingText = text
        isWorking = true; isSaving = true; status = "Saving…"; didChange?()
        let result = await write(snapshot, savingText)
        isWorking = false; isSaving = false
        switch result {
        case .saved(let saved, let warning):
            file = saved
            status = warning.map { "Saved. Temporary files could not be removed: \($0.path)" }
                ?? (isDirty ? "Saved the earlier version. Newer edits remain unsaved." : "Saved.")
        case .notWritten(let error, let recovery):
            status = error.localizedDescription + (recovery.map { " Recovery directory: \($0.path)" } ?? "")
        case .uncertain(let error, let recovery):
            uncertainSave = true
            status = "Save outcome is uncertain. " + error.localizedDescription
                + (recovery.map { " Recovery directory: \($0.path)" } ?? "")
        }
        didChange?()
        return result
    }
}
