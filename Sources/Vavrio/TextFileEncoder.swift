import Foundation

enum TextFileEncodingError: LocalizedError, Equatable {
    case containsNullBytes
    case tooLarge
    case ambiguousLeadingBOM

    var errorDescription: String? {
        switch self {
        case .containsNullBytes:
            "The text contains NUL characters and cannot be serialized as a supported text file."
        case .tooLarge:
            "The UTF-8 text, including any byte-order mark, exceeds the 2 MiB limit."
        case .ambiguousLeadingBOM:
            "The text begins with U+FEFF, which would be consumed as a byte-order mark when reopened. An explicit format change is required."
        }
    }
}

enum TextFileEncoder {
    // Returns bytes only; choosing a destination and writing belong to a later task.
    static func encode(_ text: String, hasUTF8BOM: Bool) throws -> Data {
        guard !text.utf8.contains(0) else { throw TextFileEncodingError.containsNullBytes }
        guard hasUTF8BOM || text.unicodeScalars.first?.value != 0xFEFF else {
            throw TextFileEncodingError.ambiguousLeadingBOM
        }

        let signature: [UInt8] = hasUTF8BOM ? [0xEF, 0xBB, 0xBF] : []
        let byteCount = text.utf8.count
        guard byteCount <= TextFileReader.maximumByteCount - signature.count else {
            throw TextFileEncodingError.tooLarge
        }

        var data = Data()
        data.reserveCapacity(signature.count + byteCount)
        data.append(contentsOf: signature)
        data.append(contentsOf: text.utf8)
        return data
    }
}
