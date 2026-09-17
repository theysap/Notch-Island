# Changelog

All notable changes to NotchIsland are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-09-17

### Added

- Initial project scaffold: Swift Package Manager layout targeting macOS 26+ on
  Apple silicon, built with Swift 6 language mode and strict concurrency.
- `MediaBridge` dynamic library target, which will host the MediaRemote reader
  that runs inside an Apple-signed helper process.
- `NotchIsland` executable target for the app itself.
- MIT license, changelog, and repository hygiene files.

### Notes

- macOS 15.4 and later refuse `MRMediaRemoteGetNowPlayingInfo` results to
  ordinary third-party binaries; the call returns an empty dictionary. Verified
  on macOS 27.0 (build 26A428) before any code was written. The working approach
  is to load a small dynamic library into an Apple-signed host process, which is
  what the `MediaBridge` target exists for.
