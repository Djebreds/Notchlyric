# NotchLyrics

Time-synced Spotify lyrics in a click-through overlay on macOS — anchored below
the notch, in a menu-bar ear, or bottom-right. Menu-bar app, no Dock icon.

![position: notch](https://img.shields.io/badge/positions-4-black) ![no deps](https://img.shields.io/badge/dependencies-none-black)

## What it does

Reads the playing track and playhead from Spotify via AppleScript, fetches
synced lyrics from LRCLIB (with NetEase as a fallback), and renders the current
line with a per-word karaoke sweep. The overlay floats above the menu bar, joins
every Space, and ignores clicks.

## Requirements

- macOS 14+ (developed and verified on macOS 26.6 Tahoe, Apple Silicon)
- Xcode 26 / Swift 6.3 toolchain
- Spotify desktop app

## Build

```bash
./Scripts/build-app.sh release
open NotchLyrics.app
```

For development:

```bash
swift build && swift run NotchLyricsApp
swift test
```

## First run

macOS will ask for **Automation** permission so the app can read Spotify's
playback state. Approve it. If you miss the prompt, enable it under
System Settings → Privacy & Security → Automation → NotchLyrics → Spotify.

To reset the grant:

```bash
tccutil reset AppleEvents com.local.NotchLyrics
```

**Ad-hoc signing caveat:** the Automation grant is tied to the binary's code
signature. Rebuilding changes it, so macOS may prompt again after each rebuild.
Signing with a real Developer ID instead makes the grant stick.

## Positions

Pick one from the menu-bar icon; it moves live, no restart.

| Position | Behaviour |
|---|---|
| **Below the Notch** (default) | Black panel hanging from the notch, squared top corners and rounded bottom so it reads as one shape with the cutout |
| **Menu Bar (Left / Right)** | Inline text in the display area beside the cutout |
| **Bottom Right** | Floating rounded pill above the Dock |

On displays with no notch, the notch and ear positions fall back to a pill
centred under the menu bar.

## Lyric styles

Also switchable from the menu-bar icon.

| Style | Behaviour |
|---|---|
| **Pop Active Word** (default) | The current word grows ~24% and goes fully lit; sung words step back, upcoming words stay dim. Snappy — the eye tracks one moving emphasis |
| **Fade In Words** | Each word brightens gradually across its own duration. Smoother, but reads slower because every word is mid-fade for its whole span |

Both are wrap-correct: emphasis comes from each word's own progress, not from a
gradient across the block, so words on a second visual row don't light up early.

### Why not *inside* the notch?

The notch is a physical cutout in the display panel — there are no pixels behind
it. On this machine it measures 220 × 38 pt, with real display area only in the
790 pt "ears" either side. Anything claiming to draw "in the notch" is really
drawing directly below it. That's what this does.

## Lyrics sources

Tried in order, first hit wins, results cached to disk by Spotify track ID:

1. **LRCLIB** — free, no API key, no account
2. **NetEase** — fallback, no auth, stronger Asian-language coverage
   (toggle in the menu)

A track with no synced lyrics is remembered for 7 days so it isn't refetched on
every replay. Cache lives at
`~/Library/Application Support/NotchLyrics/cache/`.

### About word-by-word sync

Spotify's own lyrics are `LINE_SYNCED` — one timestamp per line, no word
timings. No free source exposes real per-word data either. So each line's
duration is distributed across its words weighted by character length, and each
word brightens as it comes due. The `WordToken` model carries an `isEstimated`
flag, so a genuine word-level provider can drop in later without changing
anything downstream.

## Architecture

`NotchLyricsCore` is a pure library with no AppKit or SwiftUI import — all
parsing, timing, geometry, and network logic lives there and is unit-tested.
`NotchLyricsApp` is the thin AppKit/SwiftUI shell.

```
SpotifyBridge (1 Hz + PlaybackStateChanged)
      │ PlaybackState
      ▼
PlaybackClock ──60 Hz──> OverlayController ──> OverlayWindow (NSPanel)
      ▲                        │                     │ Anchor
      │                        ▼                     ▼
   samples             LyricsService          LyricView (word sweep)
                    LRCLIB → NetEase
                         │
                    LyricsCache
```

Spotify is polled at 1 Hz because an AppleScript round trip costs ~54 ms warm
(251 ms cold). `PlaybackClock` interpolates between samples against a
`ContinuousClock`, easing corrections under 0.25 s over a 200 ms window and
snapping on anything larger, which it treats as a seek.

## Tests

```bash
swift test
```

79 tests covering LRC parsing (offsets, multi-timestamp lines, enhanced word
tags, NetEase credit lines, malformed input), word-timing distribution, clock
drift and seek detection, anchor geometry against measured hardware values, and
both providers against recorded live-response fixtures. No network, no UI.

## Docs

- Design: `docs/superpowers/specs/2026-08-30-notch-lyrics-design.md`
- Plan: `docs/superpowers/plans/2026-08-30-notch-lyrics.md`

## Notes

Personal, local use. Not sandboxed, not notarized. Lyrics come from third-party
community APIs; be considerate with request volume.
