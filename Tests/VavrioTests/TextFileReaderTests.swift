import Darwin
import Foundation
import Testing
@testable import Vavrio

@Suite(.serialized)
struct TextFileReaderTests {
    private func withDirectory(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Vavrio Tests \(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }

    @Test func readsUnicodeAndPreservesLineEndingsAndSource() throws {
        try withDirectory { directory in
            let url = directory.appendingPathComponent("தமிழ் source file.swift")
            let original = Data("// வணக்கம் 👋\r\nlet greeting = \"café\"\n\t// τέλος\n".utf8)
            try original.write(to: url)
            let file = try TextFileReader.read(url)
            #expect(file.url == url)
            #expect(Data(file.text.utf8) == original)
            #expect(try Data(contentsOf: url) == original)
        }
    }

    @Test func readsEmptyFile() throws {
        try withDirectory { directory in
            let url = directory.appendingPathComponent("empty.txt")
            try Data().write(to: url)
            #expect(try TextFileReader.read(url).text.isEmpty)
        }
    }

    @Test func acceptsUTF8BOMWithoutChangingSource() throws {
        try withDirectory { directory in
            let url = directory.appendingPathComponent("bom.txt")
            let original = Data([0xEF, 0xBB, 0xBF]) + Data("hello\r\n".utf8)
            try original.write(to: url)
            #expect(try TextFileReader.read(url).text == "hello\r\n")
            #expect(try Data(contentsOf: url) == original)
        }
    }

    @Test func rejectsInvalidUTF8WithoutChangingSource() throws {
        try withDirectory { directory in
            let url = directory.appendingPathComponent("invalid.txt")
            let original = Data([0xC3, 0x28])
            try original.write(to: url)
            #expect(throws: TextFileReadError.invalidUTF8) { try TextFileReader.read(url) }
            #expect(try Data(contentsOf: url) == original)
        }
    }

    @Test func rejectsNullBytes() throws {
        try withDirectory { directory in
            let url = directory.appendingPathComponent("binary.txt")
            try Data([0x61, 0, 0x62]).write(to: url)
            #expect(throws: TextFileReadError.containsNullBytes) { try TextFileReader.read(url) }
        }
    }

    @Test func acceptsExactLimitAndRejectsOneByteMore() throws {
        try withDirectory { directory in
            let url = directory.appendingPathComponent("boundary.txt")
            var data = Data(repeating: 0x61, count: TextFileReader.maximumByteCount)
            try data.write(to: url)
            #expect(try TextFileReader.read(url).text.utf8.count == data.count)
            data.append(0x61)
            try data.write(to: url)
            #expect(throws: TextFileReadError.tooLarge) { try TextFileReader.read(url) }
            #expect(try Data(contentsOf: url) == data)
        }
    }

    @Test func reportsMissingFile() throws {
        try withDirectory { directory in
            do {
                _ = try TextFileReader.read(directory.appendingPathComponent("missing.txt"))
                Issue.record("Expected a missing-file error.")
            } catch let error as NSError {
                #expect(error.domain == NSPOSIXErrorDomain)
                #expect(error.code == Int(ENOENT))
            }
        }
    }

    @Test func rejectsDirectoryAndFIFO() throws {
        try withDirectory { directory in
            #expect(throws: TextFileReadError.notRegularFile) { try TextFileReader.read(directory) }
            let fifo = directory.appendingPathComponent("pipe")
            let status = fifo.withUnsafeFileSystemRepresentation { mkfifo($0!, 0o600) }
            #expect(status == 0)
            #expect(throws: TextFileReadError.notRegularFile) { try TextFileReader.read(fifo) }
        }
    }

    @Test func followsRegularFileSymlinkAndKeepsSelectedName() throws {
        try withDirectory { directory in
            let target = directory.appendingPathComponent("target.swift")
            let link = directory.appendingPathComponent("alias.swift")
            try Data("let value = 42\n".utf8).write(to: target)
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
            let file = try TextFileReader.read(link)
            #expect(file.url == link)
            #expect(file.text == "let value = 42\n")
            #expect(try String(contentsOf: target, encoding: .utf8) == file.text)
        }
    }

    @Test func rejectsNonFileURL() {
        #expect(throws: TextFileReadError.unsupportedLocation) {
            try TextFileReader.read(URL(string: "https://example.com/file.swift")!)
        }
    }
}
