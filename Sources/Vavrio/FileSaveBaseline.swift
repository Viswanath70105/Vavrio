import Darwin
import Foundation

enum FileSaveRestriction: String, Error, Sendable, LocalizedError {
    case selectedSymlink, notRegular, multipleLinks, ownership, permissions, specialMode
    case flags, extendedACL, metadataUnavailable, metadataTooLarge, unsupportedAttributes
    case changedDuringRead, nonlocalVolume

    var errorDescription: String? {
        switch self {
        case .selectedSymlink: "Saving through a symbolic link is not supported yet."
        case .notRegular: "Only regular text files can be saved."
        case .multipleLinks: "Saving a file shared by multiple hard links is not supported yet."
        case .ownership: "This prototype saves only files owned by your account."
        case .permissions: "The file does not allow your account to read and write it."
        case .specialMode, .flags: "The file has protection settings this prototype cannot preserve safely."
        case .extendedACL: "Saving files or folders with custom access rules is not supported yet."
        case .metadataUnavailable, .metadataTooLarge, .unsupportedAttributes:
            "The file's metadata cannot be preserved by this prototype."
        case .changedDuringRead: "The file changed while it was being opened. Reopen it before saving."
        case .nonlocalVolume: "Saving is currently supported only on local storage."
        }
    }
}

struct FileStamp: Equatable, Sendable {
    let seconds: Int
    let nanoseconds: Int
    init(_ value: timespec) { seconds = value.tv_sec; nanoseconds = value.tv_nsec }
}

struct FileMetadata: Equatable, Sendable {
    let device: Int32
    let inode: UInt64
    let size: Int64
    let mode: UInt16
    let uid: UInt32
    let gid: UInt32
    let links: UInt16
    let flags: UInt32
    let birth: FileStamp
    let modification: FileStamp
    let change: FileStamp

    init(_ value: stat) {
        device = value.st_dev; inode = value.st_ino; size = value.st_size
        mode = value.st_mode; uid = value.st_uid; gid = value.st_gid
        links = value.st_nlink; flags = value.st_flags
        birth = FileStamp(value.st_birthtimespec)
        modification = FileStamp(value.st_mtimespec); change = FileStamp(value.st_ctimespec)
    }
    static func read(_ descriptor: Int32) throws -> Self {
        var value = stat()
        guard fstat(descriptor, &value) == 0 else { throw FileSaveRestriction.metadataUnavailable }
        return Self(value)
    }
    func restriction(currentUID: UInt32 = getuid()) -> FileSaveRestriction? {
        if mode & mode_t(S_IFMT) != mode_t(S_IFREG) { return .notRegular }
        if links != 1 { return .multipleLinks }
        if uid != currentUID { return .ownership }
        if mode & 0o600 != 0o600 { return .permissions }
        if mode & 0o7000 != 0 { return .specialMode }
        if flags & ~UInt32(UF_NODUMP | UF_HIDDEN) != 0 { return .flags }
        return nil
    }
    func samePreservedMetadata(as other: Self) -> Bool {
        mode == other.mode && uid == other.uid && gid == other.gid
            && flags == other.flags && birth == other.birth
    }
}

struct FileParentBaseline: Equatable, Sendable {
    let url: URL
    let device: Int32
    let inode: UInt64
    let mode: UInt16
    let uid: UInt32
    let gid: UInt32
    let flags: UInt32
}

struct FileSaveBaseline: Equatable, Sendable {
    let metadata: FileMetadata
    let attributes: [String: Data]
    let parent: FileParentBaseline
}

enum FileSaveEligibility: Sendable {
    case eligible(FileSaveBaseline)
    case ineligible(FileSaveRestriction)

    var baseline: FileSaveBaseline? {
        if case .eligible(let baseline) = self { return baseline }
        return nil
    }
}

enum FileSaveInspection {
    static let maximumAttributeBytes = 256 * 1024

    static func hasACL(_ descriptor: Int32) throws -> Bool {
        guard let acl = acl_get_fd_np(descriptor, ACL_TYPE_EXTENDED) else {
            let error = errno
            _ = try FileMetadata.read(descriptor)
            if error == ENOENT { return false }
            throw FileSaveRestriction.metadataUnavailable
        }
        defer { acl_free(UnsafeMutableRawPointer(acl)) }
        var entry: acl_entry_t?
        let status = acl_get_entry(acl, Int32(ACL_FIRST_ENTRY.rawValue), &entry)
        // A nonempty extended ACL is outside the initial writer's support policy.
        if status == 0 { return entry != nil }
        if errno == EINVAL { return false } // No first entry in an empty ACL.
        throw FileSaveRestriction.metadataUnavailable
    }

    static func attributes(_ descriptor: Int32) throws -> [String: Data] {
        let count = flistxattr(descriptor, nil, 0, 0)
        guard count >= 0 else { throw FileSaveRestriction.metadataUnavailable }
        guard count <= maximumAttributeBytes else { throw FileSaveRestriction.metadataTooLarge }
        if count == 0 { return [:] }
        var names = [CChar](repeating: 0, count: count)
        let actual = names.withUnsafeMutableBufferPointer { flistxattr(descriptor, $0.baseAddress, $0.count, 0) }
        guard actual == count else { throw FileSaveRestriction.changedDuringRead }
        var budget = maximumAttributeBytes - count
        var result: [String: Data] = [:]
        for bytes in names.map({ UInt8(bitPattern: $0) }).split(separator: 0) {
            guard let name = String(bytes: bytes, encoding: .utf8) else { throw FileSaveRestriction.metadataUnavailable }
            if name == "com.apple.ResourceFork" || name == "com.apple.decmpfs" {
                throw FileSaveRestriction.unsupportedAttributes
            }
            let size = fgetxattr(descriptor, name, nil, 0, 0, 0)
            guard size >= 0 else { throw FileSaveRestriction.metadataUnavailable }
            guard size <= budget else { throw FileSaveRestriction.metadataTooLarge }
            var data = Data(count: size)
            let read = data.withUnsafeMutableBytes { fgetxattr(descriptor, name, $0.baseAddress, $0.count, 0, 0) }
            guard read == size else { throw FileSaveRestriction.changedDuringRead }
            result[name] = data
            budget -= size
        }
        return result
    }

    static func capture(_ descriptor: Int32, selectedURL: URL) throws -> FileSaveBaseline {
        let before = try FileMetadata.read(descriptor)
        if let reason = before.restriction() { throw reason }
        var leaf = stat()
        guard lstat(selectedURL.path, &leaf) == 0 else { throw FileSaveRestriction.changedDuringRead }
        if leaf.st_mode & mode_t(S_IFMT) == mode_t(S_IFLNK) { throw FileSaveRestriction.selectedSymlink }
        guard before == FileMetadata(leaf) else { throw FileSaveRestriction.changedDuringRead }
        let resolved = selectedURL.resolvingSymlinksInPath().standardizedFileURL
        let parentURL = resolved.deletingLastPathComponent()
        guard try parentURL.resourceValues(forKeys: [.volumeIsLocalKey]).volumeIsLocal == true else {
            throw FileSaveRestriction.nonlocalVolume
        }
        let parent = open(parentURL.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard parent >= 0 else { throw FileSaveRestriction.metadataUnavailable }
        defer { close(parent) }
        let parentMetadata = try FileMetadata.read(parent)
        guard !(try hasACL(descriptor)), !(try hasACL(parent)) else { throw FileSaveRestriction.extendedACL }
        let attributes = try attributes(descriptor)
        guard before == (try FileMetadata.read(descriptor)) else { throw FileSaveRestriction.changedDuringRead }
        return FileSaveBaseline(metadata: before, attributes: attributes,
            parent: FileParentBaseline(url: parentURL, device: parentMetadata.device, inode: parentMetadata.inode,
                                       mode: parentMetadata.mode, uid: parentMetadata.uid,
                                       gid: parentMetadata.gid, flags: parentMetadata.flags))
    }

    static func eligibility(_ result: Result<FileSaveBaseline, Error>, descriptor: Int32,
                            selectedURL: URL, byteCount: Int) -> FileSaveEligibility {
        do {
            let before = try result.get()
            let after = try capture(descriptor, selectedURL: selectedURL)
            guard before == after, after.metadata.size == byteCount else { return .ineligible(.changedDuringRead) }
            return .eligible(after)
        } catch {
            return .ineligible(error as? FileSaveRestriction ?? .metadataUnavailable)
        }
    }
}
