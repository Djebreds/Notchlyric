# NotchLyrics — Quran Mode & Apple Music Support

**Date:** 2026-08-30
**Status:** Approved for planning
**Builds on:** `2026-08-30-notch-lyrics-design.md`

Adds Apple Music as a second playback source, and word-synced Quran recitation
display using the mushaf typeface and real measured word timings.

---

## 1. Verified Findings

Every claim was measured on the target machine during investigation.

### 1.1 Apple Music playhead is accurate enough

`Music.app` exposes the same AppleScript shape as Spotify — `player position`,
`player state`, `current track` (name, artist, album, duration, track number,
persistent ID) — plus `location` (the file path) on `file track`.

Measured over a full 46s track, polling at 1 Hz and interpolating:

```
SYNC: 45 samples, mean drift 0.001s, max 0.010s
```

1 ms mean drift. The existing `PlaybackClock` needs no changes.

### 1.2 macOS arbitrates between media apps

Starting playback in Apple Music **automatically paused Spotify**:

```
before:  spotify: playing   music: paused
after:   spotify: paused    music: playing
```

So simultaneous playback is rare. Source selection still needs a defined rule.

### 1.3 Word timings are real, not estimated

`https://api.quran.com/api/qdc/audio/reciters/{id}/audio_files?chapter={n}&segments=true`
returns per-word segments as `[word_index, start_ms, end_ms]`, **absolute
(file-relative)** in milliseconds.

Data quality across 9,619 segments in 644 verses: **6 malformed (0.06%)** —
truncated tuples such as `[1]`. Guard on `count == 3` and skip.

10 of 11 reciters carry full segments. Reciter 7 is Alafasy.

### 1.4 The audio in the library matches the timings exactly

All 114 surahs were downloaded from `quranicaudio.com` and imported. Durations
cross-checked against the timing data:

```
surah   1: Music=  46.50s  API=  46.00s
surah  18: Music=1996.04s  API=1996.00s
surah  36: Music=1056.42s  API=1056.00s
surah 114: Music=  40.93s  API=  40.00s
```

The API rounds to whole seconds; deltas are rounding only. Al-Fatiha's last word
ends at 46,490 ms against a 46,447 ms file — a ~40 ms match. These are the exact
recordings the timings were measured from, so sync is exact rather than inferred.

### 1.5 The display unit is the mushaf line, not the ayah

Verses are unbounded — 2:282 is 128 words. Mushaf lines are not. Across 1,479
lines sampled:

```
words per line:  min=2   median=9   max=14
p90 = 10   p99 = 12   over 12 words: 7 of 1479 (0.5%)
```

2:282 occupies 15 mushaf lines of 7–11 words each. Every word carries a
`line_number`, so KFGQPC's own layout supplies the breaks. This maps onto the
existing `LyricLine` model unchanged.

### 1.6 quran.com uses per-page glyph fonts

QCF v2 (King Fahd Complex, Uthman Taha calligraphy): **604 font files, one per
mushaf page**, where each glyph is a whole word — `بِسْمِ` is the single
character `ﱁ`. The API supplies `code_v2` (glyph) and `v2_page` (which font).

One glyph per word maps directly onto per-word colouring.

Both formats load and both are reachable:

```
v2/ttf/p1.ttf      HTTP 200          CoreText woff2 register: true
v2/woff2/p1.woff2  HTTP 200 (41 KB)  QCF2001 usable from woff2: true
```

macOS 26 CoreText registers woff2 directly, so fonts are fetched per page and
cached rather than bundling ~24 MB upfront.

**A verse can straddle a page boundary**, so the font must be resolved
**per word** (`v2_page`), never per line.

### 1.7 Library state

114 tracks, album `Quran — Murattal`, artist `Mishary Rashid Alafasy`, genre
`Quran`, track numbers `n/114` matching surah numbers.

---

## 2. Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Sources | `PlaybackSource` protocol; Spotify + Apple Music | Existing bridge becomes one implementation |
| Source selection | The one reporting `playing`; tie broken by most recent start | §1.2 makes ties rare but not impossible |
| Quran detection | genre `Quran` **or** album containing `Quran`, plus track number 1–114, confirmed by duration within ±2 s of the API's chapter duration | Duration is the strong signal (§1.4) |
| Display unit | Mushaf line | §1.5 — bounded at 14 words |
| Font | QCF v2, fetched per page, cached | §1.6 |
| Font size | 23 pt in a 560×104 panel | Chosen from rendered comparison |
| Word emphasis | Existing `.scale` style, `isEstimated: false` | Timings are real |

### Non-goals

- Other reciters (the model allows it; only Alafasy is configured)
- Translations
- Playing audio in-app — Apple Music owns playback
- iPhone / AirPlay sources (settled as blocked)

---

## 3. Architecture

```
SpotifyBridge ─┐
               ├─> PlaybackSource ─> SourceArbiter ─> PlaybackState
MusicBridge ───┘                                          │
                                                          ▼
                         ┌──────────────── PlaybackClock (unchanged)
                         ▼                                │
                   LyricsService                          ▼
              ┌──────────┴───────────┐            OverlayController
       QuranProvider          LRCLIB/NetEase              │
              │                                           ▼
        QuranTimingAPI                          LyricView / QuranView
        QCFFontStore ─────────────────────────────────────┘
```

### 3.1 PlaybackSource

```swift
@MainActor protocol PlaybackSource: AnyObject {
    var id: String { get }                       // "spotify" | "music"
    var onChange: ((PlaybackState?) -> Void)? { get set }
    func start(); func stop()
}
```

`SpotifyBridge` is refactored to conform. `MusicBridge` mirrors it against
`Music.app`, adding `trackNumber` and `genre` to the emitted state.

### 3.2 SourceArbiter

Owns both sources. Emits the state of whichever reports `isPlaying`. If both do,
prefers the one whose playing-transition was most recent. If neither, emits nil.

### 3.3 Model changes

`PlaybackState` gains `trackNumber: Int?` and `genre: String?` (Spotify supplies
nil). `WordToken` gains `glyph: String?` and `fontPage: Int?` — nil for song
lyrics. `LyricsDocument` gains `script: Script` (`.latin` / `.arabic`) so the view
knows how to render without inspecting content.

Cache schema bumps to **3**.

### 3.4 QuranProvider

Recognises a track per §2, maps track number → surah, fetches timings and word
text, and emits a `LyricsDocument` whose lines are **mushaf lines**:

- group words by `(v2_page, line_number)`
- each line's span runs from its first word's start to its last word's end
- skip malformed segments (§1.3)
- map segment indices onto words filtered to `char_type_name == "word"` — the
  text API also returns an `end` marker token per verse that segments omit

Results cache to disk like any other provider, so a surah is fetched once.

### 3.5 QCFFontStore

Fetches `…/hafs/v2/woff2/p{page}.woff2` on demand, caches under Application
Support, registers with CoreText, and returns the font name for a page
(`QCF2{page:03d}`). Falls back to the system font if a page is unavailable.
Resolution is per word (§1.6).

### 3.6 Rendering

`QuranView` renders a mushaf line RTL, concatenating one `Text` run per word
using that word's glyph and page font, coloured by the existing `WordEmphasis`
curves. Verse number shown alongside.

---

## 4. Error Handling

| Condition | Behaviour |
|---|---|
| Neither player running | Hide overlay |
| Both playing | Arbiter picks most recent (§3.2) |
| Quran track but timings unavailable | Fall through to normal providers, then hide |
| Font page fetch fails | Render that word with the system Arabic font |
| Malformed segment | Skip the word (§1.3) |
| Track changes mid-fetch | Cancel; discard stale results |
| Automation denied for Music.app | Log; Spotify continues working |

---

## 5. Testing

Unit, no network or UI:
- `SourceArbiter` — single source, both playing, neither, most-recent tie-break
- `QuranProvider` — mushaf-line grouping, malformed-segment skipping,
  word-index-to-token mapping past the `end` marker, page-straddling verse,
  duration-tolerance rejection, track-number mapping
- `QCFFontStore` — page→name mapping, cache hit/miss, fetch failure fallback
- Model round-trip with the new fields; cache v2 entries rejected

Integration (opt-in): live timing fetch for surah 1.

Manual: play a surah in Apple Music, confirm word-synced Arabic; play a song in
Spotify, confirm lyrics still work.

---

## 6. Phasing

**Phase 1** — `PlaybackSource` + `MusicBridge` + `SourceArbiter`. Apple Music
plays song lyrics through the existing providers. Verifiable on its own.

**Phase 2** — `QuranProvider`, `QCFFontStore`, `QuranView`, mushaf-line display.
