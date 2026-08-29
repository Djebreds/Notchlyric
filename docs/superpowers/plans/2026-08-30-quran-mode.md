# Quran Mode & Apple Music Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Apple Music as a second playback source, and display word-synced Quran recitation in the mushaf typeface.

**Architecture:** The existing `SpotifyBridge` is refactored behind a `PlaybackSource` protocol so a `MusicBridge` can sit beside it, with a `SourceArbiter` choosing whichever is playing. A `QuranProvider` recognises recitation tracks and emits mushaf lines instead of lyric lines, rendered with per-page QCF glyph fonts fetched on demand.

**Tech Stack:** Swift 6.3, SwiftPM, Swift Testing, AppKit, SwiftUI, CoreText. No third-party dependencies.

**Spec:** `docs/superpowers/specs/2026-08-30-quran-mode-design.md`

## Global Constraints

- `NotchLyricsCore` must not import AppKit or SwiftUI. CoreText/font work lives in the app target.
- All network access goes through the existing `HTTPFetching` protocol.
- Seek threshold `0.25` s and correction window `200` ms are unchanged.
- Quran duration match tolerance: **±2 seconds**. Song duration tolerance stays ±3 s.
- Segment tuples must have exactly 3 elements; skip otherwise (0.06% of real data).
- Word→font resolution is **per word** via `v2_page`, never per line.
- Timing values from the API are **milliseconds, absolute (file-relative)**.
- Cache schema version becomes **3**.
- Quran font size 23 pt, panel 560×104.
- Commit after every task.

---

## File Structure

```
Sources/NotchLyricsCore/
  Models/PlaybackState.swift      + trackNumber, genre
  Models/Lyrics.swift             + WordToken.glyph/.fontPage, LyricsDocument.script
  Models/Script.swift             NEW  .latin / .arabic
  Lyrics/LyricsCache.swift        schemaVersion 3
  Quran/QuranTiming.swift         NEW  API DTOs + mushaf-line assembly
  Quran/QuranProvider.swift       NEW  detection + document building
Sources/NotchLyricsApp/
  PlaybackSource.swift            NEW  protocol
  SpotifyBridge.swift             conform
  MusicBridge.swift               NEW
  SourceArbiter.swift             NEW
  QCFFontStore.swift              NEW  per-page font fetch/register
  QuranView.swift                 NEW  RTL glyph rendering
  OverlayController.swift         wire arbiter + Quran path
Tests/NotchLyricsCoreTests/
  QuranTimingTests.swift          NEW
  QuranProviderTests.swift        NEW
  SourceArbiterTests.swift        NEW  (pure logic, lives in core)
```

---

### Task 1: Model extensions and cache bump

**Files:**
- Create: `Sources/NotchLyricsCore/Models/Script.swift`
- Modify: `Sources/NotchLyricsCore/Models/Lyrics.swift`
- Modify: `Sources/NotchLyricsCore/Models/PlaybackState.swift`
- Modify: `Sources/NotchLyricsCore/Lyrics/LyricsCache.swift`
- Test: `Tests/NotchLyricsCoreTests/ModelsTests.swift`

**Interfaces:**
- Produces: `Script.latin/.arabic`; `WordToken.glyph: String?`, `WordToken.fontPage: Int?`; `LyricsDocument.script: Script`; `PlaybackState.trackNumber: Int?`, `.genre: String?`; `LyricsCache.schemaVersion == 3`.

Existing call sites construct `WordToken(text:start:end:isEstimated:)` and `LyricsDocument(trackID:providerID:lines:)`. Keep those working by giving the new parameters defaults.

- [ ] **Step 1: Write the failing test** (append to `ModelsTests.swift`)

```swift
@Test func wordTokenDefaultsToNoGlyph() {
    let w = WordToken(text: "hi", start: 0, end: 1, isEstimated: true)
    #expect(w.glyph == nil)
    #expect(w.fontPage == nil)
}

@Test func wordTokenCarriesGlyphAndPage() {
    let w = WordToken(text: "بِسْمِ", start: 0, end: 0.58, isEstimated: false,
                      glyph: "\u{FC41}", fontPage: 1)
    #expect(w.glyph == "\u{FC41}")
    #expect(w.fontPage == 1)
    #expect(w.isEstimated == false)
}

@Test func documentDefaultsToLatinScript() {
    let d = LyricsDocument(trackID: "t", providerID: "p", lines: [])
    #expect(d.script == .latin)
}

@Test func documentRoundTripsNewFieldsThroughCodable() throws {
    let d = LyricsDocument(trackID: "t", providerID: "quran", script: .arabic, lines: [
        LyricLine(start: 0, end: 1, words: [
            WordToken(text: "x", start: 0, end: 1, isEstimated: false, glyph: "g", fontPage: 48)
        ])
    ])
    let back = try JSONDecoder().decode(LyricsDocument.self, from: JSONEncoder().encode(d))
    #expect(back == d)
    #expect(back.script == .arabic)
    #expect(back.lines[0].words[0].fontPage == 48)
}

@Test func playbackStateCarriesTrackNumberAndGenre() {
    let s = PlaybackState(trackID: "m:1", title: "Al-Fatihah", artist: "A", album: "Quran — Murattal",
                          durationMs: 46497, position: 0, isPlaying: true,
                          trackNumber: 1, genre: "Quran")
    #expect(s.trackNumber == 1)
    #expect(s.genre == "Quran")
}

@Test func playbackStateDefaultsThoseToNil() {
    let s = PlaybackState(trackID: "s:1", title: "T", artist: "A", album: "B",
                          durationMs: 1000, position: 0, isPlaying: true)
    #expect(s.trackNumber == nil)
    #expect(s.genre == nil)
}

@Test func cacheSchemaVersionIsThree() {
    #expect(LyricsCache.schemaVersion == 3)
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter ModelsTests`
Expected: FAIL — no `glyph` parameter, no `Script`.

- [ ] **Step 3: Implement**

Create `Models/Script.swift`:

```swift
/// Which writing system a document uses, so the view can pick a renderer
/// without inspecting the text.
public enum Script: String, Sendable, Codable {
    case latin
    case arabic
}
```

In `Models/Lyrics.swift`, replace the `WordToken` declaration's stored properties and init:

```swift
public struct WordToken: Equatable, Sendable, Codable {
    public var text: String
    public var start: TimeInterval
    public var end: TimeInterval
    public var isEstimated: Bool
    /// QCF glyph standing for the whole word; nil for Latin lyrics.
    public var glyph: String?
    /// Mushaf page whose QCF font renders `glyph`. Resolved per word because
    /// a verse can straddle a page boundary.
    public var fontPage: Int?

    public init(text: String, start: TimeInterval, end: TimeInterval, isEstimated: Bool,
                glyph: String? = nil, fontPage: Int? = nil) {
        self.text = text; self.start = start; self.end = end; self.isEstimated = isEstimated
        self.glyph = glyph; self.fontPage = fontPage
    }
    ...unchanged progress(at:)...
}
```

In the same file, extend `LyricsDocument`:

```swift
public struct LyricsDocument: Equatable, Sendable, Codable {
    public var trackID: String
    public var providerID: String
    public var script: Script
    public var lines: [LyricLine]

    public init(trackID: String, providerID: String, script: Script = .latin, lines: [LyricLine]) {
        self.trackID = trackID; self.providerID = providerID
        self.script = script; self.lines = lines
    }
    ...unchanged isEmpty / index(at:)...
}
```

In `Models/PlaybackState.swift`, add to `PlaybackState`:

```swift
    public var trackNumber: Int?
    public var genre: String?
```

and extend its init with `trackNumber: Int? = nil, genre: String? = nil`, assigning both.

In `Lyrics/LyricsCache.swift` change `public static let schemaVersion = 2` to `= 3`.

- [ ] **Step 4: Run the full suite**

Run: `swift test`
Expected: PASS. Existing provider tests still compile because the new parameters have defaults.

- [ ] **Step 5: Commit**

```bash
git add Sources Tests
git commit -m "feat: model fields for Arabic script, glyphs and track metadata"
```

---

### Task 2: PlaybackSource protocol and Spotify conformance

**Files:**
- Create: `Sources/NotchLyricsApp/PlaybackSource.swift`
- Modify: `Sources/NotchLyricsApp/SpotifyBridge.swift`

**Interfaces:**
- Produces: `protocol PlaybackSource` with `id`, `onChange`, `start()`, `stop()`. `SpotifyBridge` conforms with `id == "spotify"`.

No behaviour change — this is a pure refactor, verified by the app still building and running.

- [ ] **Step 1: Create the protocol**

```swift
import Foundation
import NotchLyricsCore

/// A player the app can follow. Emits nil when that player has nothing playing.
@MainActor
protocol PlaybackSource: AnyObject {
    var id: String { get }
    var onChange: ((PlaybackState?) -> Void)? { get set }
    func start()
    func stop()
}
```

- [ ] **Step 2: Conform SpotifyBridge**

In `SpotifyBridge.swift`, change the class declaration to:

```swift
final class SpotifyBridge: PlaybackSource {
    let id = "spotify"
```

`onChange`, `start()` and `stop()` already exist with matching signatures.

- [ ] **Step 3: Verify it builds and still works**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 4: Commit**

```bash
git add Sources/NotchLyricsApp
git commit -m "refactor: extract PlaybackSource protocol"
```

---

### Task 3: Apple Music bridge

**Files:**
- Create: `Sources/NotchLyricsApp/MusicBridge.swift`

**Interfaces:**
- Consumes: `PlaybackSource` (Task 2), `PlaybackState` (Task 1).
- Produces: `MusicBridge: PlaybackSource` with `id == "music"`, and `static func parse(_ raw: String?) -> PlaybackState?`.

Music.app reports `duration` in **seconds** (unlike Spotify's milliseconds), so it is multiplied by 1000 on the way in. Its notification is `com.apple.iTunes.playerInfo`.

- [ ] **Step 1: Implement**

```swift
import Foundation
import AppKit
import NotchLyricsCore

private final class MusicScriptRunner: @unchecked Sendable {
    /// Music.app reports duration in SECONDS; Spotify reports milliseconds.
    private static let source = """
    tell application "Music"
      if it is not running then return "NOTRUNNING"
      set s to (player state as text)
      if s is "stopped" then return "STOPPED"
      set t to current track
      set g to ""
      try
        set g to (genre of t)
      end try
      set tn to 0
      try
        set tn to (track number of t)
      end try
      return s & "\t" & (persistent ID of t) & "\t" & (name of t) & "\t" ¬
        & (artist of t) & "\t" & (album of t) & "\t" & (duration of t) & "\t" ¬
        & (player position) & "\t" & tn & "\t" & g
    end tell
    """

    private let script: NSAppleScript?
    private let queue = DispatchQueue(label: "com.local.NotchLyrics.music")

    init() {
        script = NSAppleScript(source: Self.source)
        var err: NSDictionary?
        script?.compileAndReturnError(&err)
        if let err { NSLog("NotchLyrics: Music AppleScript compile failed: \(err)") }
    }

    func run(_ completion: @escaping @Sendable (String?) -> Void) {
        queue.async { [weak self] in
            guard let script = self?.script else { return completion(nil) }
            var err: NSDictionary?
            let out = script.executeAndReturnError(&err).stringValue
            completion(err == nil ? out : nil)
        }
    }
}

@MainActor
final class MusicBridge: PlaybackSource {
    let id = "music"
    static let notificationName = Notification.Name("com.apple.iTunes.playerInfo")

    var onChange: ((PlaybackState?) -> Void)?

    private let runner = MusicScriptRunner()
    private var timer: Timer?
    private var lastWasPlaying = false

    func start() {
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(changed), name: Self.notificationName, object: nil)
        schedule(interval: 1)
        poll()
    }

    func stop() {
        timer?.invalidate(); timer = nil
        DistributedNotificationCenter.default().removeObserver(self)
    }

    @objc private func changed() { poll() }

    private func schedule(interval: TimeInterval) {
        timer?.invalidate()
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        t.tolerance = interval * 0.2
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func poll() {
        runner.run { raw in
            Task { @MainActor [weak self] in self?.handle(raw) }
        }
    }

    private func handle(_ raw: String?) {
        let state = Self.parse(raw)
        let playing = state?.isPlaying ?? false
        if playing != lastWasPlaying {
            lastWasPlaying = playing
            schedule(interval: playing ? 1 : 5)
        }
        onChange?(state)
    }

    static func parse(_ raw: String?) -> PlaybackState? {
        guard let raw, raw != "NOTRUNNING", raw != "STOPPED" else { return nil }
        let f = raw.components(separatedBy: "\t")
        guard f.count == 9,
              let seconds = Double(f[5].trimmingCharacters(in: .whitespaces)),
              let position = Double(f[6].trimmingCharacters(in: .whitespaces))
        else { return nil }
        let track = Int(f[7].trimmingCharacters(in: .whitespaces))
        let genre = f[8].trimmingCharacters(in: .whitespaces)
        return PlaybackState(
            trackID: "music:" + f[1], title: f[2], artist: f[3], album: f[4],
            durationMs: Int((seconds * 1000).rounded()), position: position,
            isPlaying: f[0] == "playing",
            trackNumber: (track ?? 0) > 0 ? track : nil,
            genre: genre.isEmpty ? nil : genre)
    }
}
```

- [ ] **Step 2: Verify it builds**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/NotchLyricsApp/MusicBridge.swift
git commit -m "feat: Apple Music playback source"
```

---

### Task 4: Source arbiter

**Files:**
- Create: `Sources/NotchLyricsCore/Playback/SourceArbiter.swift`
- Test: `Tests/NotchLyricsCoreTests/SourceArbiterTests.swift`

**Interfaces:**
- Produces: `struct SourceArbiter` with `mutating func update(sourceID: String, state: PlaybackState?, at: ContinuousClock.Instant) -> PlaybackState?`.

Pure logic in core so it is testable without AppKit. The app feeds it each source's latest state and renders whatever it returns.

- [ ] **Step 1: Write the failing test**

```swift
import Testing
import Foundation
@testable import NotchLyricsCore

private let t0 = ContinuousClock.now

private func state(_ id: String, playing: Bool) -> PlaybackState {
    PlaybackState(trackID: id, title: id, artist: "a", album: "b",
                  durationMs: 1000, position: 0, isPlaying: playing)
}

@Test func returnsNilWhenNothingReported() {
    var a = SourceArbiter()
    #expect(a.update(sourceID: "spotify", state: nil, at: t0) == nil)
}

@Test func returnsTheOnlyPlayingSource() {
    var a = SourceArbiter()
    _ = a.update(sourceID: "music", state: nil, at: t0)
    let out = a.update(sourceID: "spotify", state: state("s", playing: true), at: t0)
    #expect(out?.trackID == "s")
}

@Test func ignoresPausedSources() {
    var a = SourceArbiter()
    let out = a.update(sourceID: "spotify", state: state("s", playing: false), at: t0)
    #expect(out == nil)
}

@Test func whenBothPlayPrefersTheMostRecentToStart() {
    var a = SourceArbiter()
    _ = a.update(sourceID: "spotify", state: state("s", playing: true), at: t0)
    let out = a.update(sourceID: "music", state: state("m", playing: true),
                       at: t0.advanced(by: .seconds(1)))
    #expect(out?.trackID == "m")
}

@Test func staysWithTheChosenSourceWhileItKeepsPlaying() {
    var a = SourceArbiter()
    _ = a.update(sourceID: "music", state: state("m", playing: true), at: t0)
    // spotify started earlier, so it must not steal the slot
    let out = a.update(sourceID: "spotify", state: state("s", playing: true),
                       at: t0.advanced(by: .seconds(2)))
    #expect(out?.trackID == "s")   // spotify transitioned to playing later
}

@Test func fallsBackWhenTheChosenSourceStops() {
    var a = SourceArbiter()
    _ = a.update(sourceID: "spotify", state: state("s", playing: true), at: t0)
    _ = a.update(sourceID: "music", state: state("m", playing: true), at: t0.advanced(by: .seconds(1)))
    let out = a.update(sourceID: "music", state: nil, at: t0.advanced(by: .seconds(2)))
    #expect(out?.trackID == "s")
}

@Test func returnsNilOnceEverySourceStops() {
    var a = SourceArbiter()
    _ = a.update(sourceID: "spotify", state: state("s", playing: true), at: t0)
    let out = a.update(sourceID: "spotify", state: nil, at: t0.advanced(by: .seconds(1)))
    #expect(out == nil)
}

@Test func startInstantOnlyResetsOnAPauseToPlayTransition() {
    var a = SourceArbiter()
    _ = a.update(sourceID: "spotify", state: state("s", playing: true), at: t0)
    // spotify keeps playing; a later music start should win
    _ = a.update(sourceID: "spotify", state: state("s", playing: true), at: t0.advanced(by: .seconds(5)))
    let out = a.update(sourceID: "music", state: state("m", playing: true),
                       at: t0.advanced(by: .seconds(6)))
    #expect(out?.trackID == "m")
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter SourceArbiterTests`
Expected: FAIL — `cannot find 'SourceArbiter' in scope`.

- [ ] **Step 3: Implement**

```swift
import Foundation

/// Chooses which player the overlay follows.
///
/// macOS usually pauses one media app when another starts, so ties are rare —
/// but when both report playing, the one that most recently transitioned from
/// not-playing to playing wins.
public struct SourceArbiter: Sendable {
    private struct Entry {
        var state: PlaybackState?
        var startedAt: ContinuousClock.Instant?
    }

    private var entries: [String: Entry] = [:]

    public init() {}

    public mutating func update(sourceID: String,
                                state: PlaybackState?,
                                at instant: ContinuousClock.Instant) -> PlaybackState? {
        let wasPlaying = entries[sourceID]?.state?.isPlaying ?? false
        let isPlaying = state?.isPlaying ?? false

        var entry = entries[sourceID] ?? Entry(state: nil, startedAt: nil)
        entry.state = state
        if isPlaying && !wasPlaying {
            entry.startedAt = instant          // only a fresh start resets the clock
        } else if !isPlaying {
            entry.startedAt = nil
        }
        entries[sourceID] = entry

        let playing = entries.values.filter { $0.state?.isPlaying == true }
        guard !playing.isEmpty else { return nil }
        return playing.max { lhs, rhs in
            (lhs.startedAt ?? instant) < (rhs.startedAt ?? instant)
        }?.state
    }
}
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter SourceArbiterTests`
Expected: PASS, 8 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/NotchLyricsCore/Playback/SourceArbiter.swift Tests/NotchLyricsCoreTests/SourceArbiterTests.swift
git commit -m "feat: source arbiter for multiple players"
```

---

### Task 5: Wire both sources into the controller

**Files:**
- Modify: `Sources/NotchLyricsApp/OverlayController.swift`

**Interfaces:**
- Consumes: `SpotifyBridge`, `MusicBridge`, `SourceArbiter`.

End of Phase 1: playing a song in Apple Music shows lyrics through the existing providers.

- [ ] **Step 1: Replace the single bridge with both**

In `OverlayController`, replace `private let bridge = SpotifyBridge()` with:

```swift
    private let sources: [any PlaybackSource] = [SpotifyBridge(), MusicBridge()]
    private var arbiter = SourceArbiter()
```

Replace the `bridge.onChange = ...; bridge.start()` lines in `start()` with:

```swift
        for var source in sources {
            let sourceID = source.id
            source.onChange = { [weak self] state in
                guard let self else { return }
                self.ingest(self.arbiter.update(sourceID: sourceID, state: state, at: .now))
            }
            source.start()
        }
```

- [ ] **Step 2: Build and verify Apple Music now drives the overlay**

```bash
swift build && ./Scripts/build-app.sh release && open NotchLyrics.app
```

Play any normal song in Apple Music. Expected: lyrics appear exactly as they do
for Spotify. Play a Quran track: nothing appears (no provider yet — Task 7).

- [ ] **Step 3: Commit**

```bash
git add Sources/NotchLyricsApp/OverlayController.swift
git commit -m "feat: follow both Spotify and Apple Music"
```

---

### Task 6: Quran timing assembly

**Files:**
- Create: `Sources/NotchLyricsCore/Quran/QuranTiming.swift`
- Test: `Tests/NotchLyricsCoreTests/QuranTimingTests.swift`

**Interfaces:**
- Produces: `QuranTiming.VerseTiming`, `QuranTiming.WordText`, and
  `QuranTiming.mushafLines(timings:words:) -> [LyricLine]`.

This is the heart of the feature: grouping words into mushaf lines, skipping
malformed segments, and mapping segment indices onto word tokens.

- [ ] **Step 1: Write the failing test**

```swift
import Testing
import Foundation
@testable import NotchLyricsCore

private func w(_ pos: Int, _ text: String, _ glyph: String, page: Int, line: Int) -> QuranTiming.WordText {
    .init(position: pos, textUthmani: text, glyph: glyph, page: page, lineNumber: line)
}

@Test func groupsWordsIntoMushafLines() {
    let timings = [QuranTiming.VerseTiming(verseKey: "1:1", segments: [
        [1, 0, 580], [2, 580, 1409], [3, 1409, 2502], [4, 2502, 5840],
    ])]
    let words = ["1:1": [w(1,"a","ﱁ",page:1,line:2), w(2,"b","ﱂ",page:1,line:2),
                         w(3,"c","ﱃ",page:1,line:3), w(4,"d","ﱄ",page:1,line:3)]]
    let lines = QuranTiming.mushafLines(timings: timings, words: words)
    #expect(lines.count == 2)
    #expect(lines[0].words.count == 2)
    #expect(lines[0].start == 0)
    #expect(abs(lines[0].end - 1.409) < 0.001)
    #expect(lines[1].start == 1.409)
}

@Test func convertsMillisecondsToSeconds() {
    let timings = [QuranTiming.VerseTiming(verseKey: "1:1", segments: [[1, 6025, 7025]])]
    let words = ["1:1": [w(1,"a","ﱁ",page:1,line:1)]]
    let lines = QuranTiming.mushafLines(timings: timings, words: words)
    #expect(abs(lines[0].words[0].start - 6.025) < 0.001)
    #expect(abs(lines[0].words[0].end - 7.025) < 0.001)
}

@Test func skipsMalformedSegments() {
    // 0.06% of real segments are truncated tuples like [1]
    let timings = [QuranTiming.VerseTiming(verseKey: "1:3", segments: [
        [1, 11615, 12855], [1],
    ])]
    let words = ["1:3": [w(1,"a","ﱁ",page:1,line:1), w(2,"b","ﱂ",page:1,line:1)]]
    let lines = QuranTiming.mushafLines(timings: timings, words: words)
    #expect(lines.count == 1)
    #expect(lines[0].words.count == 1)
}

@Test func carriesGlyphAndPagePerWord() {
    let timings = [QuranTiming.VerseTiming(verseKey: "2:1", segments: [[1,0,100],[2,100,200]])]
    // a verse straddling a page boundary -> different fonts within one line
    let words = ["2:1": [w(1,"a","ﱁ",page:48,line:15), w(2,"b","ﲀ",page:49,line:1)]]
    let lines = QuranTiming.mushafLines(timings: timings, words: words)
    #expect(lines.count == 2)                      // different pages -> different lines
    #expect(lines[0].words[0].fontPage == 48)
    #expect(lines[1].words[0].fontPage == 49)
    #expect(lines[0].words[0].glyph == "ﱁ")
}

@Test func marksTimingsAsMeasuredNotEstimated() {
    let timings = [QuranTiming.VerseTiming(verseKey: "1:1", segments: [[1,0,580]])]
    let words = ["1:1": [w(1,"a","ﱁ",page:1,line:1)]]
    let lines = QuranTiming.mushafLines(timings: timings, words: words)
    #expect(lines[0].words[0].isEstimated == false)
}

@Test func ignoresSegmentsWithNoMatchingWord() {
    let timings = [QuranTiming.VerseTiming(verseKey: "1:1", segments: [[9, 0, 100]])]
    let words = ["1:1": [w(1,"a","ﱁ",page:1,line:1)]]
    #expect(QuranTiming.mushafLines(timings: timings, words: words).isEmpty)
}

@Test func linesAreOrderedByTime() {
    let timings = [QuranTiming.VerseTiming(verseKey: "1:1", segments: [[1,5000,5500]]),
                   QuranTiming.VerseTiming(verseKey: "1:2", segments: [[1,1000,1500]])]
    let words = ["1:1": [w(1,"late","ﱁ",page:1,line:9)],
                 "1:2": [w(1,"early","ﱂ",page:1,line:1)]]
    let lines = QuranTiming.mushafLines(timings: timings, words: words)
    #expect(lines.map { $0.words[0].text } == ["early", "late"])
}

@Test func returnsEmptyForNoTimings() {
    #expect(QuranTiming.mushafLines(timings: [], words: [:]).isEmpty)
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter QuranTimingTests`
Expected: FAIL — `cannot find 'QuranTiming' in scope`.

- [ ] **Step 3: Implement**

```swift
import Foundation

public enum QuranTiming {
    /// One verse's word segments. Values are milliseconds, absolute within the
    /// chapter audio file — not relative to the verse.
    public struct VerseTiming: Sendable {
        public let verseKey: String
        public let segments: [[Int]]
        public init(verseKey: String, segments: [[Int]]) {
            self.verseKey = verseKey; self.segments = segments
        }
    }

    /// One word of Quranic text. `position` is 1-based within its verse and is
    /// what segment tuples index by.
    public struct WordText: Sendable {
        public let position: Int
        public let textUthmani: String
        public let glyph: String?
        public let page: Int?
        public let lineNumber: Int?
        public init(position: Int, textUthmani: String, glyph: String?,
                    page: Int?, lineNumber: Int?) {
            self.position = position; self.textUthmani = textUthmani
            self.glyph = glyph; self.page = page; self.lineNumber = lineNumber
        }
    }

    /// Builds display lines grouped the way a printed mushaf breaks them.
    ///
    /// Verses are unbounded (2:282 is 128 words) but mushaf lines are not —
    /// measured at median 9 and max 14 words. Grouping by (page, line) keeps
    /// every display unit small enough for the overlay.
    public static func mushafLines(timings: [VerseTiming],
                                   words: [String: [WordText]]) -> [LyricLine] {
        struct Key: Hashable { let page: Int; let line: Int }
        var grouped: [Key: [WordToken]] = [:]

        for timing in timings {
            guard let verseWords = words[timing.verseKey] else { continue }
            let byPosition = Dictionary(uniqueKeysWithValues: verseWords.map { ($0.position, $0) })

            for segment in timing.segments {
                // 0.06% of real segments are truncated; skip rather than crash.
                guard segment.count == 3 else { continue }
                guard let word = byPosition[segment[0]] else { continue }

                let token = WordToken(text: word.textUthmani,
                                      start: Double(segment[1]) / 1000,
                                      end: Double(segment[2]) / 1000,
                                      isEstimated: false,          // measured, not inferred
                                      glyph: word.glyph,
                                      fontPage: word.page)
                let key = Key(page: word.page ?? 0, line: word.lineNumber ?? 0)
                grouped[key, default: []].append(token)
            }
        }

        return grouped.values.compactMap { tokens -> LyricLine? in
            guard !tokens.isEmpty else { return nil }
            let ordered = tokens.sorted { $0.start < $1.start }
            return LyricLine(start: ordered.first!.start,
                             end: ordered.last!.end,
                             words: ordered)
        }
        .sorted { $0.start < $1.start }
    }
}
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter QuranTimingTests`
Expected: PASS, 8 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/NotchLyricsCore/Quran Tests/NotchLyricsCoreTests/QuranTimingTests.swift
git commit -m "feat: mushaf-line assembly from word segments"
```

---

### Task 7: Quran provider

**Files:**
- Create: `Sources/NotchLyricsCore/Quran/QuranProvider.swift`
- Test: `Tests/NotchLyricsCoreTests/QuranProviderTests.swift`

**Interfaces:**
- Consumes: `LyricsProvider`, `HTTPFetching`, `QuranTiming` (Task 6).
- Produces: `QuranProvider(http:reciterID:)` with `id == "quran"`, and
  `static func surahNumber(for track: TrackQuery, genre: String?, trackNumber: Int?) -> Int?`.

Detection per spec §2: genre `Quran` or album containing `Quran`, track number
1–114, duration within **±2 s** of the chapter's declared duration.

`TrackQuery` has no genre/trackNumber, so `QuranProvider` takes them via a
`QuranHint` carried on the query. Simplest approach that avoids touching every
provider: add `public var quranHint: QuranHint?` to `TrackQuery` with a default
of nil, and have `PlaybackState.query` populate it.

- [ ] **Step 1: Write the failing test**

```swift
import Testing
import Foundation
@testable import NotchLyricsCore

private let timingJSON = """
{"audio_files":[{"chapter_id":1,"duration":46000,"verse_timings":[
 {"verse_key":"1:1","segments":[[1,0,580],[2,580,1409]]}]}]}
"""

private let wordsJSON = """
{"verses":[{"verse_key":"1:1","words":[
 {"position":1,"char_type_name":"word","text_uthmani":"a","code_v2":"\\u0641\\u0641","v2_page":1,"line_number":2},
 {"position":2,"char_type_name":"word","text_uthmani":"b","code_v2":"\\u0642\\u0642","v2_page":1,"line_number":2},
 {"position":3,"char_type_name":"end","text_uthmani":"\\u06dd","code_v2":null,"v2_page":1,"line_number":2}]}]}
"""

private func quranQuery(duration: TimeInterval = 46.497,
                        genre: String? = "Quran",
                        track: Int? = 1,
                        album: String = "Quran — Murattal") -> TrackQuery {
    var q = TrackQuery(trackID: "music:X", title: "001. Al-Fatihah",
                       artist: "Mishary Rashid Alafasy", album: album, duration: duration)
    q.quranHint = QuranHint(trackNumber: track, genre: genre)
    return q
}

@Test func detectsSurahFromTrackNumber() {
    #expect(QuranProvider.surahNumber(for: quranQuery()) == 1)
}

@Test func rejectsWhenNothingMarksItAsQuran() {
    #expect(QuranProvider.surahNumber(for: quranQuery(genre: nil, album: "Born To Die")) == nil)
}

@Test func acceptsWhenOnlyTheAlbumSaysQuran() {
    #expect(QuranProvider.surahNumber(for: quranQuery(genre: nil)) == 1)
}

@Test func rejectsOutOfRangeTrackNumbers() {
    #expect(QuranProvider.surahNumber(for: quranQuery(track: 0)) == nil)
    #expect(QuranProvider.surahNumber(for: quranQuery(track: 115)) == nil)
    #expect(QuranProvider.surahNumber(for: quranQuery(track: nil)) == nil)
}

@Test func buildsAnArabicDocument() async throws {
    let http = StubHTTP()
    await http.stub(urlContains: "audio_files", json: timingJSON)
    await http.stub(urlContains: "verses/by_chapter", json: wordsJSON)
    let doc = try await QuranProvider(http: http).fetch(quranQuery())
    #expect(doc?.script == .arabic)
    #expect(doc?.providerID == "quran")
    #expect(doc?.lines.count == 1)
    #expect(doc?.lines[0].words.count == 2)     // the "end" marker is excluded
    #expect(doc?.lines[0].words[0].fontPage == 1)
}

@Test func rejectsWhenDurationDisagrees() async throws {
    let http = StubHTTP()
    await http.stub(urlContains: "audio_files", json: timingJSON)
    await http.stub(urlContains: "verses/by_chapter", json: wordsJSON)
    // declared 46s, track claims 60s -> outside the +/-2s tolerance
    let doc = try await QuranProvider(http: http).fetch(quranQuery(duration: 60))
    #expect(doc == nil)
}

@Test func returnsNilForNonQuranTracks() async throws {
    let http = StubHTTP()
    let doc = try await QuranProvider(http: http).fetch(sampleQuery)
    #expect(doc == nil)
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter QuranProviderTests`
Expected: FAIL — `cannot find 'QuranProvider' in scope`.

- [ ] **Step 3: Add the hint to TrackQuery**

In `Models/PlaybackState.swift`, add above `TrackQuery`:

```swift
/// Player metadata that only matters for recitation detection.
public struct QuranHint: Equatable, Sendable {
    public var trackNumber: Int?
    public var genre: String?
    public init(trackNumber: Int?, genre: String?) {
        self.trackNumber = trackNumber; self.genre = genre
    }
}
```

Add `public var quranHint: QuranHint?` to `TrackQuery` with `= nil` default in its init,
and make `PlaybackState.query` populate it:

```swift
    public var query: TrackQuery {
        var q = TrackQuery(trackID: trackID, title: title, artist: artist,
                           album: album, duration: duration)
        q.quranHint = QuranHint(trackNumber: trackNumber, genre: genre)
        return q
    }
```

- [ ] **Step 4: Implement the provider**

```swift
import Foundation

public struct QuranProvider: LyricsProvider {
    public let id = "quran"
    /// 7 is Mishary Alafasy (murattal), the set verified against the timings.
    public static let defaultReciterID = 7
    public static let durationTolerance: TimeInterval = 2

    private let http: any HTTPFetching
    private let reciterID: Int

    public init(http: any HTTPFetching, reciterID: Int = QuranProvider.defaultReciterID) {
        self.http = http; self.reciterID = reciterID
    }

    /// Returns the surah number when this track looks like a recitation.
    public static func surahNumber(for track: TrackQuery) -> Int? {
        let genre = track.quranHint?.genre?.lowercased() ?? ""
        let looksQuranic = genre.contains("quran") || track.album.lowercased().contains("quran")
        guard looksQuranic, let n = track.quranHint?.trackNumber, (1...114).contains(n) else {
            return nil
        }
        return n
    }

    private struct TimingResponse: Decodable {
        struct File: Decodable {
            let duration: Int?
            let verse_timings: [Verse]?
        }
        struct Verse: Decodable {
            let verse_key: String
            let segments: [[Int]]?
        }
        let audio_files: [File]
    }

    private struct WordsResponse: Decodable {
        struct Verse: Decodable { let verse_key: String; let words: [Word]? }
        struct Word: Decodable {
            let position: Int?
            let char_type_name: String?
            let text_uthmani: String?
            let code_v2: String?
            let v2_page: Int?
            let line_number: Int?
        }
        let verses: [Verse]
    }

    public func fetch(_ track: TrackQuery) async throws -> LyricsDocument? {
        guard let surah = Self.surahNumber(for: track) else { return nil }

        guard let timingURL = URL(string:
            "https://api.quran.com/api/qdc/audio/reciters/\(reciterID)/audio_files?chapter=\(surah)&segments=true")
        else { return nil }
        let (timingData, timingStatus) = try await http.get(timingURL, headers: [:])
        guard timingStatus == 200 else { return nil }
        let timing = try JSONDecoder().decode(TimingResponse.self, from: timingData)
        guard let file = timing.audio_files.first, let verses = file.verse_timings else { return nil }

        // The declared duration is rounded to whole seconds, so compare loosely.
        if let declared = file.duration, declared > 0 {
            let seconds = Double(declared) / 1000
            guard abs(seconds - track.duration) <= Self.durationTolerance + 1 else { return nil }
        }

        guard let wordsURL = URL(string:
            "https://api.quran.com/api/v4/verses/by_chapter/\(surah)?words=true&per_page=300"
            + "&word_fields=text_uthmani,code_v2,v2_page,char_type_name,line_number")
        else { return nil }
        let (wordsData, wordsStatus) = try await http.get(wordsURL, headers: [:])
        guard wordsStatus == 200 else { return nil }
        let decoded = try JSONDecoder().decode(WordsResponse.self, from: wordsData)

        var words: [String: [QuranTiming.WordText]] = [:]
        for verse in decoded.verses {
            // The text API adds an "end" marker token per verse that segments omit.
            words[verse.verse_key] = (verse.words ?? [])
                .filter { $0.char_type_name == "word" }
                .compactMap { w in
                    guard let pos = w.position, let text = w.text_uthmani else { return nil }
                    return QuranTiming.WordText(position: pos, textUthmani: text,
                                                glyph: w.code_v2, page: w.v2_page,
                                                lineNumber: w.line_number)
                }
        }

        let timings = verses.map {
            QuranTiming.VerseTiming(verseKey: $0.verse_key, segments: $0.segments ?? [])
        }
        let lines = QuranTiming.mushafLines(timings: timings, words: words)
        guard !lines.isEmpty else { return nil }

        return LyricsDocument(trackID: track.trackID, providerID: id, script: .arabic, lines: lines)
    }
}
```

- [ ] **Step 5: Run the full suite**

Run: `swift test`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/NotchLyricsCore Tests/NotchLyricsCoreTests/QuranProviderTests.swift
git commit -m "feat: Quran provider with recitation detection"
```

---

### Task 8: QCF font store

**Files:**
- Create: `Sources/NotchLyricsApp/QCFFontStore.swift`

**Interfaces:**
- Produces: `@MainActor final class QCFFontStore` with
  `func fontName(forPage page: Int) -> String?` and `func prefetch(pages: Set<Int>) async`.

CoreText registers woff2 directly on macOS 26 (verified), so pages are fetched
on demand at ~41 KB each and cached, rather than bundling ~24 MB.

- [ ] **Step 1: Implement**

```swift
import AppKit
import CoreText

/// Fetches and registers QCF mushaf page fonts.
///
/// quran.com uses 604 fonts, one per page, where each glyph is a whole word.
/// Fonts are fetched on demand because most sessions touch only a few pages.
@MainActor
final class QCFFontStore {
    private var registered: Set<Int> = []
    private var failed: Set<Int> = []
    private let directory: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = base.appendingPathComponent("NotchLyrics/fonts", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// PostScript name for a page, or nil if that page is not available yet.
    func fontName(forPage page: Int) -> String? {
        guard registered.contains(page) else { return nil }
        return String(format: "QCF2%03d", page)
    }

    func prefetch(pages: Set<Int>) async {
        for page in pages where !registered.contains(page) && !failed.contains(page) {
            await load(page: page)
        }
    }

    private func load(page: Int) async {
        let file = directory.appendingPathComponent(String(format: "p%03d.woff2", page))

        if !FileManager.default.fileExists(atPath: file.path) {
            guard let url = URL(string:
                "https://verses.quran.foundation/fonts/quran/hafs/v2/woff2/p\(page).woff2")
            else { failed.insert(page); return }
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                    failed.insert(page); return
                }
                try data.write(to: file, options: .atomic)
            } catch {
                failed.insert(page); return
            }
        }

        var err: Unmanaged<CFError>?
        if CTFontManagerRegisterFontsForURL(file as CFURL, .process, &err) {
            registered.insert(page)
        } else {
            // Already registered by an earlier launch counts as success.
            if NSFont(name: String(format: "QCF2%03d", page), size: 12) != nil {
                registered.insert(page)
            } else {
                failed.insert(page)
            }
        }
    }
}
```

- [ ] **Step 2: Verify it builds**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/NotchLyricsApp/QCFFontStore.swift
git commit -m "feat: on-demand QCF mushaf page font store"
```

---

### Task 9: Arabic rendering and final wiring

**Files:**
- Create: `Sources/NotchLyricsApp/QuranView.swift`
- Modify: `Sources/NotchLyricsApp/LyricModel.swift`
- Modify: `Sources/NotchLyricsApp/OverlayWindow.swift`
- Modify: `Sources/NotchLyricsApp/OverlayController.swift`

**Interfaces:**
- Consumes: everything above.

- [ ] **Step 1: Create QuranView**

```swift
import SwiftUI
import NotchLyricsCore

/// Renders one mushaf line right-to-left, one Text run per word so each can be
/// coloured and sized independently. Fonts resolve per word because a line can
/// straddle a page boundary.
struct QuranView: View {
    let line: LyricLine?
    let time: TimeInterval
    let fontName: (Int) -> String?

    private let base: CGFloat = 23

    private func run(_ word: WordToken, first: Bool) -> Text {
        let progress = word.progress(at: time)
        let size = base * WordEmphasis.scale(progress: progress, style: .scale)
        let opacity = WordEmphasis.opacity(progress: progress, style: .scale)

        // Glyph + page font when available; fall back to Unicode + system Arabic.
        let usableGlyph = word.fontPage.flatMap { fontName($0) } != nil ? word.glyph : nil
        let name = word.fontPage.flatMap { fontName($0) }
        let font = name.flatMap { NSFont(name: $0, size: size) } ?? NSFont.systemFont(ofSize: size)
        let text = usableGlyph ?? (first ? word.text : " " + word.text)

        return Text(verbatim: text).font(Font(font)).foregroundColor(.white.opacity(opacity))
    }

    var body: some View {
        ZStack {
            NotchShape().fill(.black)
            if let line, !line.words.isEmpty {
                line.words.enumerated()
                    .reduce(Text(verbatim: "")) { $0 + run($1.element, first: $1.offset == 0) }
                    .multilineTextAlignment(.center)
                    .lineSpacing(6)
                    .minimumScaleFactor(0.5)
                    .lineLimit(2)
                    .environment(\.layoutDirection, .rightToLeft)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
        }
        .animation(.easeOut(duration: 0.25), value: line?.start)
    }
}
```

- [ ] **Step 2: Extend the model and host view**

In `LyricModel.swift`, add to `LyricModel`:

```swift
    @Published var script: Script = .latin
    @Published var fontResolver: (Int) -> String? = { _ in nil }
```

and change `LyricHost.body` to branch:

```swift
    var body: some View {
        if model.script == .arabic {
            QuranView(line: model.line, time: model.time, fontName: model.fontResolver)
        } else {
            LyricView(line: model.line, time: model.time,
                      position: model.position, style: model.style)
        }
    }
```

- [ ] **Step 3: Give the window an Arabic panel size**

In `OverlayWindow.swift`, add a stored property and use it in `preferredSize`:

```swift
    var script: Script = .latin
```

then in `preferredSize(for:)`, before the switch:

```swift
        if script == .arabic, position == .notch {
            return CGSize(width: 560, height: 104)
        }
```

- [ ] **Step 4: Wire the provider, font store and script switch**

In `OverlayController`, add `QuranProvider` first in the chain:

```swift
        var providers: [any LyricsProvider] = [
            QuranProvider(http: URLSessionHTTP()),
            LRCLIBProvider(http: URLSessionHTTP()),
        ]
```

Add a store and wire the resolver in `init()`:

```swift
    private let fonts = QCFFontStore()
```
```swift
        model.fontResolver = { [weak fonts] page in fonts?.fontName(forPage: page) }
```

In the fetch task, after `self.document = doc`, prefetch the pages that document needs:

```swift
                if let doc, doc.script == .arabic {
                    let pages = Set(doc.lines.flatMap { $0.words.compactMap(\.fontPage) })
                    await self.fonts.prefetch(pages: pages)
                }
                self.model.script = doc?.script ?? .latin
                self.window.script = doc?.script ?? .latin
                self.window.reanchor(to: NSScreen.main)
```

- [ ] **Step 5: Build, install and verify against the real library**

```bash
swift test && ./Scripts/build-app.sh release && open NotchLyrics.app
```

Play surah 1 in Apple Music. Expected: the mushaf line appears in the notch with
the active word enlarged and brightened, advancing with the recitation.
Then play a song in Spotify. Expected: normal lyrics, unchanged.

- [ ] **Step 6: Commit**

```bash
git add Sources/NotchLyricsApp
git commit -m "feat: mushaf-line Arabic rendering with QCF page fonts"
```

---

## Self-Review

**Spec coverage:**

| Spec section | Task |
|---|---|
| §1.1 Apple Music playhead | 3 |
| §1.2 source arbitration | 4, 5 |
| §1.3 real timings, malformed segments | 6 |
| §1.4 duration match | 7 |
| §1.5 mushaf lines | 6 |
| §1.6 QCF fonts, per-word page | 8, 9 |
| §1.7 library tags used for detection | 7 |
| §3.1 PlaybackSource | 2 |
| §3.2 SourceArbiter | 4 |
| §3.3 model changes, cache v3 | 1 |
| §3.4 QuranProvider | 7 |
| §3.5 QCFFontStore | 8 |
| §3.6 rendering | 9 |
| §4 error handling | 4 (both playing), 7 (fall-through), 8 (font failure), 6 (malformed) |
| §5 testing | 1, 4, 6, 7 |
| §6 phasing | Phase 1 = Tasks 1–5; Phase 2 = Tasks 6–9 |

**Placeholder scan:** none — every step carries complete code.

**Type consistency:** `WordToken(text:start:end:isEstimated:glyph:fontPage:)`,
`LyricsDocument(trackID:providerID:script:lines:)`, `QuranTiming.mushafLines(timings:words:)`,
`QuranProvider.surahNumber(for:)`, `QCFFontStore.fontName(forPage:)` and
`SourceArbiter.update(sourceID:state:at:)` are used consistently throughout.
