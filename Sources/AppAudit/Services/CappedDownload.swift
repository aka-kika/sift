import Foundation

/// Reads a web answer only up to a size. `URLSession.data(for:)` holds the
/// whole body in memory before Sift cuts it, and its timeout fires only when
/// no data arrives, so a saved link to a 2 GB download was read in full.
enum CappedDownload {
    /// Link pages: only the first 128 KB is ever parsed.
    static let pageLimit = 131_072
    /// Update feeds and store answers: a long appcast is a few MB.
    static let feedLimit = 8 * 1024 * 1024

    enum OverLimit {
        /// Keep the first `limit` bytes and stop reading.
        case truncate
        /// Refuse the answer: a cut feed would not parse anyway.
        case fail
    }

    /// The body, read until `limit`. A server that says up front the body is
    /// bigger is not read at all when `overLimit` is `.fail`.
    static func data(for request: URLRequest, delegate: (any URLSessionTaskDelegate)?,
                     limit: Int, overLimit: OverLimit) async throws -> (Data, URLResponse) {
        let (bytes, response) = try await URLSession.shared.bytes(for: request, delegate: delegate)
        if overLimit == .fail, response.expectedContentLength > Int64(limit) {
            bytes.task.cancel()
            throw URLError(.dataLengthExceedsMaximum)
        }
        let data = try await collect(bytes, limit: limit, overLimit: overLimit)
        bytes.task.cancel()
        return (data, response)
    }

    static func collect<S: AsyncSequence>(_ bytes: S, limit: Int, overLimit: OverLimit) async throws -> Data
    where S.Element == UInt8 {
        var data = Data()
        data.reserveCapacity(min(limit, 64 * 1024))
        for try await byte in bytes {
            if data.count == limit {
                if overLimit == .fail { throw URLError(.dataLengthExceedsMaximum) }
                break
            }
            data.append(byte)
        }
        return data
    }
}
