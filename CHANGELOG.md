# Changelog

All notable changes to NotchIsland are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.17.3] - 2026-09-18

### Changed

- A general-purpose player is now judged by what it is playing rather than by
  which application it is. VLC, IINA, QuickTime and mpv open as many albums as
  they do films, so classifying them as video players put the playhead sweep
  over every song. A file with an album or artist tag, running under fifteen
  minutes, is treated as music; anything longer, or with no tags at all, stays
  video. Artwork is deliberately not part of the test — these players publish
  it for films as readily as for albums, and often for neither.

  Dedicated video services — Apple TV, Netflix, Plex — are unchanged: the
  application really does settle it there.

## [0.17.2] - 2026-09-18

### Added

- Artwork for local files played in VLC. MediaRemote withholds the bytes here
  exactly as it does for Apple Music's library tracks — it reports the size
  and MIME type (768×768 `image/jpeg`) while `MRContentItemGetArtworkData`
  returns nil — but VLC writes the cover it extracted to its own cache, keyed
  by the very artist and album it reports through MediaRemote. Reading it
  needs no permission at all: the cache lives in `~/Library/Caches`, unlike
  the media file itself, which is usually somewhere TCC protects.

## [0.17.1] - 2026-09-18

### Fixed

- A blank gap sat between the island and other applications' menu bar icons.
  It was the menu bar reservation, and the reservation never worked: the
  system's own Control Center items cannot be pushed at all — measured at a
  300pt reservation, they did not move a pixel — and other applications' status
  items are laid out as a group anchored to the right, so an invisible item
  only makes that group wider on its left. Measured with three stand-in status
  items: they naturally sat from x 1206pt, comfortably clear of the island's
  right edge at 1022pt, and the 69pt reservation moved them to 1087pt, which is
  *towards* the island rather than away from it. So it opened a gap and made
  the overlap it was meant to prevent more likely. Removed, along with its
  setting; the app's menu bar footprint is now just its own icon.

## [0.17.0] - 2026-09-18

### Added

- Artwork for tracks in the music library, and a playhead that follows a seek
  made in the source's own window. Both come from asking the source
  application directly, because MediaRemote reports neither.

  **Artwork.** Apple Music publishes an https URL in the artwork identifier for
  catalogue tracks and an opaque identifier for library tracks, with no bytes
  anywhere — which is why some covers appeared and others fell back to the
  Music icon. Measured: no `ArtworkData` in the info dictionary in any of its
  four variants, including from a fresh process at the instant of a track
  change, which is what earlier versions relied on;
  `MRContentItemGetArtworkData` reports `HasArtworkData = 1` and returns nil;
  and neither the playback-queue request with `includeArtwork` nor
  `MRMediaRemoteGetNowPlayingArtwork` ever calls back.

  **The playhead.** MediaRemote reports a seek made *through* it and nothing
  else. Measured: Music moved from 119.4s to 45.6s while its content item went
  on reporting the original anchor. The island now checks the source's own
  position every two seconds and re-anchors when they disagree by more than
  0.75s. Normally they do not: measured against Music over successive polls,
  the interpolated playhead and the source agree to about 3ms. Verified
  correcting a 70-second divergence after a seek MediaRemote never reported.

  This needs Automation permission, which macOS asks for once. Refusing it
  leaves the app exactly as it was, and the refusal is remembered so the
  question is not asked again. Only Apple Music is wired up.

## [0.16.2] - 2026-09-18

### Fixed

- The expanded panel had roughly 20pt of dead space under the transport
  controls. Its height was a constant 168pt while its contents came to 145.5pt
  on this machine. The height is now derived from what is actually in it —
  the top strip, which is as tall as the camera housing and therefore measured
  per machine, plus the body and a deliberate 10pt margin.
- The artwork cache emptied itself completely on reaching 24 entries, so the
  cover that had just been on screen was as likely to be thrown away as the
  oldest one. It now evicts least-recently-used.

## [0.16.1] - 2026-09-18

### Fixed

- Settings… opened the window behind whatever the user was working in, and it
  had to be found by hand. An accessory application never becomes active on
  its own, and `SettingsLink` opens the scene without activating it. Measured
  with an accessory app on this machine: opening a window without activating
  leaves it visible but not key, with another application still frontmost;
  activating first makes the window key and the app frontmost. The menu item
  now activates the app before opening the scene, through the public
  `openSettings` action rather than a private selector whose name has changed
  across releases.

## [0.16.0] - 2026-09-18

### Added

- The island now shows what is already playing when the app starts, instead of
  waiting for the next track change.

  `MRMediaRemoteGetNowPlayingInfo` hands its dictionary over once, when it has
  changed, and answers nobody until it changes again — and the `...ForClient`,
  `...ForPlayer` and `...ForOrigin` variants are all gated the same way
  (measured: six consecutive attempts on a settled track, none answered).
  `+[MRNowPlayingRequest localNowPlayingItem]` is not a request to the daemon
  at all: it reads the local now-playing item synchronously, it is not gated,
  and paired with `MRContentItemGetNowPlayingInfo` it returns the same 27-key
  dictionary. Measured on a track that had been playing for minutes: answered
  every time, and it follows track changes.

### Fixed

- The playhead now follows a seek made inside the source application. The
  helper re-reads the local state on its poll, so an elapsed time that moves
  without warning is picked up within a poll — measured at ~1s for a seek made
  by another process entirely. MediaRemote reports such a seek in no other
  way: no notification, no dictionary, no handler call.

### Changed

- Track metadata is streamed by the long-lived helper rather than fetched by a
  burst of short-lived ones. The one-shot helper remains as the fallback for a
  source the local read cannot see, and now tries the local read first itself.
- The helper seeds its playing state synchronously at startup, so the app is
  no longer briefly told "not playing" before the daemon's first answer lands.

## [0.15.2] - 2026-09-18

### Fixed

- Hovering the camera housing, or the very top of the screen, did not open the
  island — only the stretches either side of the notch did. Pushing the pointer
  to the top edge reports the screen's `maxY` exactly (measured: y 1112.0 on an
  1112pt screen), and `CGRect.contains` excludes a rectangle's own maxY, so the
  one position the pointer lands in when it is flicked upwards fell outside the
  hover zone. Reaching the housing means going to that edge, which is why the
  two symptoms looked like one. The zone now extends a little past the top of
  the screen.

  Measured before and after by warping the pointer to four positions across the
  notch: the old build ignored both top-edge positions and opened for the other
  two; the new build opens for all four.

### Changed

- The hover poll runs at 0.1s instead of 0.25s, and only while the island is on
  screen. It is the only thing that sees the pointer over the notch — a global
  event monitor sees events delivered to other applications, and the menu bar
  beside the housing does not always have one — so it now runs often enough to
  feel immediate, and not at all when there is nothing to open.
- Expanding and collapsing are logged, so hover can be verified from
  `log stream` rather than by eye.

## [0.15.1] - 2026-09-17

### Fixed

- Starting the app part-way through a track left the notch empty. The daemon
  hands the dictionary over only when it has changed, and a track already under
  way has not — so there was nothing to show and nothing to wait for. Polling
  does not help: measured at sixteen consecutive fetches over 25 seconds, every
  one unanswered.

  The island now shows the source it can see while the details are on their
  way, and fills in properly at the next track change. This only happens while
  something really is playing; a source that is merely open still shows nothing
  at all, which was the point of the change in v0.15.0.

## [0.15.0] - 2026-09-17

### Fixed

- The island showed the correct track at launch and then never updated again.
  `MRMediaRemoteGetNowPlayingInfo` hands its dictionary to a given process
  **once**: a long-lived helper asking repeatedly was measured at 13 asks and 0
  replies across two track changes, while fresh processes answered correctly at
  the same moments. Metadata is now read by a short-lived helper spawned per
  refresh, and the long-lived helper keeps to what it can do repeatedly —
  watching notifications, reporting who is playing, and sending commands.
- Track changes went unnoticed. A track change alters neither the source nor
  the playing state, so a status carrying only those reported nothing new. The
  helper now emits a `changed` event on every MediaRemote notification,
  coalesced, and the app answers it by re-reading the dictionary.
- Every track update was silently discarded. The helper wrote `"isPlaying":1`
  rather than `true`, because in C a comparison yields `int` and boxing it
  without a cast produces a number — and the strict decoder throws out the
  *entire* payload over one mismatched field. The cast is fixed, booleans are
  now decoded leniently, and a line that fails to decode is logged instead of
  dropped in silence.
- Artwork downloads cancelled one another. Repeat requests for the same cover
  arrive routinely, and each one cancelled the last, so the artwork never
  finished loading. An in-flight key now guards against that.
- Playing state is taken from the notification-driven status rather than the
  dictionary's playback rate, which is a snapshot from whenever the fetch landed
  and reads as stopped immediately after a track change.

### Changed

- The island no longer appears at all unless there is real metadata to show.
  The rule is the one macOS follows: if the system's own Now Playing control has
  nothing in it, neither does the island — including on hover.
- The status item menu is now just Settings and Quit. The island is the
  interface, and macOS's own Now Playing control already covers transport.

### Notes

- A fetch is retried in a short burst (immediately, then at 600ms, 1.5s and
  3.5s) and stops at the first that answers. The daemon needs a moment after a
  notification before it will hand the new dictionary over, and an unanswered
  fetch is normal rather than a failure.

## [0.14.0] - 2026-09-17

### Fixed

- Nothing in the expanded player responded to the mouse. The transport buttons
  highlighted on hover and did nothing when clicked, and the progress bar could
  not be dragged. NotchIsland is an accessory application and never becomes
  active, so *every* click on the island is a first click, and AppKit spends a
  first click activating the window rather than delivering it — unless the view
  says otherwise. The island's view now accepts first mouse.

  Verified beforehand that the fault was in input and not in the command path:
  a debug flag pushed `next` through the whole app pipeline twice and changed
  the track both times.

### Changed

- The transport controls are centred on the progress bar rather than on the
  island, so they line up with the timeline they belong to. Artwork grew to 92pt
  and the panel was retuned around the taller column.
- The menu bar icon is the island's own silhouette with the equaliser showing
  through as negative space, drawn as a template image so macOS tints it for a
  light or dark menu bar. It replaces the generic waveform symbol.

### Added

- Debug-only `--send-command <name>`, which pushes one transport command
  through the real pipeline, separating a broken command path from a click that
  never arrived.
- The preview renderer writes the menu bar icon out too.

### Notes

- Seeking from the island is sent with `MRMediaRemoteSetElapsedTime`. A seek
  made *inside* the source application is not reported back by any means
  MediaRemote offers: it posts no notification, hands over no dictionary, and
  the elapsed-time handler it advertises never fires. The island's playhead
  therefore stays on its own reckoning until the next track change or
  play/pause, when the position resyncs.

## [0.13.2] - 2026-09-17

### Fixed

- The menu bar reservation was re-applied on every state update, rebuilding the
  status item's image about once a second for an unchanged width.

### Added

- Artwork links that point at an image directory rather than an image are
  retried with a size and format appended; there is no way to tell the two
  apart by looking at the link.

## [0.13.0] - 2026-09-17

### Fixed

- The island never updated after launch, and Apple Music showed as nothing
  playing. Three separate faults, each found by probing the daemon directly:
  - MediaRemote's notifications arrive on Core Foundation's **local**
    notification centre, not through `NSNotificationCenter`, and most of their
    names begin with an underscore. Watching `NSNotificationCenter` for names
    beginning `kMR` therefore saw nothing at all. Observing the right centre
    delivers playback state changes immediately and signals every track change.
  - The command reader's dispatch source was a local variable, released by ARC
    the moment the function returned, so it stopped delivering events. Every
    transport command was silently dropped. It is now held for the life of the
    process.
  - The now-playing dictionary is handed over only when it has changed since
    the daemon last delivered it — steady playback produces no reply at all.
    The previous code gave up after 600ms and discarded whatever arrived later,
    which threw away every update. The request now stands until it answers and
    is re-armed afterwards.

### Added

- Real artwork. Apple Music publishes no image bytes anywhere in its dictionary
  — it puts an https URL in the artwork field instead — so a URL is forwarded
  to the app, which fetches, caches and tints from it. A download is cancelled
  if the track changes first, so a slow fetch cannot put the previous cover over
  the current track.
- Commands are acknowledged, so one that goes nowhere can be told apart from
  one that never arrived.
- Artwork links that point at an image directory rather than an image are
  retried with a size and format appended; there is no way to tell the two
  apart by looking at the link.
- `contentType` is carried through as an extra classification signal.

### Notes

- A source that is playing but has published no metadata yet — which happens
  when the app starts part-way through a track, since the dictionary is only
  handed over on a change — shows an island naming the source. It fills in
  properly at the next track change.

## [0.12.0] - 2026-09-17

### Fixed

- The island could stop updating entirely and sit on a stale track.
  `MRMediaRemoteGetNowPlayingInfo` does not always call back — observed with
  Apple Music open — and the whole publish path was nested inside that
  callback, so one query that never answered stopped everything. The three
  queries now run together with a 600ms deadline that publishes whatever
  arrived, and the last good metadata is kept across a failed fetch rather than
  blanking the island.
- A player that is open but idle no longer shows an island containing nothing
  but its application icon. A registered source with no title, artist or
  duration now counts as idle, which is the state Apple Music sits in whenever
  playback is stopped.
- Roughly 10% of a CPU while playing, and 87MB of memory, caused by
  `.drawingGroup()` on the visualiser forcing an offscreen render pass every
  frame for a view a few points across. Removing it took the app to under 1%
  CPU and 18MB.

### Changed

- The progress bar is rebuilt on the system's glass material, with a tinted
  fill and a knob that appears under the pointer, to match how sliders look
  elsewhere on macOS 26. The material is layered behind solid fills rather than
  applied to them: `glassEffect` replaces what a view draws, and over the
  island's pure black there is nothing to refract, so on its own it renders as
  nothing at all.

### Added

- Debug-only `--render-live <directory>`, which renders whatever is actually
  playing through the real pipeline, for diagnosing layout problems that only
  appear with live metadata.
- A preview sample reproducing an empty-metadata source.

## [0.11.0] - 2026-09-17

### Added

- `Scripts/make-dmg.sh`, which packages the application into a disk image with a
  link to Applications, and reports the image's SHA-256.
- Release workflow: on a `v*.*.*` tag, checks the tag against `VERSION`, runs
  the tests, builds the application and disk image, and publishes both with
  checksums to a GitHub release.
- README covering what the app does, the content-type indicators, installation
  including the first-launch right-click, settings, how the MediaRemote bridge
  works and why, and how to build.
- Rendered screenshots in `docs/images`, generated by the preview renderer.

### Changed

- Disk images are created with `diskutil image create`, not `hdiutil create`,
  which macOS 27 deprecates. The LZFSE format it defaults to also produces a
  smaller image: 940K against 1.3M for the same contents.

## [0.10.0] - 2026-09-17

### Added

- `Scripts/build-app.sh`, which assembles `NotchIsland.app`: executable, bridge
  library, host script, generated icon and `Info.plist`, signed with the
  hardened runtime. Ad-hoc by default, or with a real identity when
  `DEVELOPER_ID_APPLICATION` is set.
- `Scripts/make-icon.swift`, which draws the application icon at every required
  size. The icon is generated rather than committed as binary blobs, so it can
  be changed in one place.
- Git hooks: `pre-commit` checks formatting, builds and runs the tests, and
  reminds about the changelog; `commit-msg` enforces the `vX.Y.Z` subject line.
  Install with `Scripts/install-hooks.sh`.
- GitHub Actions workflow running formatting, build, tests and a bundle build on
  every push and pull request, uploading the built application as an artifact.
- `.swift-format` configuration, and a formatting pass over the codebase.

### Notes

- The assembled bundle was verified end to end: launched from `dist/`, placed
  the island, started the bridge from `Contents/Frameworks` under the hardened
  runtime, reserved menu bar width, and left no helper process behind on quit.

## [0.9.0] - 2026-09-17

### Added

- Menu bar space reservation. An empty status item the width of the island's
  right-hand overhang means the system lays its status icons out beside the
  island rather than behind it, and folds whatever no longer fits behind its
  own overflow chevron. Verified reserving 69pt on the development machine, and
  switchable off in Settings.
- Notch measurements are now range-checked before use, and an off-centre camera
  housing is reported rather than silently distorting the island.
- `MacModel`, which identifies the machine for diagnostics and bounds-checking,
  and surfaces the model in Settings.
- Debug-only `--simulate-playback`, which feeds the island a synthetic track so
  window placement, hover and menu bar reservation can be exercised without
  commandeering the machine's audio.
- Seven further tests covering island symmetry and measurement limits.

### Changed

- The island's fill is stated as an explicit sRGB #000000 rather than
  `Color.black`, which resolves in whatever colour space the view is rendered
  into and can pick up a colour-management shift. It has to match the camera
  housing exactly.

### Notes

- The island is symmetric about the camera housing by construction: it extends
  by the same amount on both sides, and is centred on the housing rather than
  on the screen. Both properties are covered by tests across a range of notch
  widths.
- Notch size is measured from the display at runtime, not looked up from a
  table of Mac models. Every notched Mac reports the areas either side of its
  camera housing, so this is correct on models that do not exist yet.
- Reserving space only works for the status icons on the right. The menus on
  the left of the notch belong to the active application and are drawn by the
  system; there is no API to reserve space against them or to fold them, and
  macOS already truncates them at the notch with its own chevron.

## [0.8.0] - 2026-09-17

### Added

- Settings window: launch at login, menu bar icon visibility, and an option to
  hide the island entirely while playback is paused.
- Launch at login through `SMAppService`. A failed registration puts the toggle
  back rather than leaving it showing a state that is not true — it cannot
  succeed when the binary is run outside an application bundle.
- Menu bar item with the current track and transport controls, whose symbol
  follows the kind of media playing.

## [0.7.0] - 2026-09-17

### Added

- Test suite: 39 tests across 7 suites, written with Swift Testing, covering
  content-type inference, the bridge wire format in both directions, playback
  position interpolation and clamping, line reassembly from chunked pipe reads,
  island geometry, and time formatting.
- `Scripts/test.sh`, which locates Swift Testing's macro plugin and runs the
  suite. The plugin sits in a subdirectory the compiler does not search by
  default under the Command Line Tools, and passing its path at invocation
  keeps absolute paths out of `Package.swift`.

## [0.6.0] - 2026-09-17

### Added

- The expanded mini player: artwork, title, artist and album, a draggable
  progress bar with elapsed and remaining time, and previous / play-pause /
  next controls.
- Scrubbing that updates the playhead locally while dragging and only seeks the
  source on release, rather than sending a command per pixel of movement.
- `MarqueeText`, which scrolls a title that does not fit. Width is measured
  against the real font before layout, so text that fits is drawn statically
  with no timeline running at all.
- A source badge in the strip left of the camera housing, showing which
  application the audio is coming from. The visualiser occupies the strip to
  the right, so it stays put as the island opens and closes.
- Progress bars fall back to a static fill when the source reports no duration,
  instead of implying a position that does not exist.

### Changed

- The equaliser bars are capped in width so they stay slim in the wider
  expanded frame rather than becoming blocks.
- Tightened the expanded panel from 186 to 172 points; the original left too
  much empty space below the controls.

### Notes

- View-local state lives in an `@Observable` model rather than in `@State`.
  `@State` became a macro in the macOS 27 SDK and its plugin ships only with
  Xcode, not with the Command Line Tools this builds against. Every other
  SwiftUI wrapper still works; `ObservableObject` was not brought back.

## [0.5.0] - 2026-09-17

### Added

- Four activity indicators, one per content type, so the right of the notch
  says what kind of thing is playing and not merely that something is:
  - Music: equaliser bars, each driven by two sine waves of different
    frequency so they drift in and out of step rather than marching.
  - Podcast: a travelling waveform whose amplitude follows a speech envelope,
    dropping close to silence between phrases.
  - Video: the real playback position as a track with a lit head, sweeping
    instead when the source reports no duration.
  - Anything unidentified: a slow pulse.
- `VisualizerCanvas`, which draws each indicator in a single `Canvas` pass at
  30fps and stops the timeline entirely while playback is paused.
- A debug-only preview renderer (`--render-previews <directory>`) that writes
  the island's states to PNG. Capturing a floating panel needs screen-recording
  permission; this needs none. It is compiled out of release builds.

## [0.4.0] - 2026-09-17

### Added

- The island window: a non-activating floating panel pinned to the top of the
  built-in display, above the menu bar and its status items, present on every
  space and over full-screen apps.
- `NotchMetrics`, which measures the notch from the system rather than assuming
  a size, since it differs by model. Measured 208 × 37.5 pt on the development
  machine.
- `NotchShape`, the island outline: flush with the top of the screen, concave
  shoulders where it meets the bezel, rounded along the bottom.
- `HoverMonitor`, which opens the island when the pointer settles in the notch
  strip and closes it shortly after the pointer leaves, with a dwell delay so
  crossing the menu bar on the way elsewhere does not open the player.
- Compact and expanded layouts, sized from the measured notch, with the camera
  housing left clear between artwork and the activity indicator.
- Click-through: the panel ignores the mouse entirely while collapsed, so the
  menu bar underneath behaves normally, and only accepts clicks within the
  island's own outline once open.

### Notes

- The island is only ever placed on a built-in display that physically has a
  notch, and rebuilds itself when the screen configuration changes.

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
