import Foundation
import Testing
@testable import NotchIsland

@Suite("Command wire format")
struct PlaybackCommandTests {
    private func object(_ command: PlaybackCommand) throws -> [String: Any] {
        let data = try #require(command.wireFormat)
        // Every command has to be one line: the bridge reads them newline by
        // newline.
        #expect(data.last == 0x0A)
        #expect(data.dropLast().contains(0x0A) == false)

        return try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
    }

    @Test("Transport commands use the names the bridge expects")
    func transportCommands() throws {
        #expect(try object(.playPause)["cmd"] as? String == "playpause")
        #expect(try object(.next)["cmd"] as? String == "next")
        #expect(try object(.previous)["cmd"] as? String == "previous")
        #expect(try object(.refresh)["cmd"] as? String == "refresh")
    }

    @Test("Seeking carries its position")
    func seekCarriesPosition() throws {
        let payload = try object(.seek(42.5))
        #expect(payload["cmd"] as? String == "seek")
        #expect(payload["value"] as? Double == 42.5)
    }

    @Test("A negative seek is clamped rather than sent as-is")
    func seekIsClamped() throws {
        #expect(try object(.seek(-10))["value"] as? Double == 0)
    }
}
