import Foundation
import Testing

@testable import NotchIsland

/// Apple Music takes two entirely different routes to a cover, and which one
/// applies is decided purely by what the artwork identifier looks like. Getting
/// that split wrong is invisible until someone plays the other kind of track —
/// which is exactly how library artwork stayed broken — so both are pinned here.
@Suite("Artwork links")
struct ArtworkURLTests {
    @Test("A catalogue template has its size placeholders filled in")
    func catalogueTemplateResolves() {
        // The form Apple's image service publishes for a track played from
        // search or the catalogue. Useless until the placeholders are replaced.
        let resolved = ArtworkURL.resolve(
            "https://is1-ssl.mzstatic.com/image/thumb/Music/v4/ab/cd/ef/cover.jpg/{w}x{h}{c}.{f}")

        #expect(
            resolved?.absoluteString
                == "https://is1-ssl.mzstatic.com/image/thumb/Music/v4/ab/cd/ef/cover.jpg/"
                + "\(ArtworkURL.size)x\(ArtworkURL.size)bb.jpg")
    }

    @Test("A library track's identifier is not a link")
    func libraryIdentifierIsNotResolved() {
        // What Music publishes for a track in the library or a user playlist:
        // an opaque identifier, with no bytes anywhere. There is nothing to
        // fetch, so it must not be mistaken for a URL — the cover for these
        // comes from `SourceScripting` instead.
        #expect(ArtworkURL.resolve("af179ea681815796#tr:46c3f80a25e79aee") == nil)
    }

    @Test("Only http and https are fetched")
    func schemesAreRestricted() {
        #expect(ArtworkURL.resolve("file:///etc/passwd") == nil)
        #expect(ArtworkURL.resolve("data:image/png;base64,AAAA") == nil)
        #expect(ArtworkURL.resolve("https://example.com/cover.jpg") != nil)
        #expect(ArtworkURL.resolve("http://example.com/cover.jpg") != nil)
    }

    @Test("A link with no extension gets a sized fallback")
    func sizedFallbackForDirectoryStyleLinks() {
        let base = URL(string: "https://example.com/artwork")!
        #expect(
            ArtworkURL.sizedAlternative(for: base)?.absoluteString
                == "https://example.com/artwork/\(ArtworkURL.size)x\(ArtworkURL.size)bb.jpg")

        // A trailing slash must not produce a doubled one.
        let trailing = URL(string: "https://example.com/artwork/")!
        #expect(
            ArtworkURL.sizedAlternative(for: trailing)?.absoluteString
                == "https://example.com/artwork/\(ArtworkURL.size)x\(ArtworkURL.size)bb.jpg")
    }

    @Test("A link that already names an image has no fallback")
    func noFallbackWhenAlreadyAnImage() {
        #expect(
            ArtworkURL.sizedAlternative(for: URL(string: "https://e.com/a/512x512bb.jpg")!) == nil)
    }
}
