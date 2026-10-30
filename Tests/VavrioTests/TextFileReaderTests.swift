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

    @Test(arguments: [0, 1, 2, 3], [
        "", "A", "first\r\nsecond\r\n", "first\nsecond\n", "first\rsecond\r",
        "one\r\ntwo\nthree\rfour", "no final newline", "A\u{FEFF}B",
        "வணக்கம் 👩🏽‍💻", "caf\u{E9}", "cafe\u{301}", "\u{301}a"
    ])
    func roundTripsOriginalBytes(bomCount: Int, content: String) throws {
        try withDirectory { directory in
            let url = directory.appendingPathComponent("தமிழ் round trip.txt")
            let bom: [UInt8] = [0xEF, 0xBB, 0xBF]
            let original = Data(Array(repeating: bom, count: bomCount).flatMap { $0 }) + Data(content.utf8)
            try original.write(to: url)

            let file = try TextFileReader.read(url)
            #expect(file.url == url)
            #expect(file.originalData == original)
            #expect(file.hasUTF8BOM == (bomCount > 0))
            let expectedText = Data(Array(repeating: bom, count: max(0, bomCount - 1)).flatMap { $0 })
                + Data(content.utf8)
            #expect(Data(file.text.utf8) == expectedText)
            #expect(try TextFileEncoder.encode(file.text, hasUTF8BOM: file.hasUTF8BOM) == original)
            #expect(try Data(contentsOf: url) == original)
        }
    }

    @Test(arguments: [false, true])
    func encodingEditsAndErrorsPreservesSnapshotAndSource(hasBOM: Bool) throws {
        try withDirectory { directory in
            let url = directory.appendingPathComponent("snapshot.txt")
            let signature = hasBOM ? Data([0xEF, 0xBB, 0xBF]) : Data()
            let original = signature + Data("original\r\n".utf8)
            try original.write(to: url)
            let file = try TextFileReader.read(url)

            // Later changes to the path cannot change the retained read snapshot.
            let externalBytes = Data("external edit\n".utf8)
            try externalBytes.write(to: url)
            let edited = "edited e\u{301}\r\n👋\nA\u{FEFF}B"
            #expect(try TextFileEncoder.encode(edited, hasUTF8BOM: file.hasUTF8BOM)
                == signature + Data(edited.utf8))
            #expect(throws: TextFileEncodingError.containsNullBytes) {
                try TextFileEncoder.encode("invalid\0text", hasUTF8BOM: file.hasUTF8BOM)
            }
            #expect(throws: TextFileEncodingError.tooLarge) {
                try TextFileEncoder.encode(
                    String(repeating: "a", count: TextFileReader.maximumByteCount + 1),
                    hasUTF8BOM: file.hasUTF8BOM
                )
            }
            if !hasBOM {
                #expect(throws: TextFileEncodingError.ambiguousLeadingBOM) {
                    try TextFileEncoder.encode("\u{FEFF}edited", hasUTF8BOM: file.hasUTF8BOM)
                }
            }
            #expect(file.originalData == original)
            #expect(file.hasUTF8BOM == hasBOM)
            #expect(Data(file.text.utf8) == Data("original\r\n".utf8))
            #expect(try TextFileEncoder.encode(file.text, hasUTF8BOM: file.hasUTF8BOM) == original)
            #expect(try Data(contentsOf: url) == externalBytes)
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

    @Test(arguments: [0, 1, 2, 3])
    func removesAtMostOneLeadingBOM(bomCount: Int) throws {
        try withDirectory { directory in
            let url = directory.appendingPathComponent("repeated-bom.txt")
            let bom: [UInt8] = [0xEF, 0xBB, 0xBF]
            let original = Data(Array(repeating: bom, count: bomCount).flatMap { $0 } + [0x41])
            let expected = Data(Array(repeating: bom, count: max(0, bomCount - 1)).flatMap { $0 } + [0x41])
            try original.write(to: url)
            #expect(Data(try TextFileReader.read(url).text.utf8) == expected)
            #expect(try Data(contentsOf: url) == original)
        }
    }

    @Test(arguments: [1, 2])
    func readsBOMOnlyFile(bomCount: Int) throws {
        try withDirectory { directory in
            let url = directory.appendingPathComponent("bom-only.txt")
            let bom: [UInt8] = [0xEF, 0xBB, 0xBF]
            let original = Data(Array(repeating: bom, count: bomCount).flatMap { $0 })
            let expected = Data(Array(repeating: bom, count: bomCount - 1).flatMap { $0 })
            try original.write(to: url)
            #expect(Data(try TextFileReader.read(url).text.utf8) == expected)
            #expect(try Data(contentsOf: url) == original)
        }
    }

    @Test func preservesInteriorBOM() throws {
        try withDirectory { directory in
            let url = directory.appendingPathComponent("interior-bom.txt")
            let original = Data([0x41, 0xEF, 0xBB, 0xBF, 0x42])
            try original.write(to: url)
            #expect(Data(try TextFileReader.read(url).text.utf8) == original)
            #expect(try Data(contentsOf: url) == original)
        }
    }

    @Test(arguments: [
        [UInt8(0xC3), 0x28], // Invalid continuation byte.
        [UInt8(0xE2), 0x82], // Truncated sequence.
        [UInt8(0xC0), 0xAF], // Overlong encoding.
        [UInt8(0xED), 0xA0, 0x80], // Surrogate scalar.
        [UInt8(0xF4), 0x90, 0x80, 0x80] // Above U+10FFFF.
    ])
    func rejectsInvalidUTF8AfterBOMWithoutChangingSource(invalidBytes: [UInt8]) throws {
        try withDirectory { directory in
            let url = directory.appendingPathComponent("invalid-after-bom.txt")
            let original = Data([0xEF, 0xBB, 0xBF] + invalidBytes)
            try original.write(to: url)
            #expect(throws: TextFileReadError.invalidUTF8) { try TextFileReader.read(url) }
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

    @Test(arguments: [false, true])
    func acceptsExactLimitAndRejectsOneByteMore(withBOM: Bool) throws {
        try withDirectory { directory in
            let url = directory.appendingPathComponent("boundary.txt")
            let prefix = withBOM ? Data([0xEF, 0xBB, 0xBF]) : Data()
            var data = prefix + Data(repeating: 0x61, count: TextFileReader.maximumByteCount - prefix.count)
            try data.write(to: url)
            let file = try TextFileReader.read(url)
            #expect(file.text.utf8.count == data.count - prefix.count)
            #expect(file.originalData == data)
            #expect(try TextFileEncoder.encode(file.text, hasUTF8BOM: file.hasUTF8BOM) == data)
            #expect(try Data(contentsOf: url) == data)
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
