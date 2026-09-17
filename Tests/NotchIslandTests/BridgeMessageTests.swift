import Foundation
import Testing
@testable import NotchIsland

@Suite("Bridge wire format")
struct BridgeMessageTests {
    @Test("A state message becomes a now-playing snapshot")
    func decodesState() throws {
        let json = """
        {"type":"state","payload":{"title":"Bad Boyz","artist":"Release - Topic",\
        "isPlaying":true,"appName":"Safari","duration":227.881,"elapsedTime":12.5,\
        "playbackRate":1,"timestamp":1789650250.2,"trackIdentifier":"3095740",\
        "bundleIdentifier":"com.apple.WebKit.GPU","parentBundleIdentifier":"com.apple.Safari"}}
        """

        let message = try #require(BridgeMessage.decode(line: Data(json.utf8)))
        guard case .state(let track) = message else {
            Issue.record("expected a state message")
            return
        }

        #expect(track.title == "Bad Boyz")
        #expect(track.artist == "Release - Topic")
        #expect(track.isPlaying)
        #expect(track.duration == 227.881)
        #expect(track.trackIdentifier == "3095740")
        // The parent is what a person recognises; the media process is not.
        #expect(track.sourceBundleIdentifier == "com.apple.Safari")
        #expect(track.sourceName == "Safari")
    }

    @Test("A duration of zero means unknown, not a zero-length track")
    func zeroDurationIsUnknown() throws {
        let json = #"{"type":"state","payload":{"title":"Live Radio","duration":0,"isPlaying":true}}"#
        let message = try #require(BridgeMessage.decode(line: Data(json.utf8)))
        guard case .state(let track) = message else {
            Issue.record("expected a state message")
            return
        }

        #expect(track.duration == nil)
        #expect(track.progress(at: .now) == nil)
    }

    @Test("Artwork arrives base64 encoded")
    func decodesArtwork() throws {
        let bytes = Data([0x89, 0x50, 0x4E, 0x47])
        let json = """
        {"type":"artwork","key":"track|1|4","mimeType":"image/png","data":"\(bytes.base64EncodedString())"}
        """

        let message = try #require(BridgeMessage.decode(line: Data(json.utf8)))
        guard case .artwork(let key, let mimeType, let data) = message else {
            Issue.record("expected an artwork message")
            return
        }

        #expect(key == "track|1|4")
        #expect(mimeType == "image/png")
        #expect(data == bytes)
    }

    @Test("Empty artwork is rejected rather than shown as a blank cover")
    func rejectsEmptyArtwork() {
        let json = #"{"type":"artwork","key":"k","mimeType":"image/png","data":""}"#
        #expect(BridgeMessage.decode(line: Data(json.utf8)) == nil)
    }

    @Test("Idle and error messages decode")
    func decodesIdleAndError() throws {
        let idle = try #require(BridgeMessage.decode(line: Data(#"{"type":"idle"}"#.utf8)))
        guard case .idle = idle else {
            Issue.record("expected idle")
            return
        }

        let failure = try #require(
            BridgeMessage.decode(line: Data(#"{"type":"error","message":"nope"}"#.utf8))
        )
        guard case .failure(let text) = failure else {
            Issue.record("expected failure")
            return
        }
        #expect(text == "nope")
    }

    @Test("Unknown message types are ignored, not treated as failures")
    func ignoresUnknownTypes() {
        #expect(BridgeMessage.decode(line: Data(#"{"type":"something-new"}"#.utf8)) == nil)
        #expect(BridgeMessage.decode(line: Data("not json".utf8)) == nil)
    }
}
