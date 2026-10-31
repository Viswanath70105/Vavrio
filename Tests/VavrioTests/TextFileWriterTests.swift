import Darwin
import Foundation
import Testing
@testable import Vavrio

@Suite(.serialized)
struct TextFileWriterTests {
    private func fixture(_ body: (URL, URL) async throws -> Void) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Vavrio Writer \(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("தமிழ் source.swift")
        try Data("original\r\n".utf8).write(to: file)
        let sentinel = directory.appendingPathComponent("unrelated")
        try Data("leave untouched".utf8).write(to: sentinel)
        try await body(directory, file)
        #expect(try Data(contentsOf: sentinel) == Data("leave untouched".utf8))
    }
    private func xattr(_ file: URL, name: String = "com.vavrio.fixture", value: String = "preserve") throws {
        let bytes = Data(value.utf8)
        let status = bytes.withUnsafeBytes { setxattr(file.path, name, $0.baseAddress, $0.count, 0, 0) }
        #expect(status == 0)
    }
    private func command(_ path: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path); process.arguments = arguments
        try process.run(); process.waitUntilExit()
        #expect(process.terminationStatus == 0)
    }
    private func directories(_ parent: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: parent.path).filter { $0.hasPrefix(".vavrio-save-") }
    }
    private func notWritten(_ result: FileSaveResult) {
        guard case .notWritten = result else { Issue.record("Expected a pre-replacement refusal"); return }
    }

    @Test(arguments: [0, 1, 2, 3], [0o644, 0o751])
    func savesBytesMetadataAndFreshBaseline(boms: Int, mode: Int) async throws {
        try await fixture { directory, url in
            let signature = Data(Array(repeating: [UInt8(0xEF), 0xBB, 0xBF], count: boms).flatMap { $0 })
            let original = signature + Data("தமிழ் e\u{301}\r\n".utf8)
            try original.write(to: url)
            #expect(chmod(url.path, mode_t(mode)) == 0)
            try xattr(url)
            try xattr(url, name: "com.apple.quarantine", value: "0081;5f000000;VavrioTests;synthetic")
            var tagged = url
            var values = URLResourceValues(); values.labelNumber = 6
            try tagged.setResourceValues(values)
            #expect(chflags(url.path, UInt32(UF_NODUMP | UF_HIDDEN)) == 0)
            let file = try TextFileReader.read(url)
            let baseline = try #require(file.saveEligibility.baseline)
            let edited = (boms > 0 ? "\u{FEFF}" : "") + "edited 👋\r\nA\u{FEFF}B\n"
            let result = await TextFileWriter.replace(file, with: edited)
            guard case .saved(let saved, let warning) = result else { Issue.record("Expected saved, got \(result)"); return }
            #expect(warning == nil)
            #expect(saved.originalData == (try TextFileEncoder.encode(edited, hasUTF8BOM: boms > 0)))
            #expect(try Data(contentsOf: url) == saved.originalData)
            #expect(file.originalData == original)
            let fresh = try #require(saved.saveEligibility.baseline)
            #expect(fresh.metadata.inode != baseline.metadata.inode)
            #expect(fresh.metadata.samePreservedMetadata(as: baseline.metadata))
            #expect(fresh.attributes == baseline.attributes)
            #expect(try directories(directory).isEmpty)
            guard case .saved = await TextFileWriter.replace(saved, with: edited + "again") else {
                Issue.record("Fresh snapshot should support another save"); return
            }
        }
    }

    @Test(arguments: ["delete", "bytes", "inode", "permissions", "attribute", "parent"])
    func refusesChangedTargets(change: String) async throws {
        try await fixture { directory, url in
            let file = try TextFileReader.read(url)
            _ = try #require(file.saveEligibility.baseline)
            var activeURL = url
            switch change {
            case "delete": try FileManager.default.removeItem(at: url)
            case "bytes":
                let date = try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate]
                try Data("external\r\n".utf8).write(to: url)
                if let date { try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path) }
            case "inode":
                let other = directory.appendingPathComponent("different-inode")
                try file.originalData.write(to: other)
                #expect(rename(other.path, url.path) == 0)
            case "permissions": #expect(chmod(url.path, 0o600) == 0)
            case "attribute": try xattr(url, value: "external")
            default:
                let old = directory.appendingPathComponent("moved")
                try FileManager.default.moveItem(at: url, to: old)
                let second = directory.appendingPathComponent("new-parent")
                try FileManager.default.createDirectory(at: second, withIntermediateDirectories: false)
                activeURL = second.appendingPathComponent(url.lastPathComponent)
                try FileManager.default.moveItem(at: old, to: activeURL)
            }
            let expected = try? Data(contentsOf: activeURL)
            notWritten(await TextFileWriter.replace(file, with: "do not write"))
            #expect((try? Data(contentsOf: activeURL)) == expected)
            #expect(try directories(directory).isEmpty)
        }
    }

    @Test(arguments: ["symlink", "hardlink", "readonly", "special-mode", "immutable", "acl", "parent-acl", "resource-fork", "large-metadata"])
    func unsupportedSaveStillAllowsViewing(kind: String) async throws {
        try await fixture { directory, url in
            var selected = url
            switch kind {
            case "symlink":
                selected = directory.appendingPathComponent("alias")
                try FileManager.default.createSymbolicLink(at: selected, withDestinationURL: url)
            case "hardlink": try FileManager.default.linkItem(at: url, to: directory.appendingPathComponent("alias"))
            case "readonly": #expect(chmod(url.path, 0o400) == 0)
            case "special-mode": #expect(chmod(url.path, 0o1644) == 0)
            case "immutable": #expect(chflags(url.path, UInt32(UF_IMMUTABLE)) == 0)
            case "acl": try command("/bin/chmod", ["+a", "everyone allow read", url.path])
            case "parent-acl": try command("/bin/chmod", ["+a", "everyone allow read,file_inherit,directory_inherit", directory.path])
            case "resource-fork": try xattr(url, name: "com.apple.ResourceFork", value: "unsupported")
            default:
                for i in 0..<5 { try xattr(url, name: "com.vavrio.large\(i)", value: String(repeating: "x", count: 60_000)) }
            }
            defer { _ = chflags(url.path, 0); _ = chmod(url.path, 0o600) }
            let file = try TextFileReader.read(selected)
            #expect(file.text == "original\r\n")
            #expect(file.saveEligibility.baseline == nil)
            notWritten(await TextFileWriter.replace(file, with: "do not write"))
            #expect(try Data(contentsOf: url) == file.originalData)
            #expect(try directories(directory).isEmpty)
        }
    }

    @Test func rejectsOwnershipAndUnsupportedFlagsInPurePolicy() throws {
        try fixturePolicy()
    }
    private func fixturePolicy() throws {
        var value = stat(); value.st_mode = mode_t(S_IFREG) | 0o644
        value.st_nlink = 1; value.st_uid = getuid()
        #expect(FileMetadata(value).restriction() == nil)
        #expect(FileMetadata(value).restriction(currentUID: getuid() + 1) == .ownership)
        value.st_flags = UInt32(UF_APPEND)
        #expect(FileMetadata(value).restriction() == .flags)
    }

    @Test(arguments: ["\0", "\u{FEFF}ambiguous"])
    func rejectsInvalidTextWithoutFilesystemMutation(text: String) async throws {
        try await fixture { directory, url in
            let file = try TextFileReader.read(url)
            notWritten(await TextFileWriter.replace(file, with: text))
            #expect(try Data(contentsOf: url) == file.originalData)
            #expect(try directories(directory).isEmpty)
        }
    }

    @Test(arguments: [FileWritePhase.directoryReady, .beforeStageWrite, .willReplace])
    func injectedPreparationFailuresLeaveOriginal(phase failure: FileWritePhase) async throws {
        try await fixture { directory, url in
            let file = try TextFileReader.read(url)
            let hooks = FileWriteHooks { phase, _ in
                if phase == failure { throw CocoaError(.fileWriteNoPermission) }
            }
            notWritten(await TextFileWriter.replace(file, with: "edited", hooks: hooks))
            #expect(try Data(contentsOf: url) == file.originalData)
            #expect(try directories(directory).isEmpty)
        }
    }

    @Test func detectsEditAfterStaging() async throws {
        try await fixture { directory, url in
            let file = try TextFileReader.read(url)
            let hooks = FileWriteHooks { phase, _ in
                if phase == .staged { try Data("external".utf8).write(to: url) }
            }
            notWritten(await TextFileWriter.replace(file, with: "edited", hooks: hooks))
            #expect(try Data(contentsOf: url) == Data("external".utf8))
            #expect(try directories(directory).isEmpty)
        }
    }

    @Test func ambiguousPostCommitResultRetainsRecoveryDirectory() async throws {
        try await fixture { _, url in
            let file = try TextFileReader.read(url)
            let hooks = FileWriteHooks { phase, _ in
                if phase == .didReplace { throw CocoaError(.fileReadUnknown) }
            }
            let result = await TextFileWriter.replace(file, with: "edited", hooks: hooks)
            guard case .uncertain(_, let recovery) = result else { Issue.record("Expected uncertain result"); return }
            let path = try #require(recovery)
            #expect(FileManager.default.fileExists(atPath: path.path))
            #expect(try Data(contentsOf: url) == Data("edited".utf8))
            #expect(file.originalData == Data("original\r\n".utf8))
        }
    }

    @Test func cleanupFailureDoesNotDisguiseSuccessfulSave() async throws {
        try await fixture { _, url in
            let file = try TextFileReader.read(url)
            let hooks = FileWriteHooks { phase, _ in
                if phase == .willCleanup { throw CocoaError(.fileWriteNoPermission) }
            }
            let result = await TextFileWriter.replace(file, with: "edited", hooks: hooks)
            guard case .saved(let saved, let warning) = result else { Issue.record("Expected saved with cleanup warning"); return }
            #expect(warning != nil)
            #expect(saved.originalData == Data("edited".utf8))
        }
    }

    @Test func documentsResidualUncooperativeWriterRace() async throws {
        try await fixture { _, url in
            let file = try TextFileReader.read(url)
            let hooks = FileWriteHooks { phase, _ in
                if phase == .willReplace { try Data("late external edit".utf8).write(to: url) }
            }
            guard case .saved = await TextFileWriter.replace(file, with: "edited", hooks: hooks) else {
                Issue.record("Expected controlled interleaving to reach replacement"); return
            }
            #expect(try Data(contentsOf: url) == Data("edited".utf8))
        }
    }

    @Test func refusesChangedParentWithSameLeafIdentity() async throws {
        try await fixture { directory, _ in
            let manager = FileManager.default
            let parent = directory.appendingPathComponent("parent")
            let moved = directory.appendingPathComponent("old-parent")
            try manager.createDirectory(at: parent, withIntermediateDirectories: false)
            let url = parent.appendingPathComponent("file")
            try Data("original".utf8).write(to: url)
            let snapshot = try TextFileReader.read(url)
            _ = try #require(snapshot.saveEligibility.baseline)
            try manager.moveItem(at: parent, to: moved)
            try manager.createDirectory(at: parent, withIntermediateDirectories: false)
            try manager.moveItem(at: moved.appendingPathComponent("file"), to: url)
            notWritten(await TextFileWriter.replace(snapshot, with: "do not write"))
            #expect(try Data(contentsOf: url) == snapshot.originalData)
            #expect(try directories(parent).isEmpty)
        }
    }
}
