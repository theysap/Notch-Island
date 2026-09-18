# TECHNICAL.md

How NotchIsland works, and why it is built the way it is.

Most of what follows exists because macOS does not want an ordinary
application to know what is playing. Nearly every design decision here is a
consequence of that, and each one was settled by measuring the system rather
than by reading documentation, because there is no documentation — MediaRemote
is private. Where a number appears below, it was measured on the development
machine (a 13-inch MacBook Air, `Mac15,12`, macOS 27.0) and not estimated.

---

## Contents

1. [The shape of the problem](#1-the-shape-of-the-problem)
2. [Process architecture](#2-process-architecture)
3. [MediaRemote](#3-mediaremote)
4. [What MediaRemote will not report](#4-what-mediaremote-will-not-report)
5. [The Swift side](#5-the-swift-side)
6. [Geometry and the window](#6-geometry-and-the-window)
7. [Hover](#7-hover)
8. [The indicators](#8-the-indicators)
9. [Updating](#9-updating)
10. [Building and packaging](#10-building-and-packaging)
11. [Testing without a screen](#11-testing-without-a-screen)
12. [Known limits](#12-known-limits)

---

## 1. The shape of the problem

To draw what is playing you need three things: who is playing, what the track
is, and where it has got to. macOS has all three, in a daemon called
`mediaremoted`, reachable through the private `MediaRemote.framework`.

Since macOS 15.4 it will not tell you. A now-playing query from an ordinary
application gets a callback with an **empty dictionary** — no error, no denial,
nothing to catch. This was confirmed on macOS 27.0 before any of this app was
written, and it is the single fact the architecture is built around.

The check looks at the **process**, specifically whether its main executable is
signed by Apple. It does not look at what the process has loaded.

## 2. Process architecture

```
NotchIsland.app  (SwiftUI, LSUIElement, ad-hoc signed)
      │
      │  spawns
      ▼
/usr/bin/perl  (Apple-signed, so the daemon answers it)
      │
      │  DynaLoader::dl_load_file(..., RTLD_GLOBAL)
      ▼
libNotchMediaBridge.dylib
      │
      ├── stdout ──▶  newline-delimited JSON: ready, status, state, artwork,
      │               artworkURL, changed, idle, ack, error
      └── stdin  ◀──  newline-delimited JSON: play, pause, next, previous,
                      seek, refresh
```

The library has no entry point of its own. A `__attribute__((constructor))`
takes the host process over before perl runs a line of its own program, and
never returns. Perl is the host because Apple signs it and it will load an
arbitrary dylib on request; nothing is injected into any other application, and
no permission of any kind is involved.

Two details that are not obvious and cost a lot to find:

**A dispatch source assigned to a local is released when the function
returns.** The stdin reader silently stopped delivering commands until the
source was held for the life of the process. Every transport button was dead
and nothing logged an error.

**The helper cannot notice the app quitting by watching stdin.** It holds the
write end of that pipe itself, so EOF never arrives.
`DISPATCH_SOURCE_TYPE_PROC` with `DISPATCH_PROC_EXIT` does not fire for it
either. It polls `getppid()` once a second and exits about 1.2s after the app
goes, verified against both `SIGTERM` and `SIGKILL`.

## 3. MediaRemote

### 3.1 Notifications arrive on the CF *local* centre

MediaRemote's notifications do not come through `NSNotificationCenter`, and
most of their names begin with an underscore:

```
_kMRMediaRemotePlayerPlaybackStateDidChangeNotification
_kMRMediaRemotePlayerIsPlayingDidChangeNotification
kMRMediaRemoteNowPlayingInfoDidChangeNotification
kMRPlaybackQueueContentItemArtworkChangedNotification
```

Watching `NSNotificationCenter` for names beginning `kMR` sees nothing at all,
which is easily mistaken for "MediaRemote sends no notifications". The right
call is `CFNotificationCenterAddObserver` on
`CFNotificationCenterGetLocalCenter()`, matching both the `kMR` and `_kMR`
prefixes.

The payload is rich and reliable: playing state, display name, PID, and the
client and player objects. Playback state is taken straight from it, so a pause
shows up immediately rather than on the next poll.

### 3.2 Which queries answer

| Query | Behaviour |
|---|---|
| `MRMediaRemoteGetNowPlayingClient` | Answers every time. The reliable test for whether anything is playing, and which app. |
| `MRMediaRemoteGetNowPlayingApplicationPID` | Answers every time. |
| `MRMediaRemoteSendCommand` | Works. Play, pause, next, previous — all verified, including against VLC. |
| `MRMediaRemoteSetElapsedTime` | Works. Seeking from the island moves the source. |
| `MRMediaRemoteGetNowPlayingInfo` | **Gated. See below.** |

### 3.3 The dictionary is handed over once per change

`MRMediaRemoteGetNowPlayingInfo` delivers its dictionary only when it has
changed since the daemon last handed it to anyone. Measured:

| Test | Result |
|---|---|
| One process asking every 2s across two track changes | 13 asks, 0 replies |
| A fresh process after each of those changes | Answered every time, correct title |
| Any process, on a track that has been playing a while | 6 consecutive attempts, none answered |

The `ForOrigin`, `ForClient` and `ForPlayer` variants behave identically, and
disassembly shows why: `MRMediaRemoteGetNowPlayingInfo(queue, block)` is
literally `MRMediaRemoteGetNowPlayingInfoForOrigin(NULL, queue, block)`. They
are the same call.

This is why early versions of the app showed nothing when launched in the
middle of a track, and why they briefly used a burst of short-lived helper
processes to catch each change.

### 3.4 The ungated read, which replaced all of that

`+[MRNowPlayingRequest localNowPlayingItem]` is not a request to the daemon at
all. It reads the local now-playing item **synchronously**, and it is not
gated:

```objc
id item = [MRNowPlayingRequest localNowPlayingItem];
NSDictionary *info = (__bridge NSDictionary *)MRContentItemGetNowPlayingInfo(item);
```

Measured on a track that had been playing for minutes: answered **every time**,
26–27 keys, and it follows track changes within one poll. `+localIsPlaying` and
`+localNowPlayingPlayerPath` are equally synchronous and equally ungated.

`MRContentItemGetNowPlayingInfo` follows Core Foundation's *Get* rule and
returns +0 — verified by calling it 100,000 times without releasing the result,
which moved RSS by 144KB. It must be bridged **without** transferring
ownership.

With this, the long-lived helper simply reads and publishes state, and the
short-lived one survives only as a fallback. Helper processes went from up to
four per track change to **one, for the life of the app** — measured over 30
seconds of playback.

### 3.5 Wire format

The helper emits one JSON object per line. Two traps are worth recording:

**A number where a boolean was expected throws out the whole payload.** The
helper once emitted `"isPlaying":1` rather than `true`, because in C a
comparison yields `int` and `@(expr)` boxes it as a number. Swift's strict
decoding then failed the *entire* payload, so every track update vanished, with
nothing logged anywhere because the undecodable line was being skipped
silently. Booleans are cast explicitly when boxed, decoded leniently, and a
line that fails to decode is now logged rather than dropped.

**Unanswered is not the same as idle.** A fetch that goes unanswered says
nothing about whether something is playing, so the helper distinguishes `idle`
(genuinely nothing) from `nodata` (no answer), and the app ignores the latter
and keeps what it has.

## 4. What MediaRemote will not report

Two things, both of which the app gets from the source application instead.

### 4.1 Artwork

MediaRemote hands over artwork **bytes** for nothing at all. What it publishes
is one of two things:

- An **https URL** in `kMRMediaRemoteNowPlayingInfoArtworkIdentifier` — Apple
  Music catalogue tracks. The app fetches and caches it.
- An **opaque identifier**, with the size and MIME type but no bytes. Apple
  Music library tracks, VLC, and every browser.

For the second case, everything available was tried and none of it works:

| Attempt | Result |
|---|---|
| `ArtworkData` in the dictionary, all four variants | Absent |
| Same, from a fresh process at the instant of a track change | Absent |
| `MRContentItemGetArtworkData` on the live item | `HasArtworkData = 1`, data nil, size 0×0 |
| `MRContentItemGetArtworkURL`, `...URLTemplates` | Null |
| `kMRPlaybackQueueContentItemArtworkChangedNotification` items | Carried, but with no data |
| `MRMediaRemoteRequestNowPlayingPlaybackQueue` with `includeArtwork` | Never calls back |
| `MRMediaRemoteGetNowPlayingArtwork` | Never calls back |
| `MRMediaRemoteGetNowPlayingInfoWithOptionalArtwork(NULL, YES, …)` | Answers, no artwork |

The signatures above are correct rather than guessed — see
[§11.3](#113-getting-a-real-signature). `Music.app` holds
`com.apple.mediaremote.allow`, which an unsigned third-party app cannot have,
and that is the most likely explanation for why the system's own Now Playing
widget can draw artwork the app cannot obtain.

So artwork is resolved per source, in `SourceArtwork`:

| Source | Where the cover comes from |
|---|---|
| Apple Music, catalogue | The https URL MediaRemote publishes |
| Apple Music, library or a user playlist | AppleScript: `raw data of artwork 1 of current track` |
| VLC | VLC's own cache, below |
| Browsers | Nothing is available; the browser's icon is shown |

Which of the first two applies is decided entirely by what
`kMRMediaRemoteNowPlayingInfoArtworkIdentifier` looks like: an `https://` value
is a link to fetch, anything else — `af179ea681815796#tr:46c3f80a25e79aee` and
the like — is an opaque identifier with no bytes behind it anywhere. Only the
catalogue publishes links, so *everything* in the library and in user playlists
depends on the AppleScript route working.

#### The entitlement that route needs

The bundle is signed `--options runtime`. The hardened runtime blocks Apple
events outright unless the binary carries
**`com.apple.security.automation.apple-events`**, and the Automation prompt is
only ever shown for an app that also declares
**`NSAppleEventsUsageDescription`**. An app missing either gets
`errAEEventNotPermitted` (-1743) on every event, with no prompt for the user to
grant — indistinguishable, from inside the app, from a refusal.

This is what made library artwork look like a MediaRemote limitation when it
was a packaging one: the AppleScript itself was correct all along and returns
an 800×800 PNG when it is allowed to run. `Scripts/build-app.sh` writes the
usage string into `Info.plist`, signs with `Resources/NotchIsland.entitlements`,
and then *verifies the entitlement survived into the signature* — a missing one
is otherwise invisible until someone plays a library track.

A refusal is backed off for a minute rather than remembered for the life of the
process, so granting the permission in System Settings takes effect without a
relaunch. macOS shows the prompt only once and fails silently afterwards, so
retrying costs nothing.

**VLC** extracts the cover itself and writes it to
`~/Library/Caches/org.videolan.vlc/art/artistalbum/<artist>/<album>/art.jpg`,
keyed by exactly the artist and album it publishes through MediaRemote — so the
two line up with nothing to guess, and reading it needs no permission. Reading
the media file directly would also work and would generalise further, but it
costs a permission the cache does not: media usually lives in Downloads or
Documents, where `AVURLAsset` fails with `NSCocoaErrorDomain 257` until the
user grants Files-and-Folders access.

### 4.2 A seek made in the source's own window

MediaRemote reports a seek made *through* it, and not one made by the user
dragging the source's own scrubber. Measured: Music moved from 119.4s to 45.6s
while its content item went on reporting the original anchor, unchanged.

So for a scriptable source the app asks. Every two seconds, while something is
playing, it reads the source's own position and re-anchors the playhead if the
two disagree by more than 0.75s. Normally they do not: measured over successive
polls, the interpolated playhead and Music's own position agree to about **3
milliseconds**. The check has been seen correcting a 70-second divergence after
a seek MediaRemote never mentioned.

Position is stored as an elapsed time plus the instant it was reported, never
as a running counter, so the UI interpolates at display refresh rate without
polling anything and a paused track simply stops advancing.

## 5. The Swift side

```
Sources/NotchIsland/
  App/      AppDelegate, NotchIslandApp (MenuBarExtra + Settings), AppSettings
  Media/    MediaBridgeConnection, BridgeMessage, NowPlaying, MediaKind,
            MediaController, SourceScripting, SourceArtwork, ArtworkURL
  Notch/    NotchMetrics, IslandLayout, NotchPanel, NotchWindowController,
            HoverMonitor, IslandPresentation, MacModel
  Update/   AppVersion, AppRelease, UpdateChecker, UpdateInstaller
  UI/       IslandRootView, CompactIslandView, ExpandedPlayerView, ScrubBar,
            TransportControls, MarqueeText, ArtworkView, NotchShape, Theme,
            SettingsView, Visualizer/
  Support/  AppLog, ArtworkPalette, ObservationFollow, IslandPreviewRenderer
```

`MediaBridgeConnection` is an actor that spawns, supervises and relaunches the
helper with back-off. `MediaController` is the app's `@Observable` view of
playback and the only thing the UI reads.

### 5.1 Content type

`MediaKind.infer` decides which indicator to draw, from three kinds of source:

- **Dedicated applications** — Apple TV, Netflix, Plex, Spotify, Podcasts. The
  application settles it.
- **General-purpose players** — VLC, IINA, QuickTime, mpv. The application says
  nothing: they play albums and films alike. The track decides — an album or
  artist tag under fifteen minutes is music, anything longer or untagged is
  video.
- **Browsers** publish no media type at all (measured: 13 keys, no
  `MediaType`, no `StrictMediaType`). Full track tags mean music, past half an
  hour means an episode, otherwise video.

Artwork is deliberately not a signal anywhere in this: it is published for
films as readily as for albums, and frequently for neither.

### 5.2 Artwork colour

`ArtworkPalette` pulls an accent from the cover, which tints the progress bar
and the indicator. Downloads are cancelled when the track changes so a slow
fetch cannot land over the next track, and an in-flight key guards against the
case where the same cover is requested twice and each request cancels the
other — which once meant the download never finished at all.

The cache holds 24 covers and evicts least-recently-used.

## 6. Geometry and the window

The notch is **measured at runtime** from `safeAreaInsets` and the
`auxiliaryTopLeftArea` / `auxiliaryTopRightArea` of the built-in screen, never
looked up from a table of models — so it is correct on machines that do not
exist yet. Readings are range-checked before use. On this machine: 208 × 37.5pt
on a 1710 × 1112pt screen.

The island is symmetric about the camera housing by construction and centred on
the **housing**, not on the screen; those are not the same point, and the
difference is visible. Covered by tests across several notch widths.

The panel is a borderless non-activating window at level 26 — above the menu
bar (24) and status items (25) — drawn in explicit sRGB `#000000` rather than
`Color.black`, so it matches the housing exactly.

Two AppKit details the island depends on:

**`acceptsFirstMouse` must return `true`.** An accessory application never
becomes active, so every click is a "first" click; AppKit spends those
activating the window and delivers nothing to the view. Without this, every
control in the island highlights on hover and does nothing.

**An accessory app must activate itself before opening a window.** Measured
with a stand-in: opening a window without `NSApp.activate()` leaves it visible
but not key, with another application still frontmost — which is exactly how
the Settings window used to arrive behind everything.

## 7. Hover

The collapsed panel sets `ignoresMouseEvents = true` so clicks reach the menu
bar underneath, which rules out tracking areas. The pointer's location is
watched instead: two `NSEvent` monitors, plus a 0.1s poll that runs only while
the island is on screen. The poll is not a belt-and-braces measure — it is the
only thing that sees the pointer over the notch, because a global monitor sees
only events delivered to *another* application and the strip beside the camera
housing does not always have one.

The subtle bug worth recording: `CGRect.contains` excludes a rectangle's own
`maxY`, and pushing the pointer to the top of the screen reports
`screenFrame.maxY` **exactly** — 1112.0 on an 1112pt screen. A hover zone that
stopped at the top of the screen therefore missed the one position the pointer
lands in when it is flicked upwards, which also explained why hovering the
camera housing appeared not to work: reaching the housing means going to that
edge. The zone now overshoots by 2pt.

Mouse-location reads need no permission. Posting synthetic events would, which
is why none are.

## 8. The indicators

Three animations, each a plain SwiftUI `TimelineView`:

- **Music** — equaliser bars, each driven by two sine waves of different
  frequency so they drift rather than march in step.
- **Podcast** — a travelling waveform on a speech envelope, dropping close to
  silence between phrases.
- **Video** — the real playback position, drawn as a track with a lit head.
- **Generic** — a soft pulse, for audio that does not identify itself.

`.drawingGroup()` on the visualiser cost about 10% of a CPU and 87MB — an
offscreen render pass every frame for a view a few points across. Removing it
took the app to under 1% CPU and 18MB. It should not come back.

(`ps %cpu` is a lifetime average and reads high just after launch; use
`top -pid <pid> -l N -s 2` for an instantaneous figure.)

## 9. Updating

`Update/` checks GitHub's releases API ten seconds after launch and every six
hours, names the running version in the menu, and installs a newer one when
asked: download, verify, replace, relaunch.

**Why not Sparkle.** Sparkle expects a stable code signature it can compare
across versions. This project has no Developer ID at all — everything is
ad-hoc signed, which changes identity on every build — so that comparison
cannot be made.

**What is checked instead.** The disk image is downloaded over HTTPS from the
release and must hash to the digest in the `SHA256SUMS.txt` published beside
it; a mismatch is discarded rather than installed. A release missing either
asset is never offered, and neither is a draft or a pre-release. This proves
the download is the file that was published and nothing about who published
it — see the note in the README.

**Replacing a running app.** The new copy is staged in an item-replacement
directory on the same volume, stripped of its quarantine attribute, and moved
into place with `replaceItemAt`. The relaunch has to wait for this process to
exit before starting the new one, because the app quits a second instance of
itself at launch — start the new copy first and it will simply quit again.

Versions are compared numerically, not as text, so `0.17.10` is correctly newer
than `0.17.9`.

## 10. Building and packaging

No Xcode — Command Line Tools only. Consequences:

- **No `xcodebuild`.** `Scripts/build-app.sh` assembles the bundle by hand.
- **`@State` cannot be used.** It became a macro in the macOS 27 SDK and
  `SwiftUIMacros` ships only with Xcode. Every other wrapper works, and
  view-local state lives in an `@Observable` model instead.
- **Swift Testing's macro plugin** sits in a directory the compiler does not
  search, so tests run through `Scripts/test.sh`, which passes `-plugin-path`.
  Plain `swift test` fails.
- **No code-signing identity.** Everything is ad-hoc signed, so the first
  launch needs right-click → Open. Set `DEVELOPER_ID_APPLICATION` to sign
  properly.

`build-app.sh` builds **release** by default, which compiles out every
`#if DEBUG` flag. A bundle intended for testing one of those must be built with
`CONFIGURATION=debug`.

The bundle carries a build number derived from the commit count, because macOS
wants one that increases monotonically. It is deliberately not displayed: a
commit is not something anyone can download. The menu and Settings show the
release version alone.

Releasing is a tag push. `.github/workflows/release.yml` checks the tag matches
`VERSION`, runs the tests, builds the app and disk image, writes
`SHA256SUMS.txt` and publishes all of it — which is exactly what the updater
expects to find.

### 10.1 Distribution, and the Gatekeeper wall

Without a Developer ID, **every first launch on every other Mac is refused**.
Measured, rather than assumed: take the published disk image, give it the
quarantine attribute a browser would, mount it, copy the app out, and

```
codesign -dvv  →  Signature=adhoc      (no authority)
spctl -a -vvv  →  rejected
```

which surfaces as *"Apple could not verify NotchIsland is free of malware."*
The dialog offers only **Done** and **Move to Bin**, and the Control-click →
Open bypass was removed in macOS 15. What remains for a user is System
Settings → Privacy & Security → **Open Anyway**, or
`xattr -dr com.apple.quarantine`, which was confirmed to let the app launch
normally.

This affects the **first install only**. The in-app updater strips the
quarantine attribute from the staged copy before it replaces the running one,
so an update is never met with the dialog — verified by updating a 0.9.0 build
to 1.0.0 from the live release and watching it relaunch.

#### What each level of signing actually gets you

| State | First launch of a downloaded copy |
|---|---|
| Ad-hoc signed, not notarised — **where this project is** | Refused outright: *"Apple could not verify… is free of malware"*, buttons **Done** and **Move to Bin**. Only Privacy & Security → Open Anyway will do it |
| Signed with a Developer ID, **not** notarised | Still refused. Since macOS 10.15 a Developer ID signature on its own is not enough, and the wording barely changes |
| Signed with a Developer ID **and** notarised **and** stapled | The ordinary prompt: *"…is an app downloaded from the Internet. Are you sure you want to open it?"* with **Open** — and macOS adds that it checked for malicious software and found none |

So notarisation is the step that matters, and it cannot be had without the
paid Developer Program: a free Apple account cannot issue a Developer ID
certificate and `notarytool` will not accept one.

#### The variables

| Variable | Used by | Effect |
|---|---|---|
| `DEVELOPER_ID_APPLICATION` | `build-app.sh`, `make-dmg.sh` | Signs the app and the image with a real identity, with a secure timestamp rather than `--timestamp=none`, which notarisation requires |
| `NOTARY_KEYCHAIN_PROFILE` | `make-dmg.sh` | Notarises using stored credentials (`notarytool store-credentials`) — the local route |
| `NOTARY_APPLE_ID`, `NOTARY_TEAM_ID`, `NOTARY_PASSWORD` | `make-dmg.sh` | The same, for CI, with an app-specific password |
| `DEVELOPER_ID_CERTIFICATE_P12`, `DEVELOPER_ID_CERTIFICATE_PASSWORD` | the workflow | The certificate itself, base64 encoded, imported into a throwaway keychain — a fresh runner has no keychain and `codesign` cannot use an identity that is not in one |

With none of them present, everything still builds and publishes, ad-hoc
signed, and the script says so rather than pretending otherwise.

#### Doing it, once enrolled

```sh
# 1. Keychain Access → Certificate Assistant → Request a Certificate from a
#    Certificate Authority, saved to disk. Upload it at developer.apple.com
#    under Certificates → + → Developer ID Application. Download and open the
#    result, then confirm it is installed:
security find-identity -v -p codesigning

# 2. An app-specific password for notarytool, from appleid.apple.com, stored
#    under a profile name:
xcrun notarytool store-credentials notch \
    --apple-id you@example.com --team-id TEAMID --password abcd-efgh-ijkl-mnop

# 3. A signed, notarised, stapled image, locally:
export DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (TEAMID)"
./Scripts/build-app.sh
NOTARY_KEYCHAIN_PROFILE=notch ./Scripts/make-dmg.sh
```

For CI, export the certificate from Keychain Access as a `.p12` with a
password, then add the repository secrets:

```sh
base64 -i DeveloperID.p12 | pbcopy    # → DEVELOPER_ID_CERTIFICATE_P12
```

`DEVELOPER_ID_CERTIFICATE_PASSWORD`, `DEVELOPER_ID_APPLICATION`,
`NOTARY_APPLE_ID`, `NOTARY_TEAM_ID` and `NOTARY_PASSWORD` complete the set.
The next tag then produces an image that opens with a single **Open**.

Check the result before trusting it — a notarised image says so:

```sh
xcrun stapler validate NotchIsland-x.y.z.dmg
spctl -a -vvv -t install NotchIsland-x.y.z.dmg   # expect: accepted, source=Notarized Developer ID
```

### 10.2 The disk image window

The image is not a bare folder: it has a background picture, a fixed window
size and the two icons positioned either side of an arrow.

Finder is the only thing that can write that layout, and it writes it into a
`.DS_Store`. Driving Finder means Apple events, which ask for permission and
have no hope of working on a build machine — so it is done **once, by hand**,
with `Scripts/make-dmg-layout.sh`, and the resulting `.DS_Store` is committed
under `Scripts/dmg/`. `make-dmg.sh` then just copies it in. The background is
rendered by `Scripts/make-dmg-background.swift` into a TIFF carrying both 1x
and 2x representations, and is committed for the same reason.

Three things about this were only learned by doing it:

- **`diskutil image create from` silently drops `.DS_Store`.** The image built
  fine and opened as a plain folder with no background at all. `hdiutil create
  -srcfolder` preserves it, so the script uses that despite the deprecation
  warning. `diskutil` has no way to convert a writable image to a compressed
  one either, so there is no non-deprecated path today.
- **The volume name is fixed, not versioned.** The background is referenced by
  an alias that embeds the volume name, so `NotchIsland 1.0.0` would break the
  picture the moment the version changed.
- **Finder will not hide its toolbar** on macOS 26 however politely
  AppleScript asks, and there is no text-colour property for icon labels —
  `icon view options` offers text *size*, label position, a background picture
  and a background colour, and nothing else. Since Finder draws those labels
  in a dark grey regardless of appearance, a dark background makes the two
  names nearly unreadable. That is why the window is light.

## 11. Testing without a screen

63 tests across 13 suites, run with `./Scripts/test.sh`. Everything with real
logic in it — geometry, symmetry, notch-measurement limits, the wire format,
content-type inference, playback position, version comparison, release
decoding, checksum parsing — is covered without a display.

### 11.1 Rendering the island

```sh
.build/debug/NotchIsland --render-previews /tmp/previews   # every state
.build/debug/NotchIsland --render-live /tmp/live           # whatever is playing now
.build/debug/NotchIsland --simulate-playback               # a synthetic track
.build/debug/NotchIsland --send-command next               # one command, end to end
```

`ImageRenderer` cannot capture `glassEffect`: the material renders as nothing
offscreen, and worse, `glassEffect` *replaces* what a view draws, so a filled
shape with glass applied vanishes entirely. Materials are layered behind solid
fills so they degrade gracefully.

### 11.2 Driving the real thing

The pointer can be moved with `CGWarpMouseCursorPosition`, which needs no
permission — unlike posting synthetic clicks. That is how the hover fix was
measured: warp to a position, read the app's own log, and compare before and
after.

### 11.3 Getting a real signature

MediaRemote lives in the dyld shared cache, so `nm` and `otool` are useless on
it. `dyld_info -exports` lists the symbols, and lldb gives the prototypes —
load the framework into a throwaway binary of your own and disassemble it
(lldb cannot attach to `/usr/bin/perl`, which is Apple-signed and restricted):

```sh
lldb -b -o "target create ./holder" -o "b main" -o "run" \
     -o 'expr (void*)dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", 2)' \
     -o "disassemble -n MRMediaRemoteGetNowPlayingInfoForClient -c 45" -o quit
```

Read the argument registers in order, and note that anything passed to
`objc_retain` early is an object or a block. This is how the five-argument
playback-queue request, the `ForOrigin` equivalence, and the fact that
"include artwork" is a `BOOL` rather than an object were all established —
after guessed signatures had crashed the probe process repeatedly.

Object shapes come just as cheaply from the ObjC runtime:
`objc_copyClassList` filtered to `MR`, then `class_copyPropertyList`. That is
what revealed that `artworkWidth` is a `double` and `includeArtwork` is
read-only.

## 12. Known limits

- **Browser artwork is not available.** The bytes exist — MediaRemote reports
  768×768 `image/jpeg` — and there is no route to them for an unentitled app.
  Browser playback shows the browser's icon.
- **Menus on the left of the notch can be covered.** They belong to the active
  application and are drawn by the system; no API reserves space against them.
  Nothing can be done from inside an app, and trying made it worse — see the
  README.
- **`mediaremoted` runs as root** and cannot be restarted to clear its state
  without `sudo`, which makes some experiments awkward.
- **One display only.** The island is drawn on the built-in notched screen; on
  an external monitor, or with the lid closed, nothing appears.
