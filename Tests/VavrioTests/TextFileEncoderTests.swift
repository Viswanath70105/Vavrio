import Foundation
import Testing
@testable import Vavrio

struct TextFileEncoderTests {
    @Test(arguments: [false, true], [
        "", "edited\r\ntext\nwith\rno final newline", "தமிழ் 👩🏽‍💻",
        "caf\u{E9}", "cafe\u{301}", "A\u{FEFF}B"
    ])
    func encodesExactText(hasBOM: Bool, text: String) throws {
        let signature = hasBOM ? Data([0xEF, 0xBB, 0xBF]) : Data()
        #expect(try TextFileEncoder.encode(text, hasUTF8BOM: hasBOM) == signature + Data(text.utf8))
    }

    @Test(arguments: [1, 2, 3])
    func preservesLeadingTextBOMWithSignature(count: Int) throws {
        let text = String(repeating: "\u{FEFF}", count: count) + "A"
        let expected = Data(Array(repeating: [UInt8(0xEF), 0xBB, 0xBF], count: count + 1).flatMap { $0 } + [0x41])
        #expect(try TextFileEncoder.encode(text, hasUTF8BOM: true) == expected)
    }

    @Test(arguments: ["\u{FEFF}", "\u{FEFF}A", "\u{FEFF}\u{FEFF}A", "\u{FEFF}\u{301}A"])
    func rejectsLeadingTextBOMWithoutSignature(text: String) {
        #expect(throws: TextFileEncodingError.ambiguousLeadingBOM) {
            try TextFileEncoder.encode(text, hasUTF8BOM: false)
        }
    }

    @Test(arguments: [false, true], ["\0", "before\0after", "தமிழ்\0👋"])
    func rejectsNullCharacters(hasBOM: Bool, text: String) {
        #expect(throws: TextFileEncodingError.containsNullBytes) {
            try TextFileEncoder.encode(text, hasUTF8BOM: hasBOM)
        }
    }

    @Test(arguments: [false, true], ["a", "é", "👋"])
    func enforcesEncodedByteLimit(hasBOM: Bool, unit: String) throws {
        let signature = hasBOM ? Data([0xEF, 0xBB, 0xBF]) : Data()
        let budget = TextFileReader.maximumByteCount - signature.count
        let unitSize = unit.utf8.count
        let text = String(repeating: unit, count: budget / unitSize)
            + String(repeating: "a", count: budget % unitSize)
        let expected = signature + Data(text.utf8)
        #expect(expected.count == TextFileReader.maximumByteCount)
        #expect(try TextFileEncoder.encode(text, hasUTF8BOM: hasBOM) == expected)
        #expect(throws: TextFileEncodingError.tooLarge) {
            try TextFileEncoder.encode(text + "a", hasUTF8BOM: hasBOM)
        }
        #expect(throws: TextFileEncodingError.tooLarge) {
            try TextFileEncoder.encode(text + unit, hasUTF8BOM: hasBOM)
        }
    }
}
