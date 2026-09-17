import Foundation

/// Reassembles newline-delimited records from arbitrarily chunked pipe reads.
///
/// A single read can split a JSON line in half or deliver several at once, and
/// artwork lines are large enough that both happen routinely.
final class LineAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()

    /// Guards against a source that never emits a newline growing the buffer
    /// without bound.
    private let limit: Int

    init(limit: Int = 32 * 1024 * 1024) {
        self.limit = limit
    }

    /// Appends a chunk and returns every complete line it produced.
    func append(_ chunk: Data) -> [Data] {
        lock.lock()
        defer { lock.unlock() }

        buffer.append(chunk)

        if buffer.count > limit {
            buffer.removeAll(keepingCapacity: false)
            return []
        }

        var lines: [Data] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<newline]
            if !line.isEmpty {
                lines.append(Data(line))
            }
            buffer.removeSubrange(buffer.startIndex...newline)
        }
        return lines
    }

    func reset() {
        lock.lock()
        buffer.removeAll(keepingCapacity: false)
        lock.unlock()
    }
}
