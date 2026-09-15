import Foundation

public struct JSONPreviewAdapter: Sendable {
    public init() {}

    public func format(source: String) throws -> String {
        guard let data = source.data(using: .utf8) else {
            throw JSONPreviewError.invalidEncoding
        }

        let object: Any
        do {
            object = try JSONSerialization.jsonObject(
                with: data,
                options: [.fragmentsAllowed]
            )
        } catch {
            throw JSONPreviewError.invalidJSON(error.localizedDescription)
        }

        do {
            let formattedData = try JSONSerialization.data(
                withJSONObject: object,
                options: [
                    .prettyPrinted,
                    .withoutEscapingSlashes,
                    .fragmentsAllowed
                ]
            )
            guard let formatted = String(data: formattedData, encoding: .utf8) else {
                throw JSONPreviewError.invalidEncoding
            }
            return formatted
        } catch let error as JSONPreviewError {
            throw error
        } catch {
            throw JSONPreviewError.invalidJSON(error.localizedDescription)
        }
    }

    public func sourceOffset(
        forFormattedUTF8Offset formattedOffset: Int,
        source: String,
        formattedSource: String
    ) -> Int {
        let sourceBytes = Array(source.utf8)
        let formattedBytes = Array(formattedSource.utf8)
        guard !formattedBytes.isEmpty else { return 0 }

        var sourceIndex = 0
        var offsets = Array(repeating: 0, count: formattedBytes.count + 1)

        for formattedIndex in formattedBytes.indices {
            while sourceIndex < sourceBytes.count, isJSONWhitespace(sourceBytes[sourceIndex]) {
                sourceIndex += 1
            }
            offsets[formattedIndex] = sourceIndex

            let byte = formattedBytes[formattedIndex]
            guard !isJSONWhitespace(byte) else { continue }

            if sourceIndex < sourceBytes.count, sourceBytes[sourceIndex] == byte {
                sourceIndex += 1
            } else if let match = sourceBytes[sourceIndex...].firstIndex(of: byte) {
                sourceIndex = match + 1
            }
        }

        offsets[formattedBytes.count] = sourceIndex
        let clampedOffset = min(max(formattedOffset, 0), formattedBytes.count)
        return offsets[clampedOffset]
    }

    private func isJSONWhitespace(_ byte: UInt8) -> Bool {
        byte == 9 || byte == 10 || byte == 13 || byte == 32
    }
}

public enum JSONPreviewError: LocalizedError, Sendable, Equatable {
    case invalidEncoding
    case invalidJSON(String)

    public var errorDescription: String? {
        switch self {
        case .invalidEncoding:
            return "O ficheiro JSON não está codificado em UTF-8."
        case let .invalidJSON(details):
            return "JSON inválido: \(details)"
        }
    }
}
