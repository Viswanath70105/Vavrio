import Darwin
import Foundation

enum FileCreationFailure: Error, Sendable, LocalizedError {
    case destinationExists, invalidDestination, reservedDestination, parentChanged
    case storage(FileSaveFailure)
    var errorDescription: String? {
        switch self {
        case .destinationExists: "Save As creates new files only. Choose a destination that does not exist."
        case .invalidDestination: "Choose a local .md file in an existing supported folder."
        case .reservedDestination: "This path belongs to an open document or an unresolved save. Choose a different new destination."
        case .parentChanged: "The destination folder changed during creation. Your text is retained; choose a new destination again."
        case .storage(let error): error.localizedDescription
        }
    }
    static func from(_ error: Error) -> Self {
        error as? Self ?? .storage(.from(error))
    }
}

enum FileCreationResult: Sendable {
    case created(TextFile, cleanupWarning: URL?)
    case notCreated(destination: URL, FileCreationFailure, recoveryDirectory: URL?)
    case uncertain(destination: URL, FileCreationFailure, recoveryDirectory: URL?)
}

enum FileCreationPhase: Sendable { case directoryReady, beforeWrite, staged, willPublish, didPublish, willCleanup }
struct FileCreationHooks: Sendable {
    var at: @Sendable (FileCreationPhase, URL) throws -> Void = { _, _ in }
}

/// New-file publication never invokes the existing-file replacement writer.
enum TextFileCreator {
    static func canonicalDestination(_ url: URL) -> URL {
        url.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL
            .appendingPathComponent(url.lastPathComponent)
    }
    static func requireAbsent(_ url: URL) throws {
        var value = stat()
        if lstat(url.path, &value) == 0 { throw FileCreationFailure.destinationExists }
        guard errno == ENOENT else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
    }
    static func create(_ destination: URL, text: String, hasUTF8BOM: Bool,
                       hooks: FileCreationHooks = .init()) async -> FileCreationResult {
        await Task.detached(priority: .userInitiated) {
            perform(destination, text: text, hasUTF8BOM: hasUTF8BOM, hooks: hooks)
        }.value
    }
    private static func parent(_ url: URL) throws -> FileParentBaseline {
        guard try url.resourceValues(forKeys: [.volumeIsLocalKey]).volumeIsLocal == true else {
            throw FileSaveRestriction.nonlocalVolume
        }
        let fd = open(url.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw FileCreationFailure.invalidDestination }
        defer { close(fd) }
        let metadata = try FileMetadata.read(fd)
        guard metadata.flags & ~UInt32(UF_NODUMP | UF_HIDDEN) == 0,
              metadata.mode & 0o7000 == 0 else { throw FileSaveRestriction.flags }
        guard !(try FileSaveInspection.hasACL(fd)) else { throw FileSaveRestriction.extendedACL }
        return FileParentBaseline(url: url, device: metadata.device, inode: metadata.inode,
                                  mode: metadata.mode, uid: metadata.uid, gid: metadata.gid, flags: metadata.flags)
    }
    private static func verify(_ url: URL, bytes: Data) throws -> TextFile {
        let file = try TextFileReader.read(url)
        guard file.originalData == bytes else { throw FileSaveFailure.verification("created-bytes") }
        guard let baseline = file.saveEligibility.baseline else {
            if case .ineligible(let reason) = file.saveEligibility { throw reason }
            throw FileSaveFailure.verification("created-baseline")
        }
        guard baseline.metadata.uid == getuid(), baseline.metadata.links == 1,
              baseline.metadata.mode & 0o7777 == 0o600 else { throw FileSaveFailure.verification("created-mode-owner-links") }
        guard baseline.metadata.flags == 0 else { throw FileSaveFailure.verification("created-flags") }
        return file
    }
    private static func perform(_ selected: URL, text: String, hasUTF8BOM: Bool,
                                hooks: FileCreationHooks) -> FileCreationResult {
        let manager = FileManager()
        var directory: URL?
        var directoryIdentity: FileMetadata?
        var published = false
        var destination = selected
        func cleanup() -> URL? {
            guard let directory else { return nil }
            do {
                try hooks.at(.willCleanup, directory)
                var current = stat()
                guard let expected = directoryIdentity, lstat(directory.path, &current) == 0,
                      current.st_dev == expected.device, current.st_ino == expected.inode,
                      current.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) else {
                    throw FileSaveFailure.verification("cleanup-directory-identity")
                }
                try manager.removeItem(at: directory); return nil
            }
            catch { return directory }
        }
        do {
            guard selected.isFileURL, selected.pathExtension.lowercased() == "md" else {
                throw FileCreationFailure.invalidDestination
            }
            let bytes = try TextFileEncoder.encode(text, hasUTF8BOM: hasUTF8BOM)
            destination = canonicalDestination(selected)
            let parentURL = destination.deletingLastPathComponent()
            let baseline = try parent(parentURL)
            try requireAbsent(destination)
            let owned = parentURL.appendingPathComponent(".vavrio-create-\(UUID().uuidString)", isDirectory: true)
            try manager.createDirectory(at: owned, withIntermediateDirectories: false,
                                        attributes: [.posixPermissions: 0o700])
            directory = owned
            let fd = open(owned.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard fd >= 0 else { throw FileSaveFailure.verification("creation-directory") }
            defer { close(fd) }
            let metadata = try FileMetadata.read(fd)
            directoryIdentity = metadata
            guard metadata.device == baseline.device, metadata.uid == getuid(), metadata.mode & 0o7777 == 0o700,
                  !(try FileSaveInspection.hasACL(fd)) else { throw FileSaveFailure.verification("creation-directory") }
            try hooks.at(.directoryReady, owned)
            let stage = owned.appendingPathComponent("contents")
            let output = open(stage.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
            guard output >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
            let handle = FileHandle(fileDescriptor: output, closeOnDealloc: true)
            defer { try? handle.close() }
            guard fchmod(output, 0o600) == 0 else { throw FileSaveRestriction.permissions }
            try hooks.at(.beforeWrite, stage)
            try handle.write(contentsOf: bytes)
            try handle.close()
            let staged = try verify(stage, bytes: bytes)
            let stagedBaseline = staged.saveEligibility.baseline!
            let stagedMetadata = stagedBaseline.metadata
            // macOS may attach provenance to a freshly created file. Preserve its
            // inspected metadata; no source file or source xattrs are copied.
            try hooks.at(.staged, stage)
            guard try parent(parentURL) == baseline,
                  canonicalDestination(selected) == destination else { throw FileCreationFailure.parentChanged }
            try requireAbsent(destination)
            try hooks.at(.willPublish, destination)
            // Exclusive publication, not a preflight check followed by overwriting rename.
            guard renamex_np(stage.path, destination.path, UInt32(RENAME_EXCL)) == 0 else {
                if errno == EEXIST { throw FileCreationFailure.destinationExists }
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            }
            published = true
            try hooks.at(.didPublish, destination)
            let saved = try verify(destination, bytes: bytes)
            guard let fresh = saved.saveEligibility.baseline, fresh.parent == baseline,
                  fresh.metadata.device == stagedMetadata.device, fresh.metadata.inode == stagedMetadata.inode,
                  fresh.metadata.samePreservedMetadata(as: stagedMetadata), fresh.attributes == stagedBaseline.attributes,
                  canonicalDestination(selected) == destination else { throw FileSaveFailure.verification("published-file") }
            return .created(saved, cleanupWarning: cleanup())
        } catch {
            if published { return .uncertain(destination: destination, .from(error), recoveryDirectory: directory) }
            return .notCreated(destination: destination, .from(error), recoveryDirectory: cleanup())
        }
    }
}
