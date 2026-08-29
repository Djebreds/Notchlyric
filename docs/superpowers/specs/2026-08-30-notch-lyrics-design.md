# NotchLyrics — Design

**Date:** 2026-08-30
**Status:** Approved for planning
**Target:** macOS 26.6 (Tahoe), Apple Silicon, Swift 6.3 / Xcode 26.6

A menu-bar app that displays time-synced Spotify lyrics in an overlay anchored to
the MacBook notch, the menu-bar ear, or the bottom-right corner.

---

## 1. Verified Findings

Every claim below was measured on the target machine, not taken from documentation.

### 1.1 The notch has no pixels

The notch is a physical cutout in the display panel. Measured on this machine:

| Property | Value (points) |
|---|---|
| Built-in display frame | 1800 × 1169 @2x |
| `safeAreaInsets.top` | 38 |
| `auxiliaryTopLeftArea` | (0, 1131, 790, 38) |
| `auxiliaryTopRightArea` | (1010, 1131, 790, 38) |
| Derived notch | **220 wide × 38 tall**, centered at x = 900 |
| Menu bar band | y 1130 → 1169 |

Nothing can render in the 220 × 38 region. "Lyrics in the notch" is therefore
implemented as a panel that **hangs directly below the notch**, visually merged
with it so it reads as one shape.

### 1.2 Spotify exposes playback, not lyrics

Spotify's AppleScript dictionary is fully intact on macOS 26. All 24 exposed
properties were enumerated; **none is `lyrics`**. Available and relevant:
`name`, `artist`, `album`, `id`, `duration`, `artwork url`, `player position`,
`player state`.

Live sample:

```
playing | Summertime Sadness | Lana Del Rey | spotify:track:3BJe4B8zGnqEdQPMvfVjuS | dur=265427 | pos=83.745
```

Two gotchas, both confirmed empirically:

- `duration` is in **milliseconds** despite the dictionary declaring seconds.
- `player position` is in **seconds** as a `Double`, sub-second precision.

`com.spotify.client.PlaybackStateChanged` exists in the Spotify binary and is
usable via `DistributedNotificationCenter` for push updates on play/pause/skip.

### 1.3 AppleScript latency budget

In-process `NSAppleScript`, precompiled once, 15 runs:

```
cold = 251.49 ms | warm avg = 54.25 ms | min = 44.66 ms | max = 66.92 ms
```

Too slow for continuous polling; fine at 1 Hz with local interpolation.
This measurement dictates the `PlaybackClock` design in §3.2.

### 1.4 Spotify's lyrics are line-synced, not word-synced

Spotify's lyrics API reports `syncType: "LINE_SYNCED"`. Word-level timing is not
exposed.

The `karaoke` strings present in the Spotify binary (`KARAOKE_MASK`,
`vocal-removal.scdn.co/karaoke-masks/`, `karaoke_post_vocal_volume_request.proto`)
belong to the **vocal-removal** sing-along feature. They are unrelated to lyric
timing and must not be mistaken for word-sync support.

Consequence: LRCLIB provides the same granularity Spotify itself has.

### 1.5 Free lyrics sources work

**LRCLIB** — `GET https://lrclib.net/api/get`, no API key, 231 ms round trip.
Response fields: `id, trackName, artistName, albumName, duration, instrumental,
plainLyrics, syncedLyrics`. `duration` is in **seconds**.

Word-level tag survey across 5 popular tracks — all line-synced, zero word tags:

```
As It Was            synced OK | line-tags=39 | word-tags=0
Blinding Lights      synced OK | line-tags=40 | word-tags=0
Espresso             synced OK | line-tags=57 | word-tags=0
Bohemian Rhapsody    synced OK | line-tags=56 | word-tags=0
Summertime Sadness   synced OK | line-tags=65 | word-tags=0
```

**NetEase** — no auth, millisecond precision, strong Asian-language coverage.
- Search: `POST https://music.163.com/api/search/get/` (`s`, `type=1`, `limit`), `Referer: https://music.163.com` required.
- Lyric: `GET https://music.163.com/api/song/lyric?id={id}&lv=1&kv=1&tv=-1`
- Returns `lrc.lyric`, plus `tlyric` (translation). Leading `[00:00.000] 作词 : …`
  credit lines must be stripped.

### 1.6 The overlay window works

A borderless `NSWindow` at `CGShieldingWindowLevel()` with
`[.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]` was built
and run. Confirmed: renders above the menu bar (`overlaps menu bar = true`),
`isVisible = true`, `onActiveSpace = true`, survived its full lifetime.

### 1.7 MediaRemote is not an option

macOS 15.4 added entitlement verification in `mediaremoted`.
`MRMediaRemoteGetNowPlayingInfo` returns nil for unentitled apps. Workarounds
require disabling SIP or trampolining through an entitled system binary. Rejected.
AppleScript supersedes it for this use case.

### 1.8 Spotify's own lyrics: high fragility

Since **2025-12-22**, `open.spotify.com/get_access_token` requires a TOTP
generated from a secret extracted from Spotify's web player JS bundle, plus a
`server-time` fetch. The secret rotates and breaks dependents on each rotation.

Since it yields no quality gain over LRCLIB (§1.4), it is included as an
**optional provider, disabled by default, deferred to Phase 2**. It must never be
able to break the default path.

---

## 2. Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Placement | All three, switchable at runtime | Notch panel default; ear and bottom-right share one engine |
| Word sync | Character-weighted interpolated sweep | No free source has real word timings (§1.4); model stays token-shaped for future real data |
| Sources | LRCLIB (Phase 1) → NetEase (Phase 2) → Spotify (opt-in, Phase 2) | LRCLIB and NetEase both verified working with no auth; Phase 1 ships LRCLIB alone so the provider chain is exercised end-to-end before a second source is added |
| Idle behavior | Fade out completely | Zero visual noise when paused or no lyrics |
| Stack | Swift 6 + SwiftUI, SwiftPM, accessory app | Native overlay, low power, no dock icon |

### Non-goals

- Lyrics editing, upload, or contribution back to LRCLIB
- Apple Music or any player other than Spotify
- Translation display (`tlyric` is parsed but not rendered in v1)
- Sandboxing or App Store distribution (personal local use)

---

## 3. Architecture

Ten modules, each independently testable, communicating through value types.

```
DistributedNotificationCenter ─┐
                               ├─> SpotifyBridge ──> PlaybackState
        1 Hz Timer ────────────┘                         │
                                                         ▼
                                    ┌──────────── PlaybackClock (60 Hz)
                                    │                    │
                    trackID changed │                    │ estimatedPosition
                                    ▼                    ▼
                            LyricsService          LyricViewModel
                        (LRCLIB→NetEase→Spotify)         │
                                    │                    ▼
                              LyricsCache          OverlayWindow
                                    │              (Anchor: notch/ear/bottomRight)
                                    └──> LyricsDocument ──┘
```

### 3.1 SpotifyBridge

Owns one precompiled `NSAppleScript`. Emits `PlaybackState`:

```swift
struct PlaybackState: Equatable {
    let trackID: String        // "spotify:track:..."
    let title, artist, album: String
    let durationMs: Int        // millisecond source (§1.2)
    let position: TimeInterval // seconds
    let isPlaying: Bool
    let sampledAt: ContinuousClock.Instant
}
```

Runs the script off the main thread. Polls at 1 Hz while playing, backs off to
5 Hz-equivalent (every 5 s) while paused, and re-polls immediately on
`PlaybackStateChanged`. Reports `nil` when Spotify is not running.

**Dependency:** `NSAppleEventsUsageDescription` in Info.plist; TCC Automation
grant on first run.

### 3.2 PlaybackClock

Converts 1 Hz samples into a continuous 60 Hz position estimate.

- Between samples: `estimate = lastSample.position + elapsed(monotonic)`
- On new sample: if `|estimate - actual| < 0.25s`, ease the correction over
  ~200 ms to avoid visible jitter; if `>= 0.25s`, treat as a **seek** and snap.
- On pause: freeze. On play: rebase.

Uses `ContinuousClock`, never wall-clock, so sleep/wake cannot corrupt it.
This module is pure logic with an injected clock — fully unit-testable, no I/O.

### 3.3 LyricsProvider / LyricsService

```swift
protocol LyricsProvider: Sendable {
    var id: String { get }
    func fetch(_ track: TrackQuery) async throws -> LyricsDocument?
}
```

`LyricsService` tries enabled providers in priority order, returns the first
non-nil result, and writes it to `LyricsCache`. A provider that throws is logged
and skipped — one failing source never blocks the others.

Matching uses title + artist + duration, with a duration tolerance of ±3 s to
reject wrong-version matches (live cuts, remixes, extended edits).

### 3.4 LRCParser

Parses both standard `[mm:ss.xx]` and enhanced `<mm:ss.xx>` word tags into:

```swift
struct LyricLine { let start: TimeInterval; var end: TimeInterval; let words: [WordToken] }
struct WordToken { let text: String; var start, end: TimeInterval; let isEstimated: Bool }
```

When word tags are absent (always, in practice — §1.4), timings are estimated by
distributing the line's duration across words weighted by `count + 1`, and
`isEstimated` is set true. A future real word-level provider populates the same
type with `isEstimated = false` and requires no downstream change.

`end` for the final line falls back to track duration.

### 3.5 LyricsCache

JSON documents under
`~/Library/Application Support/NotchLyrics/cache/{trackID}.json`, keyed by
Spotify track ID. Negative results are cached too (with a shorter TTL) so
lyric-less tracks are not refetched on every replay.

### 3.6 OverlayWindow

`NSPanel` subclass, configured exactly as validated in §1.6:

```swift
isOpaque = false; backgroundColor = .clear; hasShadow = false
ignoresMouseEvents = true            // toggled false on hover-to-expand
level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
```

Observes `NSApplication.didChangeScreenParametersNotification` and
`NSWorkspace.activeSpaceDidChangeNotification` to re-anchor when displays change,
which satisfies the "stays in place when I move screens" requirement.

### 3.7 Anchor

Pure geometry. Given an `NSScreen` and a `Position`, returns an `NSRect`.

```swift
enum Position { case notch, earLeft, earRight, bottomRight }
```

- `.notch` — panel width `max(320, notchWidth + 200)`, centered on
  `(auxLeft.maxX + auxRight.minX) / 2`, top edge flush with `screen.frame.maxY`,
  top corners squared and bottom corners rounded so it merges with the cutout.
- `.earLeft` / `.earRight` — constrained to the corresponding
  `auxiliaryTop*Area`, so it can never overlap the cutout.
- `.bottomRight` — inset from `visibleFrame`, respecting the Dock.

**No-notch screens** (external monitors, where `safeAreaInsets.top == 0` and the
auxiliary areas are `nil`): `.notch` and `.ear` degrade to a top-centered pill
below the menu bar. Never crash, never render off-screen.

### 3.8 LyricView (SwiftUI)

Current line rendered at full weight; previous and next lines dimmed and smaller.
The word sweep is a foreground gradient mask whose leading edge is driven by the
interpolated progress across `words`. Sung text is bright, upcoming text dim,
with a short soft falloff at the boundary rather than a hard cut.

Transitions between lines use opacity plus a small vertical offset. Rendering is
driven by a `TimelineView(.animation)` bound to `PlaybackClock`.

### 3.9 MenuBarController

`NSStatusItem` menu: position mode, enabled sources, font size, opacity,
launch-at-login, quit. No preferences window in v1.

### 3.10 Settings

`UserDefaults`-backed observable struct. Changing position re-anchors the window
live without restart.

---

## 4. Error Handling

| Condition | Behavior |
|---|---|
| Spotify not running | Hide overlay; poll at low frequency |
| Automation permission denied | Menu-bar icon shows warning; menu item opens the relevant System Settings pane |
| No network | Serve from cache; fail silently otherwise |
| No lyrics from any provider | Cache the negative result; fade out (§2) |
| Instrumental track (`instrumental: true`) | Fade out; do not query further providers |
| Provider throws / malformed payload | Log, skip to next provider |
| Track changes mid-fetch | Cancel the in-flight `Task`; results for a stale trackID are discarded |
| Seek / scrub | `PlaybackClock` snaps (§3.2) |
| Display disconnected | Re-anchor to `NSScreen.main` |

---

## 5. Testing

**Unit — no network, no UI:**
- `LRCParser` — standard tags, enhanced tags, malformed lines, blank lines,
  credit-line stripping, final-line `end` fallback, word-weight distribution
- `PlaybackClock` — drift correction, seek detection at the 0.25 s boundary,
  pause/resume, injected clock only
- `Anchor` — notch geometry against the measured values in §1.1, no-notch
  fallback, Dock-aware bottom-right, off-screen rejection
- Provider decoding — recorded JSON fixtures from the live responses in §1.5,
  including a 404 and an instrumental track
- Duration-tolerance matching — rejects a match outside ±3 s

**Integration — opt-in, network:**
- Live LRCLIB and NetEase fetches for a known track

**Manual:**
- Overlay above menu bar, across Spaces, over a fullscreen app, on
  display connect/disconnect

---

## 6. Build & Distribution

SwiftPM executable target assembled into a `.app` bundle by a build script
(`Contents/MacOS`, `Contents/Info.plist`, `Contents/Resources`), then ad-hoc
code-signed. Personal local use — no notarization.

**Known consequence:** ad-hoc signing means the TCC Automation grant is tied to
the binary's cdhash, so macOS may re-prompt for permission after each rebuild.
Acceptable for local development; documented in the README.

---

## 7. Phasing

**Phase 1 — working app**
SpotifyBridge, PlaybackClock, LRCParser, LRCLIB provider, cache, OverlayWindow,
Anchor (all three positions), LyricView with word sweep, menu bar, build script.

**Phase 2 — coverage and polish**
NetEase provider, optional Spotify provider behind the TOTP flow (§1.8),
hover-to-expand full-lyrics view, launch-at-login.
