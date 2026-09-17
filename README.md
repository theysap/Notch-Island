<div align="center">

<img src="docs/images/icon.png" width="128" alt="NotchIsland icon">

# NotchIsland

**A Dynamic Island for the MacBook notch, for whatever is playing.**

Artwork to the left of the camera housing, an animation to the right that tells
you *what kind* of thing is playing, and a full mini player when you reach for
it.

<img src="docs/images/music-compact.png" width="620" alt="The collapsed island showing artwork and equaliser bars">

</div>

---

## What it does

NotchIsland turns the notch into a media display. It works with anything that
publishes now-playing information to macOS — Apple Music, Spotify, Podcasts,
IINA, VLC, and anything playing in Safari, Chrome or Arc.

**At rest**, it sits in the menu bar strip: artwork on the left of the notch, an
activity indicator on the right, and nothing at all when nothing is playing.

**Hover the top of the screen** and it opens into a mini player.

<img src="docs/images/music-expanded.png" width="620" alt="The expanded mini player">

### The indicator knows what it is looking at

This is the part that is not just decoration. The right-hand animation differs
by content type, so a glance tells you whether that sound is a song, a video or
someone talking.

| | |
|---|---|
| **Music** — equaliser bars, each driven by two sine waves of different frequency so they drift rather than march | <img src="docs/images/music-compact.png" width="300"> |
| **Podcast** — a travelling waveform on a speech envelope, dropping close to silence between phrases | <img src="docs/images/podcast-compact.png" width="300"> |
| **Video** — the real playback position, as a track with a lit head | <img src="docs/images/video-compact.png" width="300"> |

macOS reports the media type directly for native applications. Browsers report
nothing at all, so those are classified from the track tags and duration: a full
set of artist and album tags is a streaming music service, something running
past half an hour is an episode, and anything else is video.

### The mini player

Artwork, title and artist, a draggable progress bar with elapsed and remaining
time, and previous / play-pause / next. Long titles scroll. Dragging the
progress bar moves the playhead immediately and seeks the source on release,
rather than firing a seek command per pixel.

Playback that reports no duration — live radio, a stream — gets a static bar
rather than a progress bar implying a position that does not exist.

<img src="docs/images/paused-expanded.png" width="620" alt="The mini player with playback paused">

## Requirements

- macOS 26 or later
- Apple silicon
- A MacBook with a notch

The island is only ever drawn on a built-in display that physically has a notch.
On an external monitor, or with the lid closed, nothing appears.

## Installing

Download the `.dmg` from [Releases](../../releases), open it, and drag
NotchIsland to Applications.

**The first launch needs a right-click.** The app is signed ad-hoc rather than
with a paid Developer ID, so Gatekeeper will not open it on a double-click.
Right-click the app → **Open** → **Open**. This is needed once.

Then open Settings from the menu bar icon and turn on **Launch at login**.

## Settings

| Setting | What it does |
|---|---|
| Launch at login | Registers the app as a login item through `SMAppService`. |
| Show menu bar icon | The status item carries the current track and transport controls. |
| Hide the island while paused | Off by default, so the island stays put when you pause. |
| Keep menu bar icons clear of the island | Reserves menu bar width so status icons are laid out beside the island. On by default. |

### About that last one

The island is wider than the notch — that is where the artwork and the indicator
go — so it would otherwise cover whatever is in the menu bar beside the notch.

For the **status icons on the right**, NotchIsland reserves that width with an
empty status item. macOS then lays the real icons out beside the island and
folds whatever no longer fits behind its own overflow chevron.

For the **menus on the left** — File, Edit, and so on — there is no equivalent.
Those belong to the active application and are drawn by the system; no API
exists to reserve space against them or to fold them. macOS already truncates
them at the notch with its own chevron, but an application with a great many
menus can still reach under the island's left edge. If that bothers you in
practice, the island's reach is one constant in `IslandLayout.compactSideWidth`.

## How it works

Reading what is playing system-wide means MediaRemote, a private framework. As
of macOS 15.4, `mediaremoted` only answers those queries for processes whose
main executable is signed by Apple. An ordinary application gets a callback with
an empty dictionary — no error, no denial, just nothing. This was verified on
macOS 27.0 before a line of this app was written.

The check looks at the *process*, not at what the process has loaded. So
NotchIsland ships a small dynamic library and runs it inside `/usr/bin/perl`,
which Apple signs:

```
NotchIsland  ──spawns──▶  /usr/bin/perl  ──loads──▶  libNotchMediaBridge.dylib
     ▲                                                        │
     └──────────── newline-delimited JSON over a pipe ─────────┘
```

The library's constructor takes the host process over and never returns. It
streams now-playing state out as JSON and reads transport commands back in. No
permissions are required — not Accessibility, not Screen Recording, not
Automation — and nothing is injected into any other application.

The helper exits about a second after the app does. It polls its parent to
decide that, because its own stdin never reaches EOF: the write end of that pipe
stays open inside the helper itself, and neither a process-exit source nor
reparenting to launchd proved reliable enough to depend on.

### Notch geometry

The notch is measured from the display at runtime rather than looked up from a
table of Mac models — every notched Mac reports the areas either side of its
camera housing, which makes this exact on models that do not exist yet. The
island is symmetric about the housing by construction and centred on the
housing rather than on the screen.

## Building

Only the Command Line Tools are needed; Xcode is not.

```sh
swift build                 # build
./Scripts/test.sh           # run the tests
./Scripts/build-app.sh      # assemble dist/NotchIsland.app
./Scripts/make-dmg.sh       # package dist/NotchIsland-<version>.dmg
```

To sign with a real identity, set `DEVELOPER_ID_APPLICATION` before building:

```sh
export DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (TEAMID)"
./Scripts/build-app.sh
```

### Development

```sh
./Scripts/install-hooks.sh                      # formatting, build and tests before each commit
.build/debug/NotchIsland --simulate-playback    # island without commandeering your audio
.build/debug/NotchIsland --render-previews /tmp/previews   # render the island to PNG
```

Both flags are debug-only and compiled out of release builds. They exist because
capturing a floating panel needs screen-recording permission, which makes the UI
awkward to inspect any other way.

Note that view-local state lives in `@Observable` models rather than `@State`:
`@State` became a macro in the macOS 27 SDK and its plugin ships only with
Xcode, not with the Command Line Tools.

## Contributing

Commit subjects are the version the commit brings the project to — `v0.4.0`,
`v1.0.0` — with the explanation in the body. The `commit-msg` hook enforces it,
and `CHANGELOG.md` is kept up to date alongside.

## License

MIT. See [LICENSE](LICENSE).
