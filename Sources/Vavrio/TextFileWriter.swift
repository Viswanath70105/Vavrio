import Darwin
import Foundation

enum FileSaveFailure: Error, Sendable, LocalizedError {
    case ineligible(FileSaveRestriction), conflict, invalidText(TextFileEncodingError)
    case io(domain: String, code: Int), verification(String)

    var errorDescription: String? {
        switch self {
        case .ineligible(let reason):
            reason.localizedDescription + " Your text is retained."
        case .conflict:
            "The file or its metadata changed outside Vavrio. Your edits are retained. Reopen only when you are ready to discard them."
        case .invalidText(let error): error.errorDescription
        case .io(let domain, let code): "The file operation failed (\(domain), \(code)). Your edits are retained."
        case .verification: "The saved file could not be verified. Your edits and recovery information are retained."
        }
    }
    static func from(_ error: Error) -> Self {
        if let error = error as? Self { return error }
        if let error = error as? FileSaveRestriction { return .ineligible(error) }
        if let error = error as? TextFileEncodingError { return .invalidText(error) }
        let error = error as NSError
        return .io(domain: error.domain, code: error.code)
    }
}

enum FileSaveResult: Sendable {
    case saved(TextFile, cleanupWarning: URL?)
    case notWritten(FileSaveFailure, recoveryDirectory: URL?)
    case uncertain(FileSaveFailure, recoveryDirectory: URL?)
}

// Narrow operation boundaries for deterministic filesystem failure/race tests.
enum FileWritePhase: Sendable { case directoryReady, beforeStageWrite, staged, willReplace, didReplace, willCleanup }
struct FileWriteHooks: Sendable {
    var at: @Sendable (FileWritePhase, URL) throws -> Void = { _, _ in }
}

enum TextFileWriter {
    static func replace(_ file: TextFile, with text: String, hooks: FileWriteHooks = .init()) async -> FileSaveResult {
        await Task.detached(priority: .userInitiated) { perform(file, text: text, hooks: hooks) }.value
    }

    private static func check(_ file: TextFile, baseline: FileSaveBaseline, at url: URL) throws -> TextFile {
        do {
            let current = try TextFileReader.read(url)
            guard current.originalData == file.originalData, current.saveEligibility.baseline == baseline else {
                throw FileSaveFailure.conflict
            }
            return current
        } catch { throw FileSaveFailure.conflict }
    }

    private static func verifyDirectory(_ url: URL, device: Int32) throws {
        let fd = open(url.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw FileSaveFailure.verification("staging-directory") }
        defer { close(fd) }
        let metadata = try FileMetadata.read(fd)
        guard metadata.device == device, metadata.uid == getuid(), metadata.mode & 0o7777 == 0o700,
              !(try FileSaveInspection.hasACL(fd)) else { throw FileSaveFailure.verification("staging-directory-metadata") }
    }

    private static func verifyCopy(_ file: TextFile, baseline: FileSaveBaseline, at url: URL, bytes: Data) throws {
        let copy = try TextFileReader.read(url)
        guard copy.originalData == bytes, let metadata = copy.saveEligibility.baseline,
              metadata.metadata.samePreservedMetadata(as: baseline.metadata),
              metadata.attributes == baseline.attributes else { throw FileSaveFailure.verification("staging-copy") }
    }

    private static func perform(_ file: TextFile, text: String, hooks: FileWriteHooks) -> FileSaveResult {
        guard case .eligible(let baseline) = file.saveEligibility else {
            if case .ineligible(let reason) = file.saveEligibility { return .notWritten(.ineligible(reason), recoveryDirectory: nil) }
            return .notWritten(.verification("missing-baseline"), recoveryDirectory: nil)
        }
        let encoded: Data
        do { encoded = try TextFileEncoder.encode(text, hasUTF8BOM: file.hasUTF8BOM) }
        catch { return .notWritten(.from(error), recoveryDirectory: nil) }

        let manager = FileManager()
        var result: FileSaveResult?
        var coordinationError: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: file.url, options: .forReplacing,
                                                        error: &coordinationError) { url in
            var directory: URL?
            var replacementInvoked = false
            func cleanup() -> URL? {
                guard let owned = directory else { return nil }
                do {
                    try hooks.at(.willCleanup, owned)
                    try manager.removeItem(at: owned)
                    return nil
                } catch { return owned }
            }
            do {
                let expectedURL = baseline.parent.url.appendingPathComponent(file.url.lastPathComponent)
                guard url.resolvingSymlinksInPath().standardizedFileURL == expectedURL else { throw FileSaveFailure.conflict }
                _ = try check(file, baseline: baseline, at: url)
                let owned = baseline.parent.url.appendingPathComponent(".vavrio-save-\(UUID().uuidString)", isDirectory: true)
                try manager.createDirectory(at: owned, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
                directory = owned
                try verifyDirectory(owned, device: baseline.metadata.device)
                try hooks.at(.directoryReady, owned)
                let stage = owned.appendingPathComponent("contents")
                try manager.copyItem(at: url, to: stage)
                try verifyCopy(file, baseline: baseline, at: stage, bytes: file.originalData)
                try hooks.at(.beforeStageWrite, stage)
                // Only the private copied inode is truncated. The source is never opened for writing.
                try encoded.write(to: stage)
                try verifyCopy(file, baseline: baseline, at: stage, bytes: encoded)
                try hooks.at(.staged, stage)
                _ = try check(file, baseline: baseline, at: url)
                // Residual race: an uncooperative writer can still modify the target here.
                try hooks.at(.willReplace, url)
                replacementInvoked = true
                // The copied stage already has verified original metadata. Default
                // replacement re-applies creation time through Date and rounds ns.
                let returnedURL = try manager.replaceItemAt(url, withItemAt: stage, backupItemName: nil,
                                                           options: .usingNewMetadataOnly)
                guard let returnedURL,
                      returnedURL.resolvingSymlinksInPath().standardizedFileURL == expectedURL else {
                    throw FileSaveFailure.verification("returned-url")
                }
                try hooks.at(.didReplace, url)
                let saved = try TextFileReader.read(url)
                guard saved.originalData == encoded else { throw FileSaveFailure.verification("saved-bytes") }
                guard let fresh = saved.saveEligibility.baseline else { throw FileSaveFailure.verification("saved-eligibility") }
                guard fresh.parent == baseline.parent else { throw FileSaveFailure.verification("saved-parent") }
                guard fresh.metadata.samePreservedMetadata(as: baseline.metadata) else { throw FileSaveFailure.verification("saved-file-metadata") }
                guard fresh.attributes == baseline.attributes else { throw FileSaveFailure.verification("saved-attributes") }
                result = .saved(saved, cleanupWarning: cleanup())
            } catch {
                if replacementInvoked {
                    // The directory may hold recoverable original data. Never blindly roll back or delete it.
                    result = .uncertain(.from(error), recoveryDirectory: directory)
                } else {
                    result = .notWritten(.from(error), recoveryDirectory: cleanup())
                }
            }
        }
        return result ?? .notWritten(coordinationError.map { .from($0) } ?? .verification("coordinator-not-called"), recoveryDirectory: nil)
    }
}
