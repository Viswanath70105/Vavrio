// Disposable investigation, not application storage code. No path arguments.
// PASS means fixture assertions held; observed metadata differences may be losses.
import Darwin
import Foundation

func posixError() -> NSError { NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw NSError(domain: "ProbeAssertion", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}
func info(_ url: URL) throws -> stat {
    var value = stat()
    guard lstat(url.path, &value) == 0 else { throw posixError() }
    return value
}
func aclText(_ url: URL) throws -> String {
    guard let acl = acl_get_file(url.path, ACL_TYPE_EXTENDED) else {
        // macOS also reports ENOENT when an existing item has no extended ACL.
        if errno == ENOENT { _ = try info(url); return "" }
        throw posixError()
    }
    defer { acl_free(UnsafeMutableRawPointer(acl)) }
    guard let text = acl_to_text(acl, nil) else { throw posixError() }
    defer { acl_free(text) }
    return String(cString: text)
}
func attributes(_ url: URL) throws -> [String: Data] {
    let count = listxattr(url.path, nil, 0, XATTR_NOFOLLOW)
    guard count >= 0 else { throw posixError() }
    if count == 0 { return [:] }
    var buffer = [CChar](repeating: 0, count: count)
    let read = buffer.withUnsafeMutableBufferPointer {
        listxattr(url.path, $0.baseAddress, $0.count, XATTR_NOFOLLOW)
    }
    guard read >= 0 else { throw posixError() }
    let names = buffer.prefix(read).map { UInt8(bitPattern: $0) }.split(separator: 0)
    var result: [String: Data] = [:]
    for nameBytes in names {
        let name = String(decoding: nameBytes, as: UTF8.self)
        let size = getxattr(url.path, name, nil, 0, 0, XATTR_NOFOLLOW)
        guard size >= 0 else { throw posixError() }
        var value = Data(count: size)
        let actual = value.withUnsafeMutableBytes {
            getxattr(url.path, name, $0.baseAddress, $0.count, 0, XATTR_NOFOLLOW)
        }
        guard actual == size else { throw posixError() }
        result[name] = value
    }
    return result
}
func setAttribute(_ name: String, _ value: String, on url: URL) throws {
    try setAttribute(name, Data(value.utf8), on: url)
}
func setAttribute(_ name: String, _ bytes: Data, on url: URL) throws {
    let result = bytes.withUnsafeBytes { setxattr(url.path, name, $0.baseAddress, $0.count, 0, XATTR_NOFOLLOW) }
    guard result == 0 else { throw posixError() }
}
func finderMetadata(_ source: URL) throws {
    var url = source
    var values = URLResourceValues()
    values.labelNumber = 6
    try url.setResourceValues(values)
    let comment = try PropertyListSerialization.data(fromPropertyList: "fixture comment", format: .binary, options: 0)
    try setAttribute("com.apple.metadata:kMDItemFinderComment", comment, on: source)
}
func chmodFixture(_ url: URL, _ mode: mode_t) throws {
    guard chmod(url.path, mode) == 0 else { throw posixError() }
}
func command(_ executable: String, _ arguments: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    let output = Pipe()
    process.standardOutput = output
    process.standardError = output
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    try require(process.terminationStatus == 0, "Fixture command failed (exit \(process.terminationStatus), \(data.count) diagnostic bytes)")
}

struct Snapshot {
    let metadata: stat
    let bytes: Data
    let acl: String
    let xattrs: [String: Data]
    init(_ url: URL) throws {
        metadata = try info(url)
        try require(metadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG), "Snapshot requires a regular fixture")
        bytes = try Data(contentsOf: url)
        acl = try aclText(url)
        xattrs = try attributes(url)
    }
    func compared(with other: Snapshot) -> [String: Bool] {
        ["bytes": bytes == other.bytes,
         "identity": metadata.st_dev == other.metadata.st_dev && metadata.st_ino == other.metadata.st_ino,
         "mode": metadata.st_mode == other.metadata.st_mode,
         "owner": metadata.st_uid == other.metadata.st_uid && metadata.st_gid == other.metadata.st_gid,
         "flags": metadata.st_flags == other.metadata.st_flags,
         "birth": metadata.st_birthtimespec.tv_sec == other.metadata.st_birthtimespec.tv_sec
            && metadata.st_birthtimespec.tv_nsec == other.metadata.st_birthtimespec.tv_nsec,
         "mtime": metadata.st_mtimespec.tv_sec == other.metadata.st_mtimespec.tv_sec
            && metadata.st_mtimespec.tv_nsec == other.metadata.st_mtimespec.tv_nsec,
         "acl": acl == other.acl, "xattrs": xattrs == other.xattrs]
    }
}

final class Probe {
    let fm = FileManager.default
    let root: URL
    let old = Data("original\n".utf8)
    let new = Data("replaced\n".utf8)
    var passed = 0
    var failed = 0
    init() throws {
        root = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
            .deletingLastPathComponent().appendingPathComponent("replacement-fixtures-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    }
    func emit(_ fields: [String: Any]) {
        let data = try! JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
    func run(_ name: String, _ body: (URL) throws -> Void) {
        do {
            let directory = root.appendingPathComponent(name)
            try fm.createDirectory(at: directory, withIntermediateDirectories: false)
            let sentinel = directory.appendingPathComponent("unrelated")
            try old.write(to: sentinel)
            try body(directory)
            try require(Data(contentsOf: sentinel) == old, "Unrelated sentinel changed")
            passed += 1
            emit(["case": name, "result": "PASS"])
        } catch {
            failed += 1
            let error = error as NSError
            let underlying = (error.userInfo[NSUnderlyingErrorKey] as? NSError)
            emit(["case": name, "result": "FAIL", "error": "\(error.domain):\(error.code)",
                  "underlying": underlying.map { "\($0.domain):\($0.code)" } ?? "none",
                  "detail": error.domain == "ProbeAssertion" ? error.localizedDescription : "fixture/API error"])
        }
    }
    func pair(_ directory: URL) throws -> (URL, URL) {
        let source = directory.appendingPathComponent("source")
        let stageDirectory = directory.appendingPathComponent("private-stage")
        try fm.createDirectory(at: stageDirectory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let stage = stageDirectory.appendingPathComponent("replacement")
        try old.write(to: source)
        try new.write(to: stage)
        try chmodFixture(source, 0o751)
        try chmodFixture(stage, 0o600)
        try fm.setAttributes([.creationDate: Date(timeIntervalSince1970: 946684800)], ofItemAtPath: source.path)
        return (source, stage)
    }
    func replace(_ source: URL, _ stage: URL, options: FileManager.ItemReplacementOptions = []) throws {
        _ = try fm.replaceItemAt(source, withItemAt: stage, backupItemName: nil, options: options)
    }
    func errorFields(_ body: () throws -> Void) -> [String: Any] {
        do { try body(); return ["threw": false] }
        catch {
            let error = error as NSError
            var fields: [String: Any] = ["threw": true, "error": "\(error.domain):\(error.code)"]
            if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
                fields["underlying"] = "\(underlying.domain):\(underlying.code)"
            }
            fields["errorKeys"] = error.userInfo.keys.sorted()
            return fields
        }
    }
    func metadataCase(_ name: String, copyOriginal: Bool = false,
                      seed: (URL) throws -> Void = { _ in }) {
        run(name) { directory in
            let (source, stage) = try self.pair(directory)
            try seed(source)
            let before = try Snapshot(source)
            if copyOriginal {
                try self.fm.removeItem(at: stage)
                try self.fm.copyItem(at: source, to: stage)
                try self.new.write(to: stage)
            } else {
                try setAttribute("com.vavrio.stage", "stage-only", on: stage)
                try setAttribute("com.vavrio.shared", "stage-value", on: stage)
            }
            try require(info(source).st_dev == info(stage).st_dev, "Staging is not on the same volume")
            try self.replace(source, stage)
            let after = try Snapshot(source)
            var fields: [String: Any] = ["observation": name, "sameAsOriginal": before.compared(with: after),
                                       "xattrNames": after.xattrs.keys.sorted(),
                                       "missingXattrs": before.xattrs.keys.filter { after.xattrs[$0] == nil }.sorted(),
                                       "changedXattrs": before.xattrs.keys.filter { after.xattrs[$0] != nil && after.xattrs[$0] != before.xattrs[$0] }.sorted(),
                                       "addedXattrs": after.xattrs.keys.filter { before.xattrs[$0] == nil }.sorted(),
                                       "flagsBefore": before.metadata.st_flags, "flagsAfter": after.metadata.st_flags,
                                       "mode": String(after.metadata.st_mode & 0o7777, radix: 8)]
            fields["stageConsumed"] = !self.fm.fileExists(atPath: stage.path)
            self.emit(fields)
            try require(after.bytes == self.new, "Replacement bytes differ")
            try require(!self.fm.fileExists(atPath: stage.path), "Successful replacement left staging file")
            if copyOriginal {
                let preserved = before.compared(with: after)
                try require(["mode", "owner", "flags", "birth", "acl", "xattrs"].allSatisfy { preserved[$0] == true },
                            "Copy-based preparation did not preserve tested metadata")
            }
        }
    }
    func execute() {
        metadataCase("default-metadata")
        metadataCase("default-xattrs") {
            try setAttribute("com.vavrio.source", "source-only", on: $0)
            try setAttribute("com.vavrio.shared", "source-value", on: $0)
        }
        metadataCase("default-acl") { try command("/bin/chmod", ["+a", "everyone allow read,readattr,readextattr,readsecurity", $0.path]) }
        metadataCase("default-flags") { guard chflags($0.path, UInt32(UF_NODUMP)) == 0 else { throw posixError() } }
        metadataCase("default-finder-metadata", seed: finderMetadata)
        metadataCase("copy-original-metadata", copyOriginal: true) {
            try setAttribute("com.vavrio.source", "source-only", on: $0)
            try finderMetadata($0)
            try command("/bin/chmod", ["+a", "everyone allow read,readattr,readextattr,readsecurity", $0.path])
            guard chflags($0.path, UInt32(UF_NODUMP | UF_HIDDEN)) == 0 else { throw posixError() }
        }
        metadataCase("copy-original-security-xattr", copyOriginal: true) {
            try setAttribute("com.apple.quarantine", "0081;5f000000;VavrioProbe;synthetic", on: $0)
        }
        run("private-directory-acl-inheritance") { d in
            let parent = d.appendingPathComponent("acl-parent")
            try self.fm.createDirectory(at: parent, withIntermediateDirectories: false)
            try command("/bin/chmod", ["+a", "everyone allow read,execute,file_inherit,directory_inherit", parent.path])
            let privateDirectory = parent.appendingPathComponent("private-stage")
            try self.fm.createDirectory(at: privateDirectory, withIntermediateDirectories: false,
                                        attributes: [.posixPermissions: 0o700])
            let stage = privateDirectory.appendingPathComponent("payload")
            try self.old.write(to: stage)
            try chmodFixture(stage, 0o600)
            let inheritedACL = try aclText(privateDirectory)
            self.emit(["observation": "private-directory-acl-inheritance",
                       "privateMode": String(try info(privateDirectory).st_mode & 0o777, radix: 8),
                       "privateDirectoryHasACL": !inheritedACL.isEmpty,
                       "stageHasACL": try !aclText(stage).isEmpty])
            try require(!inheritedACL.isEmpty, "Directory ACL inheritance fixture")
        }
        run("new-metadata-only") { d in
            let (source, stage) = try self.pair(d)
            let before = try Snapshot(source)
            try self.replace(source, stage, options: .usingNewMetadataOnly)
            let after = try Snapshot(source)
            self.emit(["observation": "new-metadata-only", "sameAsOriginal": before.compared(with: after),
                       "mode": String(after.metadata.st_mode & 0o7777, radix: 8)])
            try require(after.bytes == self.new && after.metadata.st_mode & 0o777 == 0o600, "New metadata option did not use staging mode")
        }
        run("missing-destination") { d in
            let (_, stage) = try self.pair(d)
            let missing = d.appendingPathComponent("missing")
            var fields = self.errorFields { try self.replace(missing, stage) }
            fields["observation"] = "missing-destination"
            fields["destinationExists"] = self.fm.fileExists(atPath: missing.path)
            fields["stageExists"] = self.fm.fileExists(atPath: stage.path)
            self.emit(fields)
            if fields["threw"] as? Bool == false {
                try require(Data(contentsOf: missing) == self.new, "Created destination bytes differ")
            }
        }
        run("missing-stage") { d in
            let (source, stage) = try self.pair(d)
            let before = try Snapshot(source)
            try self.fm.removeItem(at: stage)
            let fields = self.errorFields { try self.replace(source, stage) }
            self.emit(["observation": "missing-stage", "outcome": fields,
                       "sameAsOriginal": before.compared(with: try Snapshot(source))])
            try require(fields["threw"] as? Bool == true && Data(contentsOf: source) == self.old, "Missing staging did not preserve source")
        }
        run("preparation-failure") { d in
            let (source, _) = try self.pair(d)
            let fields = self.errorFields { try self.new.write(to: source.appendingPathComponent("not-a-directory")) }
            self.emit(["observation": "preparation-failure", "outcome": fields])
            try require(fields["threw"] as? Bool == true && Data(contentsOf: source) == self.old, "Preparation failure changed source")
        }
        run("nonwritable-parent") { d in
            let (source, stage) = try self.pair(d)
            try chmodFixture(d, 0o500)
            defer { try? chmodFixture(d, 0o700) }
            let before = try Snapshot(source)
            let fields = self.errorFields { try self.replace(source, stage) }
            self.emit(["observation": "nonwritable-parent", "outcome": fields,
                       "sameAsOriginal": before.compared(with: try Snapshot(source)),
                       "stageExists": self.fm.fileExists(atPath: stage.path)])
            try require(fields["threw"] as? Bool == true && Data(contentsOf: source) == self.old, "Permission failure did not preserve source")
        }
        run("immutable-source") { d in
            let (source, stage) = try self.pair(d)
            guard chflags(source.path, UInt32(UF_IMMUTABLE)) == 0 else { throw posixError() }
            defer { _ = chflags(source.path, 0); _ = chflags(stage.path, 0) }
            let fields = self.errorFields { try self.replace(source, stage) }
            self.emit(["observation": "immutable-source", "outcome": fields,
                       "sourceUnchanged": try Data(contentsOf: source) == self.old,
                       "stageExists": self.fm.fileExists(atPath: stage.path)])
            try require(fields["threw"] as? Bool == true && Data(contentsOf: source) == self.old, "Immutable failure did not preserve source")
        }
        run("unsupported-types") { d in
            let directory = d.appendingPathComponent("directory")
            let fifo = d.appendingPathComponent("fifo")
            try self.fm.createDirectory(at: directory, withIntermediateDirectories: false)
            guard mkfifo(fifo.path, 0o600) == 0 else { throw posixError() }
            try require(info(directory).st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR), "Directory classification")
            try require(info(fifo).st_mode & mode_t(S_IFMT) == mode_t(S_IFIFO), "FIFO classification")
            self.emit(["observation": "unsupported-types", "replacementInvoked": false,
                       "directoryAndFIFOClassified": true])
        }
        run("raw-symlink-replacement") { d in
            let (target, stage) = try self.pair(d)
            let selected = d.appendingPathComponent("symlink")
            try self.fm.createSymbolicLink(at: selected, withDestinationURL: target)
            let fields = self.errorFields { try self.replace(selected, stage) }
            self.emit(["observation": "raw-symlink-replacement", "outcome": fields,
                       "linkRemains": try info(selected).st_mode & mode_t(S_IFMT) == mode_t(S_IFLNK),
                       "targetUnchanged": try Data(contentsOf: target) == self.old])
        }
        run("raw-hardlink-replacement") { d in
            let (source, stage) = try self.pair(d)
            let alias = d.appendingPathComponent("hardlink")
            try self.fm.linkItem(at: source, to: alias)
            try require(info(source).st_nlink == 2, "Hard-link fixture setup")
            try self.replace(source, stage)
            self.emit(["observation": "raw-hardlink-replacement", "aliasUnchanged": try Data(contentsOf: alias) == self.old,
                       "sameIdentityAfter": try info(source).st_ino == info(alias).st_ino])
            try require(Data(contentsOf: source) == self.new, "Hard-link replacement bytes")
        }
        run("external-content-change") { d in
            let (source, _) = try self.pair(d)
            let date = Date(timeIntervalSince1970: 1700000000)
            try self.fm.setAttributes([.modificationDate: date], ofItemAtPath: source.path)
            let before = try Snapshot(source)
            try Data("external\n".utf8).write(to: source)
            try self.fm.setAttributes([.modificationDate: date], ofItemAtPath: source.path)
            let after = try Snapshot(source)
            self.emit(["observation": "external-content-change", "sameAsOriginal": before.compared(with: after),
                       "sameSize": before.bytes.count == after.bytes.count])
            try require(before.bytes != after.bytes && before.metadata.st_ino == after.metadata.st_ino, "External edit fixture")
        }
        run("external-identity-change") { d in
            let (source, stage) = try self.pair(d)
            let before = try Snapshot(source)
            try self.old.write(to: stage)
            guard rename(stage.path, source.path) == 0 else { throw posixError() }
            let after = try Snapshot(source)
            self.emit(["observation": "external-identity-change", "sameAsOriginal": before.compared(with: after)])
            try require(before.bytes == after.bytes && before.metadata.st_ino != after.metadata.st_ino, "Identity replacement fixture")
        }
        run("check-replace-interleaving") { d in
            let (source, stage) = try self.pair(d)
            let baseline = try Snapshot(source)
            try require(baseline.bytes == Data(contentsOf: source), "Preflight baseline")
            try Data("external\n".utf8).write(to: source)
            try self.replace(source, stage)
            self.emit(["observation": "check-replace-interleaving", "externalEditOverwritten": try Data(contentsOf: source) == self.new,
                       "actualConcurrencyTest": false])
        }
        run("coordinated-replacement") { d in
            let (source, stage) = try self.pair(d)
            var coordinationError: NSError?
            var writeError: Error?
            var called = false
            NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: source, options: .forReplacing, error: &coordinationError) { url in
                called = true
                do { try self.replace(url, stage) } catch { writeError = error }
            }
            if let error = coordinationError ?? (writeError as NSError?) { throw error }
            try require(called && Data(contentsOf: source) == self.new, "Coordinated replacement")
            self.emit(["observation": "coordinated-replacement", "accessorCalled": called, "otherPresentersTested": false])
        }
        run("new-save-as-exclusive-publish") { d in
            let (source, stage) = try self.pair(d)
            let destination = d.appendingPathComponent("new-destination")
            // Fixture policy experiment: explicit source rwx bits, no special bits.
            try chmodFixture(stage, info(source).st_mode & 0o777)
            guard renamex_np(stage.path, destination.path, UInt32(RENAME_EXCL)) == 0 else { throw posixError() }
            let published = try Snapshot(destination)
            let contender = d.appendingPathComponent("contender")
            try self.old.write(to: contender)
            let result = renamex_np(contender.path, destination.path, UInt32(RENAME_EXCL))
            let code = errno
            try require(result == -1 && code == EEXIST, "Exclusive publish overwrote existing destination")
            try require(Data(contentsOf: destination) == self.new && Data(contentsOf: contender) == self.old, "Exclusive publish failure changed bytes")
            self.emit(["observation": "new-save-as-exclusive-publish", "mode": String(published.metadata.st_mode & 0o7777, radix: 8),
                       "existingDestinationError": "NSPOSIXErrorDomain:\(code)", "newFileXattrNames": published.xattrs.keys.sorted()])
        }
    }
}

@main
struct Main {
    static func main() throws {
        let probe = try Probe()
        probe.execute()
        // Fixtures may include metadata flags, but immutable flags are cleared in-case.
        try probe.fm.removeItem(at: probe.root)
        probe.emit(["summary": true, "passed": probe.passed, "failed": probe.failed,
                    "ownedFixtureRootRemoved": !probe.fm.fileExists(atPath: probe.root.path)])
        if probe.failed > 0 { exit(1) }
    }
}
