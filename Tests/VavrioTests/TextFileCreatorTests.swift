import Darwin
import Foundation
import Testing
@testable import Vavrio

@Suite(.serialized)
struct TextFileCreatorTests {
    private func fixture(_ body: (URL, URL) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Vavrio Create \(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        try await body(root, root.appendingPathComponent("new.md"))
    }
    @Test(arguments: [false, true], ["", "தமிழ் 👋 e\u{301}\r\nline\nlast\r", "A\u{FEFF}B"])
    func createsExactPrivateFileWithReusableBaseline(bom: Bool, text: String) async throws {
        try await fixture { (root, url) async throws -> Void in
            let result = await TextFileCreator.create(url, text: text, hasUTF8BOM: bom)
            guard case .created(let file, let warning) = result else {
                Issue.record("Expected created file: \(result)"); return
            }
            #expect(warning == nil)
            #expect(file.originalData == (try TextFileEncoder.encode(text, hasUTF8BOM: bom)))
            let baseline = try #require(file.saveEligibility.baseline)
            #expect(baseline.metadata.mode & 0o7777 == 0o600)
            #expect(baseline.metadata.uid == getuid() && baseline.metadata.links == 1)
            #expect(baseline.attributes["com.vavrio.source"] == nil)
            #expect(try FileManager.default.contentsOfDirectory(atPath: root.path) == ["new.md"])
            guard case .saved = await TextFileWriter.replace(file, with: text + "next") else {
                Issue.record("Created baseline cannot be saved"); return
            }
        }
    }
    @Test(arguments: ["file", "directory", "symlink", "dangling", "race"])
    func neverReplacesDestination(kind: String) async throws {
        try await fixture { (root, url) async throws -> Void in
            let other = root.appendingPathComponent("other")
            try Data("original".utf8).write(to: other)
            switch kind {
            case "file": try Data("original".utf8).write(to: url)
            case "directory": try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
            case "symlink": try FileManager.default.createSymbolicLink(at: url, withDestinationURL: other)
            case "dangling": try FileManager.default.createSymbolicLink(at: url, withDestinationURL: root.appendingPathComponent("absent"))
            default: break
            }
            let hooks = FileCreationHooks { phase, destination in
                if kind == "race", phase == .willPublish { try Data("racer".utf8).write(to: destination) }
            }
            guard case .notCreated(_, .destinationExists, _) = await TextFileCreator.create(url, text: "never overwrite", hasUTF8BOM: false, hooks: hooks) else {
                Issue.record("Expected collision refusal"); return
            }
            #expect(try String(contentsOf: other, encoding: .utf8) == "original")
            if kind == "file" || kind == "symlink" { #expect(try String(contentsOf: url, encoding: .utf8) == "original") }
            if kind == "race" { #expect(try String(contentsOf: url, encoding: .utf8) == "racer") }
            if kind == "dangling" { #expect(try FileManager.default.destinationOfSymbolicLink(atPath: url.path).hasSuffix("absent")) }
        }
    }
    @Test(arguments: ["nul", "bom", "large"])
    func rejectsInvalidTextWithoutCreation(kind: String) async throws {
        let text = kind == "nul" ? "\0" : kind == "bom" ? "\u{FEFF}ambiguous" : String(repeating: "x", count: TextFileReader.maximumByteCount + 1)
        try await fixture { (root, url) async throws -> Void in
            guard case .notCreated = await TextFileCreator.create(url, text: text, hasUTF8BOM: false) else {
                Issue.record("Expected invalid-text refusal"); return
            }
            #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
        }
    }
    @Test func acceptsExactByteLimit() async throws {
        try await fixture { (_, url) async throws -> Void in
            let text = String(repeating: "x", count: TextFileReader.maximumByteCount - 3)
            guard case .created(let file, _) = await TextFileCreator.create(url, text: text, hasUTF8BOM: true) else {
                Issue.record("Boundary creation failed"); return
            }
            #expect(file.originalData.count == TextFileReader.maximumByteCount)
        }
    }
    @Test(arguments: [FileCreationPhase.directoryReady, .beforeWrite, .staged, .willPublish, .didPublish, .willCleanup])
    func distinguishesFailureUncertaintyAndCleanup(phase failure: FileCreationPhase) async throws {
        try await fixture { (_, url) async throws -> Void in
            let hooks = FileCreationHooks { phase, _ in if phase == failure { throw CocoaError(.fileWriteUnknown) } }
            let result = await TextFileCreator.create(url, text: "saved", hasUTF8BOM: false, hooks: hooks)
            switch failure {
            case .didPublish:
                guard case .uncertain(let attempted, _, let recovery) = result else { Issue.record("Expected uncertain"); return }
                #expect(attempted == url && recovery != nil)
                #expect(try String(contentsOf: url, encoding: .utf8) == "saved")
            case .willCleanup:
                guard case .created(_, let warning) = result else { Issue.record("Expected successful save"); return }
                #expect(warning != nil)
            default:
                guard case .notCreated = result else { Issue.record("Expected non-creation"); return }
                #expect(!FileManager.default.fileExists(atPath: url.path))
            }
        }
    }
    @Test func refusesChangedParentAndPreservesStagedDataInMovedFolder() async throws {
        try await fixture { (root, _) async throws -> Void in
            let parent = root.appendingPathComponent("parent")
            let moved = root.appendingPathComponent("moved")
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
            let url = parent.appendingPathComponent("new.md")
            let hooks = FileCreationHooks { phase, _ in
                if phase == .staged {
                    try FileManager.default.moveItem(at: parent, to: moved)
                    try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
                }
            }
            guard case .notCreated = await TextFileCreator.create(url, text: "keep", hasUTF8BOM: false, hooks: hooks) else {
                Issue.record("Expected parent conflict"); return
            }
            #expect(!FileManager.default.fileExists(atPath: url.path))
            #expect(try FileManager.default.contentsOfDirectory(atPath: moved.path).count == 1)
        }
    }
    @Test(arguments: ["permissions", "acl", "flags"])
    func refusesUnsupportedParents(kind: String) async throws {
        try await fixture { (root, url) async throws -> Void in
            if kind == "permissions" { #expect(chmod(root.path, 0o500) == 0) }
            if kind == "flags" { #expect(chflags(root.path, UInt32(UF_IMMUTABLE)) == 0) }
            if kind == "acl" {
                let command = Process(); command.executableURL = URL(fileURLWithPath: "/bin/chmod")
                command.arguments = ["+a", "everyone allow read", root.path]
                try command.run(); command.waitUntilExit(); #expect(command.terminationStatus == 0)
            }
            defer { _ = chflags(root.path, 0); _ = chmod(root.path, 0o700) }
            guard case .notCreated = await TextFileCreator.create(url, text: "refuse", hasUTF8BOM: false) else {
                Issue.record("Expected unsupported parent refusal"); return
            }
            #expect(!FileManager.default.fileExists(atPath: url.path))
        }
    }
    @Test func postPublicationMetadataChangeIsUncertain() async throws {
        try await fixture { (_, url) async throws -> Void in
            let hooks = FileCreationHooks { phase, destination in
                if phase == .didPublish {
                    let bytes = Data("changed".utf8)
                    let result = bytes.withUnsafeBytes { setxattr(destination.path, "com.vavrio.external", $0.baseAddress, $0.count, 0, 0) }
                    guard result == 0 else { throw CocoaError(.fileWriteUnknown) }
                }
            }
            guard case .uncertain = await TextFileCreator.create(url, text: "published", hasUTF8BOM: false, hooks: hooks) else {
                Issue.record("Changed metadata was accepted"); return
            }
            #expect(try String(contentsOf: url, encoding: .utf8) == "published")
        }
    }

}
