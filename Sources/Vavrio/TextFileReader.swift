import Darwin
import Foundation

struct TextFile: Sendable {
    let url: URL
    let text: String
    let originalData: Data

    var hasUTF8BOM: Bool {
        originalData.starts(with: [0xEF, 0xBB, 0xBF])
    }
}

enum TextFileReadError: LocalizedError, Equatable {
    case unsupportedLocation
    case notRegularFile
    case tooLarge
    case invalidUTF8
    case containsNullBytes

    var errorDescription: String? {
        switch self {
        case .unsupportedLocation:
            "Choose a file on this Mac."
        case .notRegularFile:
            "Choose a regular text file, rather than a folder or special file."
        case .tooLarge:
            "This viewer supports files up to 2 MiB. Choose a smaller UTF-8 text file."
        case .invalidUTF8:
            "The file is not valid UTF-8 text. This version does not convert other encodings."
        case .containsNullBytes:
            "The file contains NUL bytes and is not supported as plain text by this viewer."
        }
    }
}

enum TextFileReader {
    // A provisional scope limit, not a measured performance guarantee.
    static let maximumByteCount = 2 * 1024 * 1024

    static func read(_ url: URL) throws -> TextFile {
        guard url.isFileURL else { throw TextFileReadError.unsupportedLocation }

        var openingError = EINVAL
        let descriptor = url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return Int32(-1) }
            // Nonblocking open lets us reject a FIFO without waiting for a writer.
            let descriptor = Darwin.open(path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)
            openingError = errno
            return descriptor
        }
        guard descriptor >= 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(openingError))
        }

        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }

        // Inspect the opened descriptor, so path changes cannot bypass this check.
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        guard metadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else {
            throw TextFileReadError.notRegularFile
        }
        guard metadata.st_size <= maximumByteCount else {
            throw TextFileReadError.tooLarge
        }

        var data = Data()
        // Enforce the limit during reading too, in case the file grows after fstat.
        while true {
            let count = min(64 * 1024, maximumByteCount + 1 - data.count)
            guard let chunk = try handle.read(upToCount: count), !chunk.isEmpty else { break }
            data.append(chunk)
            guard data.count <= maximumByteCount else { throw TextFileReadError.tooLarge }
        }

        guard !data.contains(0) else { throw TextFileReadError.containsNullBytes }
        let textData = data.starts(with: [0xEF, 0xBB, 0xBF]) ? data.dropFirst(3) : data[...]
        // This strict decoder preserves U+FEFF and supports macOS 14. NUL was
        // rejected above, so only this temporary buffer's terminator ends text.
        let terminatedUTF8 = textData.map { CChar(bitPattern: $0) } + [0]
        let text = terminatedUTF8.withUnsafeBufferPointer { buffer in
            String(validatingCString: buffer.baseAddress!) // Always contains the terminator.
        }
        guard let text else {
            throw TextFileReadError.invalidUTF8
        }
        return TextFile(url: url, text: text, originalData: data)
    }
}
