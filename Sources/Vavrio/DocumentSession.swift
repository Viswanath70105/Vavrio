import Foundation

/// One document's state. Filesystem adapters are asynchronous; UI stays in AppKit.
@MainActor
final class DocumentSession {
    enum Origin { case placeholder, untitled(String), fileBacked }
    private(set) var origin: Origin
    private(set) var uncertainDestination: URL?
    init(untitledName: String? = nil) {
        origin = untitledName.map { .untitled($0) } ?? .placeholder
        if untitledName != nil { status = "New document. Use Save (⌘S) to choose a new file." }
    }
    var isUntitled: Bool { if case .untitled = origin { return true }; return false }
    var canSaveAs: Bool { canEdit && !isWorking }
    var canInvokeSave: Bool { !uncertainSave && (isUntitled ? !isWorking : canSave) }
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
        guard canEdit else { return false }
        return uncertainSave || !text.utf8.elementsEqual((file?.text ?? "").utf8)
    }
    var canEdit: Bool { file != nil || isUntitled }
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
            file = snapshot; origin = .fileBacked; text = snapshot.text; revision &+= 1; uncertainSave = false; uncertainDestination = nil
            if case .ineligible(let reason) = snapshot.saveEligibility {
                status = reason.localizedDescription + " Use Save As to preserve your edits in a new file."
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
            file = saved; uncertainSave = false; uncertainDestination = nil
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
    func saveAs(_ destination: URL,
                create: @escaping @Sendable (URL, String, Bool) async -> FileCreationResult = {
                    await TextFileCreator.create($0, text: $1, hasUTF8BOM: $2)
                }) async -> FileCreationResult? {
        guard canSaveAs else { return nil }
        let savingText = text
        let hasBOM = file?.hasUTF8BOM ?? false
        let associated = file?.url
        let uncertain = uncertainDestination
        isWorking = true; isSaving = true; status = "Creating \(destination.lastPathComponent)…"; didChange?()
        let reserved = await Task.detached {
            let canonical = TextFileCreator.canonicalDestination(destination)
            return [associated, uncertain].compactMap { $0 }.contains {
                TextFileCreator.canonicalDestination($0) == canonical
            }
        }.value
        let result: FileCreationResult
        if reserved { result = .notCreated(destination: destination, .reservedDestination, recoveryDirectory: nil) }
        else { result = await create(destination, savingText, hasBOM) }
        isWorking = false; isSaving = false
        switch result {
        case .created(let saved, let warning):
            file = saved; origin = .fileBacked; uncertainSave = false; uncertainDestination = nil
            if let warning { recoveryDirectory = warning }
            status = isDirty ? "Saved the earlier version at \(saved.url.path). Newer edits remain unsaved." : "Saved at \(saved.url.path)."
            if let warning { status += " Cleanup needed: \(warning.path). Use File → Reveal Recovery Folder." }
        case .notCreated(let destination, let error, let recovery):
            if let recovery { recoveryDirectory = recovery }
            status = "No file was created at \(destination.path). " + error.localizedDescription
        case .uncertain(let destination, let error, let recovery):
            uncertainSave = true; uncertainDestination = destination
            if let recovery { recoveryDirectory = recovery }
            status = "Creation outcome is uncertain at \(destination.path). Save is blocked; use Save As at a different new path or open the attempted destination separately to inspect it. " + error.localizedDescription
            if let file { status += " Reload from Disk still reloads the original file: \(file.url.path)." }
        }
        if case .created = result {} else if let recoveryDirectory {
            status += " Use File → Reveal Recovery Folder: \(recoveryDirectory.path). A complete backup is not guaranteed."
        }
        didChange?()
        return result
    }

}
