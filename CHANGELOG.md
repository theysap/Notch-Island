# Changelog

All notable changes to NotchIsland are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.0] - 2026-09-17

### Added

- Swift media layer: `NowPlaying` snapshots, a decoder for the bridge's wire
  format, and `MediaController`, the app's observable view of what is playing.
- `MediaBridgeConnection`, which supervises the host process, streams its
  output, writes commands to it, and relaunches it with back-off if it dies.
- Content-type inference in `MediaKind`. MediaRemote reports an explicit media
  type for native applications and nothing at all for browsers, so browser
  playback is classified from the track tags and duration instead.
- Artwork handling, including the source application's icon as a stand-in for
  sources that publish no artwork.
- `ArtworkPalette`, which averages artwork down to an accent and background
  colour so the island can be tinted to match what is playing.
- Application shell: an accessory-mode app with a menu bar item showing the
  current track and a way to quit.

### Fixed

- The helper process outlived the app. The write end of its own stdin pipe
  stays open inside the helper, so the pipe never reaches EOF, and neither a
  `DISPATCH_SOURCE_TYPE_PROC` exit source nor reparenting to launchd was enough
  on its own. The helper now polls its parent once a second and exits about a
  second after the app goes away, verified against both `SIGTERM` and `SIGKILL`.

## [0.2.0] - 2026-09-17

### Added

- `NotchMediaBridge`, a dynamic library that reads system-wide now-playing
  state from MediaRemote and streams it as newline-delimited JSON on stdout:
  title, artist, album, source application, media type, duration, elapsed time,
  playback rate and artwork bytes.
- Playback commands in the other direction, read as newline-delimited JSON on
  stdin: play, pause, play/pause toggle, next, previous, stop and seek.
- `Resources/notch-media-bridge.pl`, the Apple-signed host process that loads
  the bridge. The bridge constructor takes the process over and never returns.
- Duplicate suppression, so a track change produces one update rather than the
  half-dozen notifications MediaRemote actually sends.
- A bounded artwork retry chain (0.4s, 1.2s, 3.0s). Browser sources routinely
  publish artwork metadata before the bytes exist.
- A five-second heartbeat, so a source that dies without notifying cannot leave
  a stale track on screen.

### Notes

- Verified live against Safari playback: state streams correctly, and the
  process exits on stdin EOF when the app goes away.
- Some sources publish no artwork bytes at all — YouTube in Safari is one — so
  the app will need to fall back to the source application's icon.

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
