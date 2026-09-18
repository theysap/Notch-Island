import Foundation
import Testing

@testable import NotchIsland

@Suite("Release versions")
struct AppVersionTests {
    @Test("Versions compare by number, not as text")
    func comparesNumerically() {
        // The reason this type exists: "0.17.10" sorts before "0.17.9" as a
        // string, which would hide an update.
        #expect(AppVersion("0.17.10")! > AppVersion("0.17.9")!)
        #expect(AppVersion("1.0.0")! > AppVersion("0.99.99")!)
        #expect(AppVersion("0.18.0")! > AppVersion("0.17.3")!)
        #expect(AppVersion("0.17.3")! == AppVersion("0.17.3")!)
    }

    @Test("A tag is accepted with or without its v")
    func acceptsTagForm() {
        #expect(AppVersion("v0.17.3") == AppVersion("0.17.3"))
        #expect(AppVersion("0.17")! == AppVersion(major: 0, minor: 17, patch: 0))
        #expect(AppVersion("2")! == AppVersion(major: 2, minor: 0, patch: 0))
    }

    @Test("A suffix is ignored rather than refused")
    func ignoresSuffix() {
        // An unfamiliar tag should still compare sensibly.
        #expect(AppVersion("0.18.0-beta.1")! == AppVersion("0.18.0")!)
    }

    @Test("Nonsense is refused")
    func rejectsNonsense() {
        #expect(AppVersion("") == nil)
        #expect(AppVersion("nightly") == nil)
    }
}

@Suite("Release feed")
struct AppReleaseTests {
    private func json(
        tag: String = "v0.18.0", draft: Bool = false, prerelease: Bool = false,
        assets: String = """
        [{"name": "NotchIsland-0.18.0.dmg",
          "browser_download_url": "https://example.invalid/NotchIsland-0.18.0.dmg"},
         {"name": "SHA256SUMS.txt",
          "browser_download_url": "https://example.invalid/SHA256SUMS.txt"}]
        """
    ) -> Data {
        Data(
            """
            {"tag_name": "\(tag)", "body": "notes", "draft": \(draft),
             "prerelease": \(prerelease), "assets": \(assets)}
            """.utf8)
    }

    private func decode(_ data: Data) throws -> GitHubRelease {
        try JSONDecoder().decode(GitHubRelease.self, from: data)
    }

    @Test("A published release yields its disk image and checksums")
    func readsRelease() throws {
        let release = try #require(decode(json()).release)

        #expect(release.version == AppVersion("0.18.0"))
        #expect(release.diskImage.lastPathComponent == "NotchIsland-0.18.0.dmg")
        #expect(release.checksums.lastPathComponent == "SHA256SUMS.txt")
    }

    @Test("Drafts and pre-releases are not offered")
    func skipsUnfinishedReleases() throws {
        #expect(try decode(json(draft: true)).release == nil)
        #expect(try decode(json(prerelease: true)).release == nil)
    }

    @Test("A release with no checksums is not offered")
    func requiresChecksums() throws {
        // Without them an update cannot be verified, so it is not installed.
        let assets = """
            [{"name": "NotchIsland-0.18.0.dmg",
              "browser_download_url": "https://example.invalid/NotchIsland-0.18.0.dmg"}]
            """
        #expect(try decode(json(assets: assets)).release == nil)
    }

    @Test("A release with no disk image is not offered")
    func requiresDiskImage() throws {
        let assets = """
            [{"name": "SHA256SUMS.txt",
              "browser_download_url": "https://example.invalid/SHA256SUMS.txt"}]
            """
        #expect(try decode(json(assets: assets)).release == nil)
    }

    @Test("A tag that is not a version is not offered")
    func requiresVersionTag() throws {
        #expect(try decode(json(tag: "nightly")).release == nil)
    }
}

@Suite("Checksums")
struct ChecksumsTests {
    private let digest = String(repeating: "a", count: 64)

    @Test("The digest is found by file name")
    func findsDigest() {
        let text = """
            \(String(repeating: "b", count: 64))  OtherFile.dmg
            \(digest)  NotchIsland-0.18.0.dmg
            """
        #expect(Checksums.digest(for: "NotchIsland-0.18.0.dmg", in: text) == digest)
    }

    @Test("A binary marker and a leading path are both tolerated")
    func toleratesShasumForms() {
        #expect(Checksums.digest(for: "a.dmg", in: "\(digest) *a.dmg") == digest)
        #expect(Checksums.digest(for: "a.dmg", in: "\(digest)  dist/a.dmg") == digest)
    }

    @Test("A missing or malformed entry yields nothing")
    func rejectsRubbish() {
        #expect(Checksums.digest(for: "a.dmg", in: "\(digest)  b.dmg") == nil)
        #expect(Checksums.digest(for: "a.dmg", in: "not-a-digest  a.dmg") == nil)
        #expect(Checksums.digest(for: "a.dmg", in: "") == nil)
    }
}
