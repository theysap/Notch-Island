import Foundation
import Testing
@testable import NotchIsland

@Suite("Line reassembly")
struct LineAccumulatorTests {
    @Test("A line split across reads is reassembled")
    func reassemblesSplitLine() {
        let accumulator = LineAccumulator()

        #expect(accumulator.append(Data(#"{"type":"re"#.utf8)).isEmpty)

        let lines = accumulator.append(Data("ady\"}\n".utf8))
        #expect(lines.count == 1)
        #expect(String(data: lines[0], encoding: .utf8) == #"{"type":"ready"}"#)
    }

    @Test("Several lines in one read are all returned")
    func splitsMultipleLines() {
        let accumulator = LineAccumulator()
        let lines = accumulator.append(Data("one\ntwo\nthree\n".utf8))

        #expect(lines.map { String(data: $0, encoding: .utf8) } == ["one", "two", "three"])
    }

    @Test("A trailing partial line is held back until it completes")
    func holdsPartialLine() {
        let accumulator = LineAccumulator()

        let first = accumulator.append(Data("complete\npar".utf8))
        #expect(first.map { String(data: $0, encoding: .utf8) } == ["complete"])

        let second = accumulator.append(Data("tial\n".utf8))
        #expect(second.map { String(data: $0, encoding: .utf8) } == ["partial"])
    }

    @Test("Blank lines are skipped")
    func skipsBlankLines() {
        let accumulator = LineAccumulator()
        let lines = accumulator.append(Data("one\n\n\ntwo\n".utf8))

        #expect(lines.count == 2)
    }

    @Test("A source that never sends a newline cannot grow the buffer forever")
    func enforcesLimit() {
        let accumulator = LineAccumulator(limit: 64)

        #expect(accumulator.append(Data(repeating: 0x41, count: 128)).isEmpty)
        // The oversized buffer is dropped, so a later well-formed line still
        // parses rather than being glued to the garbage in front of it.
        let lines = accumulator.append(Data("recovered\n".utf8))
        #expect(lines.map { String(data: $0, encoding: .utf8) } == ["recovered"])
    }
}
