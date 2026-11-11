import Foundation

/// One document's state. Filesystem adapters are asynchronous; UI stays in AppKit.
@MainActor
final class DocumentSession {
    enum ReadOutcome: Equatable { case loaded, failed, cancelled, timedOut, superseded, busy }
    enum ReadKind { case open, reload }
    private(set) var recoveryDirectory: URL?
    private var readKind = ReadKind.open
    private var abandonedOutcome = ReadOutcome.cancelled
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
        abandonedOutcome = timedOut ? .timedOut : .cancelled
        let action = readKind == .reload ? "Reload" : "Open"
        abandonedLoadMessage = action + (timedOut ? " timed out." : " cancelled.")
        status = abandonedLoadMessage + " Loaded documents remain editable. Further file operations and closing must wait for the reader to finish."
        didChange?()
    }

    @discardableResult
    func open(_ url: URL, kind: ReadKind = .open, timeout: Duration = .seconds(10),
              read: @escaping @Sendable (URL) throws -> TextFile = TextFileReader.read) async -> ReadOutcome {
        guard !isWorking else { return .busy }
        readKind = kind
        let token = UUID()
        let initialRevision = revision
        loadToken = token; isWorking = true; isLoading = true
        status = "\(kind == .reload ? "Reloading" : "Opening") \(url.lastPathComponent)…"
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
            status = abandonedLoadMessage + (file == nil ? " No document was opened." : " The previous document is retained.")
            didChange?(); return abandonedOutcome
        }
        loadToken = nil
        guard revision == initialRevision else {
            status = "The document changed during the read. Your edits were retained; use File → Reload from Disk when ready."
            didChange?(); return .superseded
        }
        switch result {
        case .success(let snapshot):
            file = snapshot; text = snapshot.text; revision &+= 1; uncertainSave = false
            if case .ineligible(let reason) = snapshot.saveEligibility {
                status = reason.localizedDescription + " You can copy your edits."
            } else { status = (kind == .reload ? "Reloaded." : "Opened.") + " Changes are saved only with Save (⌘S)." }
            didChange?(); return .loaded
        case .failure(let error):
            status = "Couldn’t \(kind == .reload ? "reload" : "open") \(url.lastPathComponent): \(error.localizedDescription)"
            didChange?(); return .failed
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
            file = saved; uncertainSave = false
            if let warning { recoveryDirectory = warning }
            status = warning.map { "Saved. Temporary files could not be removed. Use File → Reveal Recovery Folder: \($0.path)" }
                ?? (isDirty ? "Saved the earlier version. Newer edits remain unsaved." : "Saved.")
        case .notWritten(let error, let recovery):
            if let recovery { recoveryDirectory = recovery }
            status = "Replacement did not occur. " + error.localizedDescription + (recovery.map { " Use File → Reveal Recovery Folder: \($0.path). Folder contents depend on the failure stage; a complete backup is not guaranteed." } ?? "")
        case .uncertain(let error, let recovery):
            if let recovery { recoveryDirectory = recovery }
            uncertainSave = true
            status = "Save outcome is uncertain; the disk may contain the attempted save. Save is blocked. Copy any wanted edits before File → Reload from Disk. " + error.localizedDescription
                + (recovery.map { " Use File → Reveal Recovery Folder: \($0.path). Folder contents depend on the failure stage; a complete backup is not guaranteed." } ?? "")
        }
        didChange?()
        return result
    }
}
