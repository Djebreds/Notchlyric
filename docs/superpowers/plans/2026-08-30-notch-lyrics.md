# NotchLyrics Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A macOS menu-bar app that shows time-synced Spotify lyrics in a click-through overlay anchored to the notch, a menu-bar ear, or the bottom-right corner.

**Architecture:** A pure-logic library (`NotchLyricsCore`) holds parsing, timing, geometry, and lyric providers with zero AppKit dependencies so all of it is unit-testable. A thin executable (`NotchLyricsApp`) supplies AppKit/SwiftUI: an `NSAppleScript` bridge to Spotify, a borderless always-on-top `NSPanel`, and a SwiftUI lyric view. Playback position is sampled at 1 Hz and interpolated to 60 Hz locally.

**Tech Stack:** Swift 6.3, SwiftPM, Swift Testing (`import Testing`), AppKit, SwiftUI. No third-party dependencies.

**Spec:** `docs/superpowers/specs/2026-08-30-notch-lyrics-design.md`

## Global Constraints

- Target platform: macOS 26.6 (Tahoe), Apple Silicon. Package `platforms: [.macOS(.v14)]` for the core library; the app target requires macOS 14+ APIs only.
- Swift tools version: `6.0`. Swift Testing, not XCTest.
- Zero third-party dependencies.
- `NotchLyricsCore` must not `import AppKit` or `import SwiftUI`. Geometry uses `CoreGraphics` types only. This is what keeps it testable.
- All network access goes through the `HTTPFetching` protocol so tests never touch the network.
- Spotify `duration` from AppleScript is **milliseconds**; `player position` is **seconds**. LRCLIB `duration` is **seconds**. Convert at the boundary, never mid-logic.
- Seek detection threshold: `0.25` seconds. Correction ramp window: `200` milliseconds.
- Duration match tolerance between a lyric candidate and the playing track: `±3` seconds.
- User-Agent for all outbound requests: `NotchLyrics/1.0 (personal use)`.
- Commit after every task.

---

## File Structure

```
NotchLyrics/
  Package.swift
  Sources/
    NotchLyricsCore/
      Models/PlaybackState.swift      PlaybackState, TrackQuery
      Models/Lyrics.swift             LyricsDocument, LyricLine, WordToken
      Models/Position.swift           Position enum
      Playback/PlaybackClock.swift    1 Hz samples -> 60 Hz estimate
      Lyrics/LRCParser.swift          LRC text -> [LyricLine]
      Lyrics/WordTimingEstimator.swift character-weighted word spans
      Lyrics/HTTPFetching.swift       network seam + URLSession impl
      Lyrics/LyricsProvider.swift     protocol + ProviderError
      Lyrics/LRCLIBProvider.swift     lrclib.net
      Lyrics/NetEaseProvider.swift    music.163.com
      Lyrics/LyricsCache.swift        disk cache, positive + negative
      Lyrics/LyricsService.swift      provider chain + matching
      Geometry/ScreenMetrics.swift    AppKit-free screen description
      Geometry/Anchor.swift           Position + metrics -> NSRect
    NotchLyricsApp/
      main.swift                      entry point
      AppDelegate.swift               wiring, lifecycle
      SpotifyBridge.swift             NSAppleScript + notifications
      OverlayWindow.swift             NSPanel subclass
      OverlayController.swift         window <-> state glue, re-anchoring
      LyricView.swift                 SwiftUI word-sweep renderer
      MenuBarController.swift         NSStatusItem menu
      Settings.swift                  UserDefaults-backed
  Tests/NotchLyricsCoreTests/
      LRCParserTests.swift
      WordTimingEstimatorTests.swift
      PlaybackClockTests.swift
      AnchorTests.swift
      LRCLIBProviderTests.swift
      NetEaseProviderTests.swift
      LyricsServiceTests.swift
      Support/StubHTTP.swift
  Scripts/build-app.sh
  README.md
```

---

### Task 1: Package scaffold and core models

**Files:**
- Create: `Package.swift`
- Create: `Sources/NotchLyricsCore/Models/Lyrics.swift`
- Create: `Sources/NotchLyricsCore/Models/PlaybackState.swift`
- Create: `Sources/NotchLyricsCore/Models/Position.swift`
- Test: `Tests/NotchLyricsCoreTests/ModelsTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `WordToken`, `LyricLine`, `LyricsDocument`, `TrackQuery`, `PlaybackState`, `Position`. Every later task depends on these exact names.

- [ ] **Step 1: Write `Package.swift`**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NotchLyrics",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "NotchLyricsCore", targets: ["NotchLyricsCore"]),
        .executable(name: "NotchLyricsApp", targets: ["NotchLyricsApp"]),
    ],
    targets: [
        .target(name: "NotchLyricsCore"),
        .executableTarget(name: "NotchLyricsApp", dependencies: ["NotchLyricsCore"]),
        .testTarget(name: "NotchLyricsCoreTests", dependencies: ["NotchLyricsCore"]),
    ]
)
```

- [ ] **Step 2: Write the models**

`Models/Lyrics.swift`:

```swift
import Foundation

public struct WordToken: Equatable, Sendable, Codable {
    public var text: String
    public var start: TimeInterval
    public var end: TimeInterval
    public var isEstimated: Bool

    public init(text: String, start: TimeInterval, end: TimeInterval, isEstimated: Bool) {
        self.text = text; self.start = start; self.end = end; self.isEstimated = isEstimated
    }

    /// 0...1 progress of this word at `time`.
    public func progress(at time: TimeInterval) -> Double {
        guard end > start else { return time >= start ? 1 : 0 }
        return min(1, max(0, (time - start) / (end - start)))
    }
}

public struct LyricLine: Equatable, Sendable, Codable {
    public var start: TimeInterval
    public var end: TimeInterval
    public var words: [WordToken]

    public init(start: TimeInterval, end: TimeInterval, words: [WordToken]) {
        self.start = start; self.end = end; self.words = words
    }

    public var text: String { words.map(\.text).joined(separator: " ") }
    public var isBlank: Bool { words.isEmpty || text.trimmingCharacters(in: .whitespaces).isEmpty }
}

public struct LyricsDocument: Equatable, Sendable, Codable {
    public var trackID: String
    public var providerID: String
    public var lines: [LyricLine]

    public init(trackID: String, providerID: String, lines: [LyricLine]) {
        self.trackID = trackID; self.providerID = providerID; self.lines = lines
    }

    public var isEmpty: Bool { lines.allSatisfy(\.isBlank) }

    /// Index of the line active at `time`, or nil before the first line.
    public func index(at time: TimeInterval) -> Int? {
        guard !lines.isEmpty, time >= lines[0].start else { return nil }
        var lo = 0, hi = lines.count - 1, found = 0
        while lo <= hi {
            let mid = (lo + hi) / 2
            if lines[mid].start <= time { found = mid; lo = mid + 1 } else { hi = mid - 1 }
        }
        return found
    }
}
```

`Models/PlaybackState.swift`:

```swift
import Foundation

public struct TrackQuery: Equatable, Sendable {
    public var trackID: String
    public var title: String
    public var artist: String
    public var album: String
    public var duration: TimeInterval   // seconds

    public init(trackID: String, title: String, artist: String, album: String, duration: TimeInterval) {
        self.trackID = trackID; self.title = title; self.artist = artist
        self.album = album; self.duration = duration
    }
}

public struct PlaybackState: Equatable, Sendable {
    public var trackID: String
    public var title: String
    public var artist: String
    public var album: String
    public var durationMs: Int          // Spotify reports milliseconds
    public var position: TimeInterval   // seconds
    public var isPlaying: Bool

    public init(trackID: String, title: String, artist: String, album: String,
                durationMs: Int, position: TimeInterval, isPlaying: Bool) {
        self.trackID = trackID; self.title = title; self.artist = artist; self.album = album
        self.durationMs = durationMs; self.position = position; self.isPlaying = isPlaying
    }

    public var duration: TimeInterval { Double(durationMs) / 1000 }

    public var query: TrackQuery {
        TrackQuery(trackID: trackID, title: title, artist: artist, album: album, duration: duration)
    }
}
```

`Models/Position.swift`:

```swift
public enum Position: String, CaseIterable, Sendable, Codable {
    case notch, earLeft, earRight, bottomRight

    public var displayName: String {
        switch self {
        case .notch: "Below the Notch"
        case .earLeft: "Menu Bar (Left)"
        case .earRight: "Menu Bar (Right)"
        case .bottomRight: "Bottom Right"
        }
    }
}
```

- [ ] **Step 3: Write the failing test**

`Tests/NotchLyricsCoreTests/ModelsTests.swift`:

```swift
import Testing
import Foundation
@testable import NotchLyricsCore

private func doc(_ starts: [TimeInterval]) -> LyricsDocument {
    let lines = starts.enumerated().map { i, s in
        LyricLine(start: s, end: i + 1 < starts.count ? starts[i + 1] : s + 3,
                  words: [WordToken(text: "l\(i)", start: s, end: s + 1, isEstimated: true)])
    }
    return LyricsDocument(trackID: "t", providerID: "p", lines: lines)
}

@Test func durationConvertsMillisecondsToSeconds() {
    let s = PlaybackState(trackID: "spotify:track:x", title: "T", artist: "A", album: "B",
                          durationMs: 265427, position: 83.7, isPlaying: true)
    #expect(abs(s.duration - 265.427) < 0.0001)
}

@Test func indexAtReturnsNilBeforeFirstLine() {
    #expect(doc([10, 20, 30]).index(at: 5) == nil)
}

@Test func indexAtFindsActiveLine() {
    let d = doc([10, 20, 30])
    #expect(d.index(at: 10) == 0)
    #expect(d.index(at: 19.9) == 0)
    #expect(d.index(at: 20) == 1)
    #expect(d.index(at: 999) == 2)
}

@Test func wordProgressClamps() {
    let w = WordToken(text: "hi", start: 4, end: 6, isEstimated: true)
    #expect(w.progress(at: 3) == 0)
    #expect(w.progress(at: 5) == 0.5)
    #expect(w.progress(at: 9) == 1)
}
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter ModelsTests`
Expected: PASS, 4 tests.

- [ ] **Step 5: Commit**

```bash
git add Package.swift Sources Tests
git commit -m "feat: package scaffold and core models"
```

---

### Task 2: LRC parser

**Files:**
- Create: `Sources/NotchLyricsCore/Lyrics/LRCParser.swift`
- Test: `Tests/NotchLyricsCoreTests/LRCParserTests.swift`

**Interfaces:**
- Consumes: `LyricLine`, `WordToken` (Task 1).
- Produces: `LRCParser.parse(_ text: String, trackDuration: TimeInterval) -> [LyricLine]`. Emits one `WordToken` per whitespace-separated word with `isEstimated: true` and zero-width spans; Task 3 fills the spans in.

Handles: `[mm:ss.xx]` and `[mm:ss.xxx]`, multiple timestamps on one line, `[offset:±ms]`, metadata tags (`ar` `ti` `al` `by` `length`), NetEase credit lines (`作词 :`, `作曲 :`), and enhanced `<mm:ss.xx>` word tags if ever present.

- [ ] **Step 1: Write the failing test**

```swift
import Testing
import Foundation
@testable import NotchLyricsCore

@Test func parsesBasicTimestamps() {
    let lrc = """
    [00:17.38] Kiss me hard before you go
    [00:21.61] Summertime sadness
    """
    let lines = LRCParser.parse(lrc, trackDuration: 265)
    #expect(lines.count == 2)
    #expect(abs(lines[0].start - 17.38) < 0.001)
    #expect(lines[0].text == "Kiss me hard before you go")
    #expect(abs(lines[0].end - 21.61) < 0.001)
}

@Test func parsesMillisecondPrecision() {
    let lines = LRCParser.parse("[00:17.320]Kiss me", trackDuration: 100)
    #expect(abs(lines[0].start - 17.32) < 0.001)
}

@Test func lastLineEndsAtTrackDuration() {
    let lines = LRCParser.parse("[00:10.00] only line", trackDuration: 42)
    #expect(lines[0].end == 42)
}

@Test func lastLineFallsBackWhenDurationUnknown() {
    let lines = LRCParser.parse("[00:10.00] only line", trackDuration: 0)
    #expect(lines[0].end == 14)   // start + 4s default
}

@Test func skipsMetadataTags() {
    let lrc = """
    [ar:Lana Del Rey]
    [ti:Summertime Sadness]
    [00:17.38] real line
    """
    let lines = LRCParser.parse(lrc, trackDuration: 100)
    #expect(lines.count == 1)
    #expect(lines[0].text == "real line")
}

@Test func appliesOffsetTag() {
    let lrc = """
    [offset:+500]
    [00:10.00] shifted
    """
    let lines = LRCParser.parse(lrc, trackDuration: 100)
    #expect(abs(lines[0].start - 9.5) < 0.001)   // +500ms offset plays 0.5s earlier
}

@Test func expandsMultipleTimestampsOnOneLine() {
    let lines = LRCParser.parse("[00:10.00][00:50.00] chorus", trackDuration: 100)
    #expect(lines.count == 2)
    #expect(lines[0].start == 10)
    #expect(lines[1].start == 50)
    #expect(lines.map(\.text) == ["chorus", "chorus"])
}

@Test func stripsNetEaseCreditLines() {
    let lrc = """
    [00:00.000] 作词 : Lana Del Rey
    [00:01.000] 作曲 : Rick Nowels
    [00:17.320]Kiss me hard
    """
    let lines = LRCParser.parse(lrc, trackDuration: 100)
    #expect(lines.count == 1)
    #expect(lines[0].text == "Kiss me hard")
}

@Test func keepsBlankLinesAsGaps() {
    let lrc = """
    [00:10.00] first
    [00:12.00]
    [00:20.00] second
    """
    let lines = LRCParser.parse(lrc, trackDuration: 100)
    #expect(lines.count == 3)
    #expect(lines[1].isBlank)
    #expect(lines[0].end == 12)
}

@Test func sortsOutOfOrderTimestamps() {
    let lines = LRCParser.parse("[00:50.00] later\n[00:10.00] earlier", trackDuration: 100)
    #expect(lines.map(\.text) == ["earlier", "later"])
}

@Test func ignoresMalformedLines() {
    let lines = LRCParser.parse("no timestamp here\n[bad] also bad\n[00:10.00] good", trackDuration: 100)
    #expect(lines.count == 1)
    #expect(lines[0].text == "good")
}

@Test func parsesEnhancedWordTags() {
    let lines = LRCParser.parse("[00:10.00] <00:10.00>Kiss <00:10.50>me <00:11.00>hard", trackDuration: 100)
    #expect(lines.count == 1)
    #expect(lines[0].words.map(\.text) == ["Kiss", "me", "hard"])
    #expect(lines[0].words[0].isEstimated == false)
    #expect(abs(lines[0].words[1].start - 10.5) < 0.001)
}

@Test func returnsEmptyForEmptyInput() {
    #expect(LRCParser.parse("", trackDuration: 100).isEmpty)
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter LRCParserTests`
Expected: FAIL — `cannot find 'LRCParser' in scope`.

- [ ] **Step 3: Implement**

```swift
import Foundation

public enum LRCParser {
    /// Fallback span for a final line when the track duration is unknown.
    static let trailingLineFallback: TimeInterval = 4

    private static let timeTag = /\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]/
    private static let wordTag = /<(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?>/
    private static let offsetTag = /\[offset:\s*([+-]?\d+)\s*\]/
    private static let metadataTag = /^\[[a-zA-Z#]+:.*\]$/
    private static let creditLine = /^(作词|作曲|编曲|制作人|出品|录音|混音)\s*[:：]/

    public static func parse(_ text: String, trackDuration: TimeInterval) -> [LyricLine] {
        var offset: TimeInterval = 0
        if let m = text.firstMatch(of: offsetTag), let ms = Int(m.1) {
            // Positive offset means lyrics should appear earlier.
            offset = -Double(ms) / 1000
        }

        var collected: [(start: TimeInterval, words: [WordToken], estimated: Bool)] = []

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }

            let stamps = line.matches(of: timeTag)
            guard !stamps.isEmpty, stamps[0].range.lowerBound == line.startIndex else {
                continue    // no leading timestamp -> not a lyric line
            }

            // Content begins after the final leading timestamp.
            var contentStart = line.startIndex
            var times: [TimeInterval] = []
            for s in stamps {
                guard s.range.lowerBound == contentStart else { break }
                times.append(seconds(minutes: s.1, seconds: s.2, fraction: s.3))
                contentStart = s.range.upperBound
            }
            guard !times.isEmpty else { continue }

            let content = String(line[contentStart...]).trimmingCharacters(in: .whitespaces)
            if content.firstMatch(of: metadataTag) != nil { continue }
            if content.firstMatch(of: creditLine) != nil { continue }

            let (words, estimated) = parseWords(content)
            for t in times {
                collected.append((start: max(0, t + offset), words: words, estimated: estimated))
            }
        }

        guard !collected.isEmpty else { return [] }
        collected.sort { $0.start < $1.start }

        return collected.enumerated().map { i, item in
            let end: TimeInterval
            if i + 1 < collected.count {
                end = collected[i + 1].start
            } else if trackDuration > item.start {
                end = trackDuration
            } else {
                end = item.start + trailingLineFallback
            }
            var words = item.words
            if item.estimated {
                // Spans filled in by WordTimingEstimator (Task 3).
                words = words.map {
                    var w = $0; w.start = item.start; w.end = end; return w
                }
            }
            return LyricLine(start: item.start, end: end, words: words)
        }
    }

    /// Returns tokens and whether their timings still need estimating.
    private static func parseWords(_ content: String) -> ([WordToken], Bool) {
        let tags = content.matches(of: wordTag)
        if tags.isEmpty {
            let words = content.split(separator: " ").map {
                WordToken(text: String($0), start: 0, end: 0, isEstimated: true)
            }
            return (words, true)
        }

        var tokens: [WordToken] = []
        for (i, tag) in tags.enumerated() {
            let start = seconds(minutes: tag.1, seconds: tag.2, fraction: tag.3)
            let textEnd = i + 1 < tags.count ? tags[i + 1].range.lowerBound : content.endIndex
            let word = String(content[tag.range.upperBound..<textEnd])
                .trimmingCharacters(in: .whitespaces)
            guard !word.isEmpty else { continue }
            tokens.append(WordToken(text: word, start: start, end: start, isEstimated: false))
        }
        for i in tokens.indices {
            tokens[i].end = i + 1 < tokens.count ? tokens[i + 1].start : tokens[i].start + 0.5
        }
        return (tokens, false)
    }

    private static func seconds(minutes: Substring, seconds sec: Substring,
                                fraction: Substring?) -> TimeInterval {
        let m = Double(minutes) ?? 0
        let s = Double(sec) ?? 0
        var f: Double = 0
        if let fraction, let raw = Double(fraction) {
            f = raw / pow(10, Double(fraction.count))
        }
        return m * 60 + s + f
    }
}
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter LRCParserTests`
Expected: PASS, 13 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/NotchLyricsCore/Lyrics/LRCParser.swift Tests/NotchLyricsCoreTests/LRCParserTests.swift
git commit -m "feat: LRC parser with offset, multi-timestamp and enhanced tag support"
```

---

### Task 3: Word timing estimator

**Files:**
- Create: `Sources/NotchLyricsCore/Lyrics/WordTimingEstimator.swift`
- Test: `Tests/NotchLyricsCoreTests/WordTimingEstimatorTests.swift`

**Interfaces:**
- Consumes: `LyricLine`, `WordToken` (Task 1).
- Produces: `WordTimingEstimator.apply(to lines: [LyricLine]) -> [LyricLine]`. Distributes each line's span across its words weighted by `text.count + 1`. Lines whose tokens have `isEstimated == false` pass through untouched.

- [ ] **Step 1: Write the failing test**

```swift
import Testing
import Foundation
@testable import NotchLyricsCore

private func estimatedLine(_ text: String, _ start: TimeInterval, _ end: TimeInterval) -> LyricLine {
    LyricLine(start: start, end: end,
              words: text.split(separator: " ").map {
                  WordToken(text: String($0), start: start, end: end, isEstimated: true)
              })
}

@Test func distributesSpanAcrossWords() {
    let out = WordTimingEstimator.apply(to: [estimatedLine("aa bb cc", 0, 9)])
    let w = out[0].words
    #expect(w.count == 3)
    #expect(w[0].start == 0)
    #expect(abs(w[2].end - 9) < 0.0001)
    // equal weights -> equal thirds
    #expect(abs(w[0].end - 3) < 0.0001)
    #expect(abs(w[1].start - 3) < 0.0001)
}

@Test func longerWordsGetMoreTime() {
    let out = WordTimingEstimator.apply(to: [estimatedLine("a mississippi", 0, 10)])
    let w = out[0].words
    let short = w[0].end - w[0].start
    let long = w[1].end - w[1].start
    #expect(long > short * 3)
}

@Test func wordsAreContiguousAndOrdered() {
    let out = WordTimingEstimator.apply(to: [estimatedLine("one two three four", 5, 13)])
    let w = out[0].words
    for i in 0..<(w.count - 1) {
        #expect(abs(w[i].end - w[i + 1].start) < 0.0001)
        #expect(w[i].start < w[i].end)
    }
    #expect(w.first!.start == 5)
    #expect(abs(w.last!.end - 13) < 0.0001)
}

@Test func preservesRealWordTimings() {
    let real = LyricLine(start: 0, end: 10, words: [
        WordToken(text: "a", start: 0, end: 1, isEstimated: false),
        WordToken(text: "b", start: 1, end: 2, isEstimated: false),
    ])
    let out = WordTimingEstimator.apply(to: [real])
    #expect(out[0].words == real.words)
}

@Test func handlesBlankLine() {
    let blank = LyricLine(start: 0, end: 5, words: [])
    #expect(WordTimingEstimator.apply(to: [blank])[0].words.isEmpty)
}

@Test func handlesZeroLengthSpan() {
    let out = WordTimingEstimator.apply(to: [estimatedLine("a b", 7, 7)])
    #expect(out[0].words.allSatisfy { $0.start == 7 && $0.end == 7 })
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter WordTimingEstimatorTests`
Expected: FAIL — `cannot find 'WordTimingEstimator' in scope`.

- [ ] **Step 3: Implement**

```swift
import Foundation

public enum WordTimingEstimator {
    /// Fills in per-word spans for lines whose tokens are marked estimated.
    ///
    /// Each word's share of the line is proportional to `text.count + 1`. The
    /// +1 keeps single-character words from collapsing to a near-zero span.
    public static func apply(to lines: [LyricLine]) -> [LyricLine] {
        lines.map { line in
            guard !line.words.isEmpty, line.words.contains(where: \.isEstimated) else { return line }

            let span = max(0, line.end - line.start)
            let weights = line.words.map { Double($0.text.count + 1) }
            let total = weights.reduce(0, +)
            guard total > 0, span > 0 else {
                var l = line
                l.words = l.words.map { var w = $0; w.start = line.start; w.end = line.start; return w }
                return l
            }

            var out = line.words
            var cursor = line.start
            for i in out.indices {
                let share = span * (weights[i] / total)
                out[i].start = cursor
                cursor += share
                out[i].end = cursor
            }
            out[out.count - 1].end = line.end   // absorb float drift
            var l = line
            l.words = out
            return l
        }
    }
}
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter WordTimingEstimatorTests`
Expected: PASS, 6 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/NotchLyricsCore/Lyrics/WordTimingEstimator.swift Tests/NotchLyricsCoreTests/WordTimingEstimatorTests.swift
git commit -m "feat: character-weighted word timing estimator"
```

---

### Task 4: Playback clock

**Files:**
- Create: `Sources/NotchLyricsCore/Playback/PlaybackClock.swift`
- Test: `Tests/NotchLyricsCoreTests/PlaybackClockTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `PlaybackClock` with `mutating func ingest(position:at:isPlaying:)`, `func position(at:) -> TimeInterval`, `var didSeek: Bool`. Instants are `ContinuousClock.Instant` passed in by the caller, so tests never sleep.

Rationale (spec §3.2): AppleScript costs ~54 ms warm, so we sample at 1 Hz and interpolate. Corrections under `0.25 s` ease in over `200 ms`; anything larger is a seek and snaps.

- [ ] **Step 1: Write the failing test**

```swift
import Testing
import Foundation
@testable import NotchLyricsCore

private let t0 = ContinuousClock.now

@Test func interpolatesWhilePlaying() {
    var c = PlaybackClock()
    c.ingest(position: 10, at: t0, isPlaying: true)
    #expect(abs(c.position(at: t0.advanced(by: .milliseconds(500))) - 10.5) < 0.01)
    #expect(abs(c.position(at: t0.advanced(by: .seconds(2))) - 12) < 0.01)
}

@Test func freezesWhilePaused() {
    var c = PlaybackClock()
    c.ingest(position: 10, at: t0, isPlaying: false)
    #expect(abs(c.position(at: t0.advanced(by: .seconds(5))) - 10) < 0.01)
}

@Test func smallDriftEasesInRatherThanJumping() {
    var c = PlaybackClock()
    c.ingest(position: 10, at: t0, isPlaying: true)
    let t1 = t0.advanced(by: .seconds(1))
    c.ingest(position: 11.1, at: t1, isPlaying: true)   // 0.1s ahead of prediction
    #expect(c.didSeek == false)
    // immediately after: correction not yet applied
    #expect(abs(c.position(at: t1) - 11.0) < 0.01)
    // halfway through the 200ms ramp
    #expect(abs(c.position(at: t1.advanced(by: .milliseconds(100))) - 11.15) < 0.01)
    // fully corrected
    #expect(abs(c.position(at: t1.advanced(by: .milliseconds(200))) - 11.3) < 0.01)
}

@Test func largeJumpIsTreatedAsSeekAndSnaps() {
    var c = PlaybackClock()
    c.ingest(position: 10, at: t0, isPlaying: true)
    let t1 = t0.advanced(by: .seconds(1))
    c.ingest(position: 90, at: t1, isPlaying: true)
    #expect(c.didSeek == true)
    #expect(abs(c.position(at: t1) - 90) < 0.01)
}

@Test func backwardSeekSnaps() {
    var c = PlaybackClock()
    c.ingest(position: 100, at: t0, isPlaying: true)
    let t1 = t0.advanced(by: .seconds(1))
    c.ingest(position: 5, at: t1, isPlaying: true)
    #expect(c.didSeek == true)
    #expect(abs(c.position(at: t1) - 5) < 0.01)
}

@Test func seekThresholdBoundary() {
    var c = PlaybackClock()
    c.ingest(position: 10, at: t0, isPlaying: true)
    let t1 = t0.advanced(by: .seconds(1))
    c.ingest(position: 11.3, at: t1, isPlaying: true)   // 0.3 > 0.25 threshold
    #expect(c.didSeek == true)
}

@Test func resumingAfterPauseRebases() {
    var c = PlaybackClock()
    c.ingest(position: 10, at: t0, isPlaying: false)
    let t1 = t0.advanced(by: .seconds(30))
    c.ingest(position: 10, at: t1, isPlaying: true)
    #expect(c.didSeek == false)
    #expect(abs(c.position(at: t1.advanced(by: .seconds(1))) - 11) < 0.01)
}

@Test func neverReturnsNegative() {
    var c = PlaybackClock()
    c.ingest(position: 0, at: t0, isPlaying: true)
    #expect(c.position(at: t0) >= 0)
}

@Test func positionIsZeroBeforeAnySample() {
    let c = PlaybackClock()
    #expect(c.position(at: t0) == 0)
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter PlaybackClockTests`
Expected: FAIL — `cannot find 'PlaybackClock' in scope`.

- [ ] **Step 3: Implement**

```swift
import Foundation

/// Turns coarse 1 Hz position samples into a smooth continuous estimate.
///
/// Uses `ContinuousClock` so sleep/wake cannot corrupt the timeline. All
/// instants are supplied by the caller, which keeps this pure and testable.
public struct PlaybackClock: Sendable {
    public static let seekThreshold: TimeInterval = 0.25
    public static let correctionWindow: TimeInterval = 0.2

    private var anchorPosition: TimeInterval = 0
    private var anchorInstant: ContinuousClock.Instant?
    private var isPlaying = false

    private var pendingDelta: TimeInterval = 0
    private var correctionStart: ContinuousClock.Instant?

    public private(set) var didSeek = false

    public init() {}

    public var hasSample: Bool { anchorInstant != nil }

    public mutating func ingest(position: TimeInterval,
                                at instant: ContinuousClock.Instant,
                                isPlaying playing: Bool) {
        didSeek = false

        guard anchorInstant != nil else {
            anchorPosition = max(0, position)
            anchorInstant = instant
            isPlaying = playing
            return
        }

        // Fold everything applied so far into a fresh anchor.
        let current = position(at: instant)
        anchorPosition = current
        anchorInstant = instant
        pendingDelta = 0
        correctionStart = nil

        let wasPlaying = isPlaying
        isPlaying = playing

        let delta = position - current
        if abs(delta) >= Self.seekThreshold {
            anchorPosition = max(0, position)
            // A pause/resume boundary explains the gap; don't call it a seek.
            didSeek = wasPlaying == playing
        } else if delta != 0 {
            pendingDelta = delta
            correctionStart = instant
        }
    }

    public func position(at instant: ContinuousClock.Instant) -> TimeInterval {
        guard let anchorInstant else { return 0 }

        var p = anchorPosition
        if isPlaying {
            p += Self.seconds(from: anchorInstant.duration(to: instant))
        }
        if let correctionStart, pendingDelta != 0 {
            let elapsed = Self.seconds(from: correctionStart.duration(to: instant))
            let factor = min(1, max(0, elapsed / Self.correctionWindow))
            p += pendingDelta * factor
        }
        return max(0, p)
    }

    private static func seconds(from d: Duration) -> TimeInterval {
        let c = d.components
        return TimeInterval(c.seconds) + TimeInterval(c.attoseconds) * 1e-18
    }
}
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter PlaybackClockTests`
Expected: PASS, 9 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/NotchLyricsCore/Playback/PlaybackClock.swift Tests/NotchLyricsCoreTests/PlaybackClockTests.swift
git commit -m "feat: playback clock with drift correction and seek detection"
```

---

### Task 5: Screen metrics and anchor geometry

**Files:**
- Create: `Sources/NotchLyricsCore/Geometry/ScreenMetrics.swift`
- Create: `Sources/NotchLyricsCore/Geometry/Anchor.swift`
- Test: `Tests/NotchLyricsCoreTests/AnchorTests.swift`

**Interfaces:**
- Consumes: `Position` (Task 1).
- Produces: `ScreenMetrics` (init with `frame`, `visibleFrame`, `safeAreaTop`, `auxTopLeft`, `auxTopRight`; computed `hasNotch`, `notchRect`) and `Anchor.frame(for:in:size:) -> CGRect`. Task 10 constructs `ScreenMetrics` from an `NSScreen`.

Tests use the values measured on the target machine (spec §1.1): frame `1800×1169`, `safeAreaTop 38`, aux left `(0,1131,790,38)`, aux right `(1010,1131,790,38)`.

- [ ] **Step 1: Write the failing test**

```swift
import Testing
import CoreGraphics
@testable import NotchLyricsCore

/// Measured on the target MacBook (spec §1.1).
private let notched = ScreenMetrics(
    frame: CGRect(x: 0, y: 0, width: 1800, height: 1169),
    visibleFrame: CGRect(x: 0, y: 0, width: 1800, height: 1130),
    safeAreaTop: 38,
    auxTopLeft: CGRect(x: 0, y: 1131, width: 790, height: 38),
    auxTopRight: CGRect(x: 1010, y: 1131, width: 790, height: 38)
)

private let external = ScreenMetrics(
    frame: CGRect(x: 1800, y: 0, width: 2560, height: 1440),
    visibleFrame: CGRect(x: 1800, y: 0, width: 2560, height: 1415),
    safeAreaTop: 0, auxTopLeft: nil, auxTopRight: nil
)

private let size = CGSize(width: 420, height: 84)

@Test func detectsNotch() {
    #expect(notched.hasNotch)
    #expect(external.hasNotch == false)
}

@Test func computesNotchRect() {
    let n = notched.notchRect!
    #expect(n.width == 220)
    #expect(n.height == 38)
    #expect(n.midX == 900)
}

@Test func notchPanelIsCenteredAndFlushWithScreenTop() {
    let f = Anchor.frame(for: .notch, in: notched, size: size)
    #expect(f.midX == 900)
    #expect(f.maxY == 1169)         // flush with physical top, over the menu bar
    #expect(f.height == 84)
}

@Test func notchPanelIsAtLeastAsWideAsNotchPlusMargin() {
    let narrow = CGSize(width: 100, height: 84)
    let f = Anchor.frame(for: .notch, in: notched, size: narrow)
    #expect(f.width >= 220)
}

@Test func notchFallsBackBelowMenuBarWithoutNotch() {
    let f = Anchor.frame(for: .notch, in: external, size: size)
    #expect(f.midX == external.frame.midX)
    #expect(f.maxY == external.visibleFrame.maxY)   // below menu bar, not over it
}

@Test func earLeftStaysInsideLeftAuxiliaryArea() {
    let f = Anchor.frame(for: .earLeft, in: notched, size: size)
    #expect(f.minX >= 0)
    #expect(f.maxX <= 790)          // never crosses into the cutout
    #expect(f.height == 38)
}

@Test func earRightStaysInsideRightAuxiliaryArea() {
    let f = Anchor.frame(for: .earRight, in: notched, size: size)
    #expect(f.minX >= 1010)
    #expect(f.maxX <= 1800)
    #expect(f.height == 38)
}

@Test func earClampsOversizedPanel() {
    let huge = CGSize(width: 5000, height: 38)
    let f = Anchor.frame(for: .earLeft, in: notched, size: huge)
    #expect(f.width <= 790)
}

@Test func earFallsBackWithoutNotch() {
    let f = Anchor.frame(for: .earRight, in: external, size: size)
    #expect(f.maxY <= external.visibleFrame.maxY)
    #expect(f.maxX <= external.frame.maxX)
}

@Test func bottomRightRespectsVisibleFrame() {
    let f = Anchor.frame(for: .bottomRight, in: notched, size: size)
    #expect(f.maxX <= 1800)
    #expect(f.minY >= 0)
    #expect(f.maxY <= 1130)         // above the Dock
}

@Test func bottomRightOnExternalDisplayUsesItsOrigin() {
    let f = Anchor.frame(for: .bottomRight, in: external, size: size)
    #expect(f.minX >= 1800)
    #expect(f.maxX <= 4360)
}

@Test func everyPositionStaysWithinScreenBounds() {
    for p in Position.allCases {
        for m in [notched, external] {
            let f = Anchor.frame(for: p, in: m, size: size)
            #expect(m.frame.contains(f) || m.frame.intersects(f))
            #expect(f.width > 0 && f.height > 0)
        }
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter AnchorTests`
Expected: FAIL — `cannot find 'ScreenMetrics' in scope`.

- [ ] **Step 3: Implement**

`ScreenMetrics.swift`:

```swift
import CoreGraphics

/// AppKit-free description of a display, so geometry stays unit-testable.
public struct ScreenMetrics: Equatable, Sendable {
    public var frame: CGRect
    public var visibleFrame: CGRect
    public var safeAreaTop: CGFloat
    public var auxTopLeft: CGRect?
    public var auxTopRight: CGRect?

    public init(frame: CGRect, visibleFrame: CGRect, safeAreaTop: CGFloat,
                auxTopLeft: CGRect?, auxTopRight: CGRect?) {
        self.frame = frame; self.visibleFrame = visibleFrame
        self.safeAreaTop = safeAreaTop
        self.auxTopLeft = auxTopLeft; self.auxTopRight = auxTopRight
    }

    public var hasNotch: Bool {
        safeAreaTop > 0 && auxTopLeft != nil && auxTopRight != nil
    }

    /// The camera cutout — a region with no pixels behind it (spec §1.1).
    public var notchRect: CGRect? {
        guard let l = auxTopLeft, let r = auxTopRight, r.minX > l.maxX else { return nil }
        return CGRect(x: l.maxX, y: l.minY, width: r.minX - l.maxX, height: safeAreaTop)
    }
}
```

`Anchor.swift`:

```swift
import CoreGraphics

public enum Anchor {
    public static let edgeInset: CGFloat = 16
    public static let earInset: CGFloat = 8

    public static func frame(for position: Position,
                             in metrics: ScreenMetrics,
                             size: CGSize) -> CGRect {
        switch position {
        case .notch:       notchFrame(metrics, size)
        case .earLeft:     earFrame(metrics, size, left: true)
        case .earRight:    earFrame(metrics, size, left: false)
        case .bottomRight: bottomRightFrame(metrics, size)
        }
    }

    private static func notchFrame(_ m: ScreenMetrics, _ size: CGSize) -> CGRect {
        guard let notch = m.notchRect else {
            // No notch: a pill centred under the menu bar.
            let w = min(size.width, m.visibleFrame.width - 2 * edgeInset)
            return CGRect(x: m.frame.midX - w / 2,
                          y: m.visibleFrame.maxY - size.height,
                          width: w, height: size.height)
        }
        // Wide enough to visually swallow the cutout, then hang below it.
        let w = min(max(size.width, notch.width), m.frame.width - 2 * edgeInset)
        return CGRect(x: notch.midX - w / 2,
                      y: m.frame.maxY - size.height,
                      width: w, height: size.height)
    }

    private static func earFrame(_ m: ScreenMetrics, _ size: CGSize, left: Bool) -> CGRect {
        guard let aux = left ? m.auxTopLeft : m.auxTopRight, m.hasNotch else {
            let w = min(size.width, m.visibleFrame.width - 2 * edgeInset)
            let x = left ? m.frame.minX + edgeInset : m.frame.maxX - w - edgeInset
            return CGRect(x: x, y: m.visibleFrame.maxY - size.height, width: w, height: size.height)
        }
        let w = min(size.width, aux.width - 2 * earInset)
        // Left ear must dodge the Apple menu; right ear butts against the cutout.
        let x = left ? aux.maxX - w - earInset : aux.minX + earInset
        return CGRect(x: x, y: aux.minY, width: w, height: m.safeAreaTop)
    }

    private static func bottomRightFrame(_ m: ScreenMetrics, _ size: CGSize) -> CGRect {
        let w = min(size.width, m.visibleFrame.width - 2 * edgeInset)
        let h = min(size.height, m.visibleFrame.height - 2 * edgeInset)
        return CGRect(x: m.visibleFrame.maxX - w - edgeInset,
                      y: m.visibleFrame.minY + edgeInset,
                      width: w, height: h)
    }
}
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter AnchorTests`
Expected: PASS, 12 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/NotchLyricsCore/Geometry Tests/NotchLyricsCoreTests/AnchorTests.swift
git commit -m "feat: screen metrics and anchor geometry for all four positions"
```

---

### Task 6: HTTP seam and LRCLIB provider

**Files:**
- Create: `Sources/NotchLyricsCore/Lyrics/HTTPFetching.swift`
- Create: `Sources/NotchLyricsCore/Lyrics/LyricsProvider.swift`
- Create: `Sources/NotchLyricsCore/Lyrics/LRCLIBProvider.swift`
- Create: `Tests/NotchLyricsCoreTests/Support/StubHTTP.swift`
- Test: `Tests/NotchLyricsCoreTests/LRCLIBProviderTests.swift`

**Interfaces:**
- Consumes: `TrackQuery`, `LyricsDocument` (Task 1), `LRCParser` (Task 2), `WordTimingEstimator` (Task 3).
- Produces: `HTTPFetching` protocol (`get`, `post`), `URLSessionHTTP`, `LyricsProvider` protocol (`id`, `fetch`), `LRCLIBProvider(http:)`. Tasks 8 and 14 depend on these exact names.

Fixture bodies come from the live responses recorded in spec §1.5.

- [ ] **Step 1: Write the stub and the failing test**

`Tests/NotchLyricsCoreTests/Support/StubHTTP.swift`:

```swift
import Foundation
@testable import NotchLyricsCore

actor StubHTTP: HTTPFetching {
    struct Response { let body: Data; let status: Int }
    private var routes: [String: Response] = [:]
    private(set) var requestedURLs: [String] = []
    var failure: Error?

    func stub(urlContains key: String, json: String, status: Int = 200) {
        routes[key] = Response(body: Data(json.utf8), status: status)
    }

    func setFailure(_ e: Error) { failure = e }

    func get(_ url: URL, headers: [String: String]) async throws -> (Data, Int) {
        requestedURLs.append(url.absoluteString)
        if let failure { throw failure }
        for (key, r) in routes where url.absoluteString.contains(key) {
            return (r.body, r.status)
        }
        return (Data("{}".utf8), 404)
    }

    func post(_ url: URL, headers: [String: String], body: Data) async throws -> (Data, Int) {
        requestedURLs.append(url.absoluteString)
        if let failure { throw failure }
        for (key, r) in routes where url.absoluteString.contains(key) {
            return (r.body, r.status)
        }
        return (Data("{}".utf8), 404)
    }
}

struct StubError: Error {}

let sampleQuery = TrackQuery(
    trackID: "spotify:track:3BJe4B8zGnqEdQPMvfVjuS",
    title: "Summertime Sadness", artist: "Lana Del Rey",
    album: "Born To Die", duration: 265.427
)
```

`Tests/NotchLyricsCoreTests/LRCLIBProviderTests.swift`:

```swift
import Testing
import Foundation
@testable import NotchLyricsCore

/// Shape recorded from a live lrclib.net response (spec §1.5).
private let lrclibHit = """
{"id":15939,"trackName":"Summertime Sadness","artistName":"Lana Del Rey",
 "albumName":"Born To Die","duration":265.0,"instrumental":false,
 "plainLyrics":"Kiss me hard before you go",
 "syncedLyrics":"[00:17.38] Kiss me hard before you go\\n[00:21.61] Summertime sadness"}
"""

private let lrclibMiss = """
{"statusCode":404,"error":"Not Found","message":"Failed to find specified track"}
"""

private let lrclibInstrumental = """
{"id":1,"trackName":"X","artistName":"Y","albumName":"Z","duration":265.0,
 "instrumental":true,"plainLyrics":null,"syncedLyrics":null}
"""

private let lrclibPlainOnly = """
{"id":2,"trackName":"X","artistName":"Y","albumName":"Z","duration":265.0,
 "instrumental":false,"plainLyrics":"just words","syncedLyrics":null}
"""

@Test func parsesSyncedLyricsIntoDocument() async throws {
    let http = StubHTTP()
    await http.stub(urlContains: "lrclib.net", json: lrclibHit)
    let doc = try await LRCLIBProvider(http: http).fetch(sampleQuery)
    #expect(doc?.providerID == "lrclib")
    #expect(doc?.lines.count == 2)
    #expect(doc?.lines[0].text == "Kiss me hard before you go")
    #expect(doc?.trackID == sampleQuery.trackID)
}

@Test func wordTimingsAreFilledIn() async throws {
    let http = StubHTTP()
    await http.stub(urlContains: "lrclib.net", json: lrclibHit)
    let doc = try await LRCLIBProvider(http: http).fetch(sampleQuery)
    let words = doc!.lines[0].words
    #expect(words.count == 6)
    #expect(words[0].start == doc!.lines[0].start)
    #expect(words[0].end > words[0].start)      // estimator ran
    #expect(words.allSatisfy(\.isEstimated))
}

@Test func sendsDurationInSecondsNotMilliseconds() async throws {
    let http = StubHTTP()
    await http.stub(urlContains: "lrclib.net", json: lrclibHit)
    _ = try await LRCLIBProvider(http: http).fetch(sampleQuery)
    let url = await http.requestedURLs.first!
    #expect(url.contains("duration=265"))
    #expect(url.contains("duration=265427") == false)
}

@Test func returnsNilOn404() async throws {
    let http = StubHTTP()
    await http.stub(urlContains: "lrclib.net", json: lrclibMiss, status: 404)
    #expect(try await LRCLIBProvider(http: http).fetch(sampleQuery) == nil)
}

@Test func returnsNilForInstrumental() async throws {
    let http = StubHTTP()
    await http.stub(urlContains: "lrclib.net", json: lrclibInstrumental)
    #expect(try await LRCLIBProvider(http: http).fetch(sampleQuery) == nil)
}

@Test func returnsNilWhenOnlyPlainLyricsExist() async throws {
    let http = StubHTTP()
    await http.stub(urlContains: "lrclib.net", json: lrclibPlainOnly)
    #expect(try await LRCLIBProvider(http: http).fetch(sampleQuery) == nil)
}

@Test func propagatesTransportErrors() async {
    let http = StubHTTP()
    await http.setFailure(StubError())
    await #expect(throws: (any Error).self) {
        try await LRCLIBProvider(http: http).fetch(sampleQuery)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter LRCLIBProviderTests`
Expected: FAIL — `cannot find 'LRCLIBProvider' in scope`.

- [ ] **Step 3: Implement**

`HTTPFetching.swift`:

```swift
import Foundation

public protocol HTTPFetching: Sendable {
    func get(_ url: URL, headers: [String: String]) async throws -> (Data, Int)
    func post(_ url: URL, headers: [String: String], body: Data) async throws -> (Data, Int)
}

public struct URLSessionHTTP: HTTPFetching {
    public static let userAgent = "NotchLyrics/1.0 (personal use)"
    private let session: URLSession

    public init(timeout: TimeInterval = 8) {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = timeout
        cfg.waitsForConnectivity = false
        session = URLSession(configuration: cfg)
    }

    public func get(_ url: URL, headers: [String: String]) async throws -> (Data, Int) {
        try await run(request(url, method: "GET", headers: headers, body: nil))
    }

    public func post(_ url: URL, headers: [String: String], body: Data) async throws -> (Data, Int) {
        try await run(request(url, method: "POST", headers: headers, body: body))
    }

    private func request(_ url: URL, method: String,
                         headers: [String: String], body: Data?) -> URLRequest {
        var r = URLRequest(url: url)
        r.httpMethod = method
        r.httpBody = body
        r.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        for (k, v) in headers { r.setValue(v, forHTTPHeaderField: k) }
        return r
    }

    private func run(_ r: URLRequest) async throws -> (Data, Int) {
        let (data, response) = try await session.data(for: r)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
}
```

`LyricsProvider.swift`:

```swift
import Foundation

public protocol LyricsProvider: Sendable {
    var id: String { get }
    /// Returns nil when the provider simply has no synced lyrics for this track.
    /// Throws only on transport or decoding failure.
    func fetch(_ track: TrackQuery) async throws -> LyricsDocument?
}

public extension LyricsProvider {
    /// Rejects a candidate whose length disagrees with the playing track.
    func durationMatches(_ candidate: TimeInterval, _ track: TrackQuery,
                         tolerance: TimeInterval = 3) -> Bool {
        guard candidate > 0, track.duration > 0 else { return true }
        return abs(candidate - track.duration) <= tolerance
    }

    func buildDocument(trackID: String, lrc: String, duration: TimeInterval) -> LyricsDocument? {
        let lines = WordTimingEstimator.apply(to: LRCParser.parse(lrc, trackDuration: duration))
        let doc = LyricsDocument(trackID: trackID, providerID: id, lines: lines)
        return doc.isEmpty ? nil : doc
    }
}
```

`LRCLIBProvider.swift`:

```swift
import Foundation

public struct LRCLIBProvider: LyricsProvider {
    public let id = "lrclib"
    private let http: any HTTPFetching

    public init(http: any HTTPFetching) { self.http = http }

    private struct Payload: Decodable {
        let instrumental: Bool?
        let duration: Double?
        let syncedLyrics: String?
    }

    public func fetch(_ track: TrackQuery) async throws -> LyricsDocument? {
        var c = URLComponents(string: "https://lrclib.net/api/get")!
        c.queryItems = [
            .init(name: "track_name", value: track.title),
            .init(name: "artist_name", value: track.artist),
            .init(name: "album_name", value: track.album),
            // LRCLIB expects whole seconds, not milliseconds.
            .init(name: "duration", value: String(Int(track.duration.rounded()))),
        ]
        guard let url = c.url else { return nil }

        let (data, status) = try await http.get(url, headers: [:])
        guard status == 200 else { return nil }

        let payload = try JSONDecoder().decode(Payload.self, from: data)
        guard payload.instrumental != true,
              let lrc = payload.syncedLyrics, !lrc.isEmpty,
              durationMatches(payload.duration ?? 0, track)
        else { return nil }

        return buildDocument(trackID: track.trackID, lrc: lrc, duration: track.duration)
    }
}
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter LRCLIBProviderTests`
Expected: PASS, 7 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/NotchLyricsCore/Lyrics Tests/NotchLyricsCoreTests
git commit -m "feat: HTTP seam, provider protocol and LRCLIB provider"
```

---

### Task 7: Disk cache

**Files:**
- Create: `Sources/NotchLyricsCore/Lyrics/LyricsCache.swift`
- Test: `Tests/NotchLyricsCoreTests/LyricsCacheTests.swift`

**Interfaces:**
- Consumes: `LyricsDocument` (Task 1).
- Produces: `actor LyricsCache(directory:)` with `load(trackID:) -> CacheHit?`, `store(trackID:document:)`. `CacheHit` is `enum { case found(LyricsDocument), case knownMissing }`. Negative entries expire after 7 days; positive entries never expire.

- [ ] **Step 1: Write the failing test**

```swift
import Testing
import Foundation
@testable import NotchLyricsCore

private func tempDir() -> URL {
    let u = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("notchlyrics-tests-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
    return u
}

private let sampleDoc = LyricsDocument(trackID: "t1", providerID: "lrclib", lines: [
    LyricLine(start: 1, end: 2, words: [WordToken(text: "hi", start: 1, end: 2, isEstimated: true)])
])

@Test func returnsNilForUnknownTrack() async {
    let c = LyricsCache(directory: tempDir())
    #expect(await c.load(trackID: "nope") == nil)
}

@Test func roundTripsADocument() async {
    let c = LyricsCache(directory: tempDir())
    await c.store(trackID: "t1", document: sampleDoc)
    guard case .found(let d)? = await c.load(trackID: "t1") else {
        Issue.record("expected a cached document"); return
    }
    #expect(d == sampleDoc)
}

@Test func recordsNegativeResults() async {
    let c = LyricsCache(directory: tempDir())
    await c.store(trackID: "t2", document: nil)
    guard case .knownMissing? = await c.load(trackID: "t2") else {
        Issue.record("expected a negative cache hit"); return
    }
}

@Test func negativeEntriesExpire() async {
    let dir = tempDir()
    let c = LyricsCache(directory: dir, negativeTTL: -1)   // already expired
    await c.store(trackID: "t3", document: nil)
    #expect(await c.load(trackID: "t3") == nil)
}

@Test func positiveEntriesDoNotExpire() async {
    let c = LyricsCache(directory: tempDir(), negativeTTL: -1)
    await c.store(trackID: "t4", document: sampleDoc)
    #expect(await c.load(trackID: "t4") != nil)
}

@Test func sanitizesTrackIDIntoASafeFilename() async {
    let dir = tempDir()
    let c = LyricsCache(directory: dir)
    await c.store(trackID: "spotify:track:3BJe/4B8z", document: sampleDoc)
    let files = try! FileManager.default.contentsOfDirectory(atPath: dir.path)
    #expect(files.count == 1)
    #expect(files[0].contains("/") == false)
    #expect(await c.load(trackID: "spotify:track:3BJe/4B8z") != nil)
}

@Test func survivesCorruptedFile() async {
    let dir = tempDir()
    let c = LyricsCache(directory: dir)
    await c.store(trackID: "t5", document: sampleDoc)
    let f = try! FileManager.default.contentsOfDirectory(atPath: dir.path)[0]
    try! Data("garbage".utf8).write(to: dir.appendingPathComponent(f))
    #expect(await c.load(trackID: "t5") == nil)
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter LyricsCacheTests`
Expected: FAIL — `cannot find 'LyricsCache' in scope`.

- [ ] **Step 3: Implement**

```swift
import Foundation

public actor LyricsCache {
    public enum CacheHit: Equatable {
        case found(LyricsDocument)
        case knownMissing
    }

    private struct Entry: Codable {
        var document: LyricsDocument?
        var storedAt: Date
    }

    private let directory: URL
    private let negativeTTL: TimeInterval

    /// - Parameter negativeTTL: how long a "no lyrics" result stays valid.
    public init(directory: URL, negativeTTL: TimeInterval = 7 * 24 * 3600) {
        self.directory = directory
        self.negativeTTL = negativeTTL
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    public static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("NotchLyrics/cache", isDirectory: true)
    }

    public func load(trackID: String) -> CacheHit? {
        guard let data = try? Data(contentsOf: url(for: trackID)),
              let entry = try? JSONDecoder().decode(Entry.self, from: data)
        else { return nil }

        if let doc = entry.document { return .found(doc) }
        guard Date().timeIntervalSince(entry.storedAt) < negativeTTL else { return nil }
        return .knownMissing
    }

    public func store(trackID: String, document: LyricsDocument?) {
        let entry = Entry(document: document, storedAt: Date())
        guard let data = try? JSONEncoder().encode(entry) else { return }
        try? data.write(to: url(for: trackID), options: .atomic)
    }

    private func url(for trackID: String) -> URL {
        let safe = trackID.map { $0.isLetter || $0.isNumber ? String($0) : "_" }.joined()
        return directory.appendingPathComponent("\(safe).json")
    }
}
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter LyricsCacheTests`
Expected: PASS, 7 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/NotchLyricsCore/Lyrics/LyricsCache.swift Tests/NotchLyricsCoreTests/LyricsCacheTests.swift
git commit -m "feat: disk cache with negative-result TTL"
```

---

### Task 8: Lyrics service

**Files:**
- Create: `Sources/NotchLyricsCore/Lyrics/LyricsService.swift`
- Test: `Tests/NotchLyricsCoreTests/LyricsServiceTests.swift`

**Interfaces:**
- Consumes: `LyricsProvider` (Task 6), `LyricsCache` (Task 7).
- Produces: `actor LyricsService(providers:cache:)` with `func lyrics(for track: TrackQuery) async -> LyricsDocument?`. Never throws — a failing provider is skipped so one bad source cannot break the chain (spec §3.3).

- [ ] **Step 1: Write the failing test**

```swift
import Testing
import Foundation
@testable import NotchLyricsCore

private func tempCache() -> LyricsCache {
    let u = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("nl-svc-\(UUID().uuidString)")
    return LyricsCache(directory: u)
}

private struct FakeProvider: LyricsProvider {
    let id: String
    let result: LyricsDocument?
    var error: Error?
    let calls: Counter

    func fetch(_ track: TrackQuery) async throws -> LyricsDocument? {
        await calls.bump(id)
        if let error { throw error }
        return result
    }
}

private actor Counter {
    private(set) var ids: [String] = []
    func bump(_ id: String) { ids.append(id) }
}

private func doc(_ provider: String) -> LyricsDocument {
    LyricsDocument(trackID: sampleQuery.trackID, providerID: provider, lines: [
        LyricLine(start: 0, end: 1, words: [WordToken(text: "x", start: 0, end: 1, isEstimated: true)])
    ])
}

@Test func returnsFirstProviderResult() async {
    let c = Counter()
    let svc = LyricsService(
        providers: [FakeProvider(id: "a", result: doc("a"), calls: c),
                    FakeProvider(id: "b", result: doc("b"), calls: c)],
        cache: tempCache())
    let out = await svc.lyrics(for: sampleQuery)
    #expect(out?.providerID == "a")
    #expect(await c.ids == ["a"])       // b never consulted
}

@Test func fallsThroughWhenFirstReturnsNil() async {
    let c = Counter()
    let svc = LyricsService(
        providers: [FakeProvider(id: "a", result: nil, calls: c),
                    FakeProvider(id: "b", result: doc("b"), calls: c)],
        cache: tempCache())
    #expect(await svc.lyrics(for: sampleQuery)?.providerID == "b")
    #expect(await c.ids == ["a", "b"])
}

@Test func aThrowingProviderDoesNotBlockTheChain() async {
    let c = Counter()
    let svc = LyricsService(
        providers: [FakeProvider(id: "a", result: nil, error: StubError(), calls: c),
                    FakeProvider(id: "b", result: doc("b"), calls: c)],
        cache: tempCache())
    #expect(await svc.lyrics(for: sampleQuery)?.providerID == "b")
}

@Test func returnsNilWhenEveryProviderMisses() async {
    let c = Counter()
    let svc = LyricsService(providers: [FakeProvider(id: "a", result: nil, calls: c)],
                            cache: tempCache())
    #expect(await svc.lyrics(for: sampleQuery) == nil)
}

@Test func secondLookupIsServedFromCache() async {
    let c = Counter()
    let svc = LyricsService(providers: [FakeProvider(id: "a", result: doc("a"), calls: c)],
                            cache: tempCache())
    _ = await svc.lyrics(for: sampleQuery)
    _ = await svc.lyrics(for: sampleQuery)
    #expect(await c.ids == ["a"])       // provider hit exactly once
}

@Test func negativeResultIsCachedToo() async {
    let c = Counter()
    let svc = LyricsService(providers: [FakeProvider(id: "a", result: nil, calls: c)],
                            cache: tempCache())
    _ = await svc.lyrics(for: sampleQuery)
    _ = await svc.lyrics(for: sampleQuery)
    #expect(await c.ids == ["a"])
}

@Test func emptyProviderListReturnsNil() async {
    #expect(await LyricsService(providers: [], cache: tempCache()).lyrics(for: sampleQuery) == nil)
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter LyricsServiceTests`
Expected: FAIL — `cannot find 'LyricsService' in scope`.

- [ ] **Step 3: Implement**

```swift
import Foundation
import OSLog

public actor LyricsService {
    private let providers: [any LyricsProvider]
    private let cache: LyricsCache
    private let log = Logger(subsystem: "com.local.NotchLyrics", category: "lyrics")

    public init(providers: [any LyricsProvider], cache: LyricsCache) {
        self.providers = providers
        self.cache = cache
    }

    /// Never throws: a provider that fails is logged and skipped so one bad
    /// source cannot break the chain (spec §3.3).
    public func lyrics(for track: TrackQuery) async -> LyricsDocument? {
        switch await cache.load(trackID: track.trackID) {
        case .found(let doc): return doc
        case .knownMissing:   return nil
        case nil:             break
        }

        for provider in providers {
            do {
                if let doc = try await provider.fetch(track) {
                    await cache.store(trackID: track.trackID, document: doc)
                    return doc
                }
            } catch {
                log.error("provider \(provider.id, privacy: .public) failed: \(error)")
            }
        }

        await cache.store(trackID: track.trackID, document: nil)
        return nil
    }
}
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter LyricsServiceTests`
Expected: PASS, 7 tests.

- [ ] **Step 5: Run the whole suite and commit**

```bash
swift test
git add Sources/NotchLyricsCore/Lyrics/LyricsService.swift Tests/NotchLyricsCoreTests/LyricsServiceTests.swift
git commit -m "feat: lyrics service with provider chain and caching"
```

---

### Task 9: Spotify bridge

**Files:**
- Create: `Sources/NotchLyricsApp/SpotifyBridge.swift`
- Create: `Sources/NotchLyricsApp/main.swift` (temporary probe, replaced in Task 12)

**Interfaces:**
- Consumes: `PlaybackState` (Task 1).
- Produces: `@MainActor final class SpotifyBridge` with `var onChange: ((PlaybackState?) -> Void)?`, `func start()`, `func stop()`. Emits `nil` when Spotify is not running or stopped.

Verified behaviour this encodes (spec §1.2–1.3): precompile the script once (cold 251 ms → warm 54 ms), run it off the main thread, poll 1 Hz while playing and every 5 s otherwise, and re-poll immediately on `com.spotify.client.PlaybackStateChanged`.

This task has no unit test — it is I/O against a live app. It is verified by the manual probe in Step 3.

- [ ] **Step 1: Implement the bridge**

```swift
import Foundation
import AppKit
import NotchLyricsCore

/// Reads Spotify playback via AppleScript.
///
/// Spotify exposes no lyrics property (spec §1.2), so this supplies only
/// track identity and position; lyrics come from LyricsService.
@MainActor
final class SpotifyBridge {
    static let notificationName = Notification.Name("com.spotify.client.PlaybackStateChanged")

    /// `duration` is milliseconds and `player position` is seconds (spec §1.2).
    private static let source = """
    tell application "Spotify"
      if it is not running then return "NOTRUNNING"
      set theState to (player state as text)
      if theState is "stopped" then return "STOPPED"
      set theTrack to current track
      return theState & "\\t" & (id of theTrack) & "\\t" & (name of theTrack) & "\\t" ¬
        & (artist of theTrack) & "\\t" & (album of theTrack) & "\\t" ¬
        & (duration of theTrack) & "\\t" & (player position)
    end tell
    """

    var onChange: ((PlaybackState?) -> Void)?

    private let script: NSAppleScript?
    private let queue = DispatchQueue(label: "com.local.NotchLyrics.applescript")
    private var timer: Timer?
    private var lastWasPlaying = false

    init() {
        script = NSAppleScript(source: Self.source)
        var err: NSDictionary?
        script?.compileAndReturnError(&err)   // pay the 251 ms cold cost once
        if let err { NSLog("NotchLyrics: AppleScript compile failed: \(err)") }
    }

    func start() {
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(spotifyChanged),
            name: Self.notificationName, object: nil)
        schedule(interval: 1)
        poll()
    }

    func stop() {
        timer?.invalidate(); timer = nil
        DistributedNotificationCenter.default().removeObserver(self)
    }

    @objc private func spotifyChanged() { poll() }

    private func schedule(interval: TimeInterval) {
        timer?.invalidate()
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        t.tolerance = interval * 0.2
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func poll() {
        guard let script else { return }
        queue.async {
            var err: NSDictionary?
            let raw = script.executeAndReturnError(&err).stringValue
            Task { @MainActor [weak self] in
                self?.handle(raw: err == nil ? raw : nil)
            }
        }
    }

    private func handle(raw: String?) {
        let state = Self.parse(raw)
        // Back off to 5 s when nothing is playing; 1 Hz keeps sync tight while it is.
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
        guard f.count == 7, let durationMs = Int(f[5].trimmingCharacters(in: .whitespaces)),
              let position = Double(f[6].trimmingCharacters(in: .whitespaces))
        else { return nil }
        return PlaybackState(trackID: f[1], title: f[2], artist: f[3], album: f[4],
                             durationMs: durationMs, position: position,
                             isPlaying: f[0] == "playing")
    }
}
```

- [ ] **Step 2: Write a temporary probe entry point**

`Sources/NotchLyricsApp/main.swift`:

```swift
import AppKit
import NotchLyricsCore

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

final class ProbeDelegate: NSObject, NSApplicationDelegate {
    let bridge = SpotifyBridge()
    var ticks = 0
    func applicationDidFinishLaunching(_ n: Notification) {
        bridge.onChange = { state in
            self.ticks += 1
            if let s = state {
                print("[\(self.ticks)] \(s.isPlaying ? "▶" : "❚❚") \(s.title) — \(s.artist) "
                    + "| \(String(format: "%.2f", s.position))/\(String(format: "%.2f", s.duration))s")
            } else {
                print("[\(self.ticks)] no playback")
            }
            if self.ticks >= 5 { NSApp.terminate(nil) }
        }
        bridge.start()
    }
}
let d = ProbeDelegate()
app.delegate = d
app.run()
```

- [ ] **Step 3: Verify against live Spotify**

Run: `swift run NotchLyricsApp`
Expected: five lines showing the real track and an advancing position, e.g.
`[1] ▶ Summertime Sadness — Lana Del Rey | 83.75/265.43s`.

If it prints `no playback`, start Spotify and play something. If macOS shows an
Automation permission prompt, approve it.

- [ ] **Step 4: Commit**

```bash
git add Sources/NotchLyricsApp
git commit -m "feat: Spotify AppleScript bridge with adaptive polling"
```

---

### Task 10: Overlay window

**Files:**
- Create: `Sources/NotchLyricsApp/OverlayWindow.swift`

**Interfaces:**
- Consumes: `Position`, `ScreenMetrics`, `Anchor` (Tasks 1, 5).
- Produces: `final class OverlayWindow: NSPanel` with `init(position:)`, `func reanchor(to:)`, `func setContent(_:)`, `func fadeIn()`, `func fadeOut()`, and `extension ScreenMetrics { init(_ screen: NSScreen) }`.

Configuration is exactly what was validated live in spec §1.6.

- [ ] **Step 1: Implement**

```swift
import AppKit
import SwiftUI
import NotchLyricsCore

extension ScreenMetrics {
    init(_ screen: NSScreen) {
        self.init(frame: screen.frame,
                  visibleFrame: screen.visibleFrame,
                  safeAreaTop: screen.safeAreaInsets.top,
                  auxTopLeft: screen.auxiliaryTopLeftArea,
                  auxTopRight: screen.auxiliaryTopRightArea)
    }
}

/// Borderless click-through panel that floats above the menu bar on every Space.
/// This configuration was validated on the target machine (spec §1.6).
final class OverlayWindow: NSPanel {
    private(set) var position: Position
    private var hosting: NSHostingView<AnyView>?

    init(position: Position) {
        self.position = position
        super.init(contentRect: CGRect(x: 0, y: 0, width: 420, height: 84),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isMovable = false
        hidesOnDeactivate = false
        alphaValue = 0
        level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func setContent<V: View>(_ view: V) {
        let wrapped = AnyView(view)
        if let hosting {
            hosting.rootView = wrapped
        } else {
            let h = NSHostingView(rootView: wrapped)
            h.frame = contentRect(forFrameRect: frame)
            h.autoresizingMask = [.width, .height]
            contentView = h
            hosting = h
        }
    }

    /// Panel size per position: the ear is limited to the menu bar's height.
    private func preferredSize(for metrics: ScreenMetrics) -> CGSize {
        switch position {
        case .notch:       CGSize(width: 460, height: 84)
        case .earLeft, .earRight:
            CGSize(width: 340, height: max(22, metrics.safeAreaTop))
        case .bottomRight: CGSize(width: 380, height: 72)
        }
    }

    func reanchor(to screen: NSScreen?) {
        guard let screen = screen ?? NSScreen.main else { return }
        let metrics = ScreenMetrics(screen)
        let size = preferredSize(for: metrics)
        setFrame(Anchor.frame(for: position, in: metrics, size: size), display: true)
    }

    func setPosition(_ new: Position, screen: NSScreen?) {
        position = new
        reanchor(to: screen)
    }

    func fadeIn() {
        guard alphaValue < 1 else { return }
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            animator().alphaValue = 1
        }
    }

    func fadeOut() {
        guard alphaValue > 0 else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, self.alphaValue == 0 else { return }
            self.orderOut(nil)
        })
    }
}
```

- [ ] **Step 2: Verify it builds**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/NotchLyricsApp/OverlayWindow.swift
git commit -m "feat: click-through overlay panel above the menu bar"
```

---

### Task 11: Lyric view with word sweep

**Files:**
- Create: `Sources/NotchLyricsApp/LyricView.swift`

**Interfaces:**
- Consumes: `LyricLine`, `WordToken`, `Position` (Tasks 1, 3).
- Produces: `struct LyricView: View` taking `line: LyricLine?`, `time: TimeInterval`, `position: Position`, and `struct NotchShape: Shape`.

The sweep: sung text is bright, upcoming text dim, with a soft gradient boundary rather than a hard cut (spec §3.8). Progress is computed from word spans produced by Task 3.

- [ ] **Step 1: Implement**

```swift
import SwiftUI
import NotchLyricsCore

/// Square top corners, rounded bottom — so the panel reads as an extension
/// of the notch rather than a separate floating box.
struct NotchShape: Shape {
    var radius: CGFloat = 14
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - radius))
        p.addQuadCurve(to: CGPoint(x: rect.minX + radius, y: rect.maxY),
                       control: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY - radius),
                       control: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

struct LyricView: View {
    let line: LyricLine?
    let time: TimeInterval
    let position: Position

    private var isEar: Bool { position == .earLeft || position == .earRight }

    /// Fraction of the line already sung, derived from word spans.
    private var sweep: Double {
        guard let line, !line.words.isEmpty else { return 0 }
        let widths = line.words.map { Double($0.text.count + 1) }
        let total = widths.reduce(0, +)
        guard total > 0 else { return 0 }
        var done = 0.0
        for (i, w) in line.words.enumerated() {
            done += widths[i] * w.progress(at: time)
        }
        return min(1, max(0, done / total))
    }

    private var font: Font {
        isEar ? .system(size: 12, weight: .medium)
              : .system(size: position == .notch ? 15 : 14, weight: .semibold)
    }

    var body: some View {
        ZStack {
            background
            if let line, !line.isBlank {
                text(line)
                    .padding(.horizontal, isEar ? 8 : 16)
                    .padding(.bottom, position == .notch ? 10 : 0)
                    .frame(maxWidth: .infinity, maxHeight: .infinity,
                           alignment: position == .notch ? .bottom : .center)
                    .id(line.start)
                    .transition(.opacity.combined(with: .offset(y: 6)))
            }
        }
        .animation(.easeOut(duration: 0.25), value: line?.start)
    }

    @ViewBuilder private var background: some View {
        switch position {
        case .notch:
            NotchShape().fill(.black)
        case .earLeft, .earRight:
            Color.clear
        case .bottomRight:
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.black.opacity(0.72))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(.white.opacity(0.08), lineWidth: 1))
        }
    }

    private func text(_ line: LyricLine) -> some View {
        Text(line.text)
            .font(font)
            .lineLimit(isEar ? 1 : 2)
            .multilineTextAlignment(.center)
            .minimumScaleFactor(0.7)
            .foregroundStyle(.white.opacity(0.34))
            .overlay(alignment: .leading) {
                // Bright layer revealed left-to-right as the line is sung.
                Text(line.text)
                    .font(font)
                    .lineLimit(isEar ? 1 : 2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(.white)
                    .mask(alignment: .leading) {
                        GeometryReader { geo in
                            LinearGradient(
                                stops: [
                                    .init(color: .white, location: 0),
                                    .init(color: .white, location: max(0, sweep - 0.04)),
                                    .init(color: .clear, location: min(1, sweep + 0.04)),
                                    .init(color: .clear, location: 1),
                                ],
                                startPoint: .leading, endPoint: .trailing)
                            .frame(width: geo.size.width, height: geo.size.height)
                        }
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
git add Sources/NotchLyricsApp/LyricView.swift
git commit -m "feat: lyric view with interpolated word sweep"
```

---

### Task 12: NetEase provider

**Files:**
- Create: `Sources/NotchLyricsCore/Lyrics/NetEaseProvider.swift`
- Test: `Tests/NotchLyricsCoreTests/NetEaseProviderTests.swift`

**Interfaces:**
- Consumes: `LyricsProvider`, `HTTPFetching` (Task 6).
- Produces: `NetEaseProvider(http:)`. Consumed by `OverlayController` in Task 13.

Endpoints verified live (spec §1.5): search is a `POST` form to
`music.163.com/api/search/get/` with a `Referer` header; lyrics are `GET
music.163.com/api/song/lyric?id=…&lv=1&kv=1&tv=-1`. NetEase durations are in
milliseconds.

- [ ] **Step 1: Write the failing test**

```swift
import Testing
import Foundation
@testable import NotchLyricsCore

/// Shapes recorded from live music.163.com responses (spec §1.5).
private let searchHit = """
{"result":{"songs":[
  {"id":16593589,"name":"Summertime Sadness","duration":264773,
   "artists":[{"name":"Lana Del Rey"}]}]},"code":200}
"""

private let searchWrongDuration = """
{"result":{"songs":[
  {"id":26203201,"name":"Summertime Sadness (Asadinho Vocal Mix)","duration":514737,
   "artists":[{"name":"Lana Del Rey"}]}]},"code":200}
"""

private let searchEmpty = #"{"result":{"songs":[]},"code":200}"#

private let lyricHit = """
{"lrc":{"lyric":"[00:00.000] 作词 : Lana Del Rey\\n[00:17.320]Kiss me hard before you go\\n[00:21.389]Summertime sadness"},"code":200}
"""

private let lyricEmpty = #"{"lrc":{"lyric":""},"code":200}"#

@Test func fetchesAndParsesNetEaseLyrics() async throws {
    let http = StubHTTP()
    await http.stub(urlContains: "search/get", json: searchHit)
    await http.stub(urlContains: "song/lyric", json: lyricHit)
    let doc = try await NetEaseProvider(http: http).fetch(sampleQuery)
    #expect(doc?.providerID == "netease")
    #expect(doc?.lines.count == 2)              // credit line stripped
    #expect(doc?.lines[0].text == "Kiss me hard before you go")
}

@Test func rejectsCandidateOutsideDurationTolerance() async throws {
    let http = StubHTTP()
    await http.stub(urlContains: "search/get", json: searchWrongDuration)
    await http.stub(urlContains: "song/lyric", json: lyricHit)
    #expect(try await NetEaseProvider(http: http).fetch(sampleQuery) == nil)
}

@Test func returnsNilWhenSearchFindsNothing() async throws {
    let http = StubHTTP()
    await http.stub(urlContains: "search/get", json: searchEmpty)
    #expect(try await NetEaseProvider(http: http).fetch(sampleQuery) == nil)
}

@Test func returnsNilWhenLyricBodyIsEmpty() async throws {
    let http = StubHTTP()
    await http.stub(urlContains: "search/get", json: searchHit)
    await http.stub(urlContains: "song/lyric", json: lyricEmpty)
    #expect(try await NetEaseProvider(http: http).fetch(sampleQuery) == nil)
}

@Test func sendsRefererHeaderRequiredByNetEase() async throws {
    let http = StubHTTP()
    await http.stub(urlContains: "search/get", json: searchHit)
    await http.stub(urlContains: "song/lyric", json: lyricHit)
    _ = try await NetEaseProvider(http: http).fetch(sampleQuery)
    #expect(await http.requestedURLs.contains { $0.contains("search/get") })
    #expect(await http.requestedURLs.contains { $0.contains("song/lyric") })
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter NetEaseProviderTests`
Expected: FAIL — `cannot find 'NetEaseProvider' in scope`.

- [ ] **Step 3: Implement**

```swift
import Foundation

/// NetEase Cloud Music. No authentication required; a Referer header is
/// mandatory or the endpoint rejects the request (spec §1.5).
public struct NetEaseProvider: LyricsProvider {
    public let id = "netease"
    private let http: any HTTPFetching

    public init(http: any HTTPFetching) { self.http = http }

    private static let headers = [
        "Referer": "https://music.163.com",
        "Content-Type": "application/x-www-form-urlencoded",
    ]

    private struct SearchResponse: Decodable {
        struct Result: Decodable { let songs: [Song]? }
        struct Song: Decodable {
            let id: Int
            let name: String
            let duration: Int      // milliseconds
        }
        let result: Result?
    }

    private struct LyricResponse: Decodable {
        struct LRC: Decodable { let lyric: String? }
        let lrc: LRC?
    }

    public func fetch(_ track: TrackQuery) async throws -> LyricsDocument? {
        guard let songID = try await search(track) else { return nil }

        guard let url = URL(string:
            "https://music.163.com/api/song/lyric?id=\(songID)&lv=1&kv=1&tv=-1")
        else { return nil }

        let (data, status) = try await http.get(url, headers: Self.headers)
        guard status == 200 else { return nil }

        let payload = try JSONDecoder().decode(LyricResponse.self, from: data)
        guard let lrc = payload.lrc?.lyric, !lrc.isEmpty else { return nil }

        return buildDocument(trackID: track.trackID, lrc: lrc, duration: track.duration)
    }

    private func search(_ track: TrackQuery) async throws -> Int? {
        guard let url = URL(string: "https://music.163.com/api/search/get/") else { return nil }

        var form = URLComponents()
        form.queryItems = [
            .init(name: "s", value: "\(track.title) \(track.artist)"),
            .init(name: "type", value: "1"),
            .init(name: "offset", value: "0"),
            .init(name: "limit", value: "5"),
        ]
        let body = Data((form.percentEncodedQuery ?? "").utf8)

        let (data, status) = try await http.post(url, headers: Self.headers, body: body)
        guard status == 200 else { return nil }

        let payload = try JSONDecoder().decode(SearchResponse.self, from: data)
        guard let songs = payload.result?.songs else { return nil }

        // NetEase durations are milliseconds; compare in seconds.
        return songs.first { durationMatches(Double($0.duration) / 1000, track) }?.id
    }
}
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter NetEaseProviderTests`
Expected: PASS, 5 tests.

- [ ] **Step 5: Run the full suite and commit**

```bash
swift test
git add Sources/NotchLyricsCore/Lyrics/NetEaseProvider.swift Tests/NotchLyricsCoreTests/NetEaseProviderTests.swift
git commit -m "feat: NetEase fallback provider"
```

---

### Task 13: Settings, menu bar, and app wiring

**Files:**
- Create: `Sources/NotchLyricsApp/Settings.swift`
- Create: `Sources/NotchLyricsApp/MenuBarController.swift`
- Create: `Sources/NotchLyricsApp/OverlayController.swift`
- Create: `Sources/NotchLyricsApp/AppDelegate.swift`
- Modify: `Sources/NotchLyricsApp/main.swift` (replace the Task 9 probe)

**Interfaces:**
- Consumes: everything from Tasks 1–12.
- Produces: the running app. `OverlayController` owns the `SpotifyBridge`, `PlaybackClock`, `LyricsService`, and `OverlayWindow`, and drives a 60 Hz display timer.

- [ ] **Step 1: Implement Settings**

```swift
import Foundation
import NotchLyricsCore

@MainActor
final class Settings {
    private enum Key {
        static let position = "position"
        static let fontScale = "fontScale"
        static let netEaseEnabled = "netEaseEnabled"
    }

    static let shared = Settings()
    private let defaults = UserDefaults.standard

    var onChange: (() -> Void)?

    var position: Position {
        get { Position(rawValue: defaults.string(forKey: Key.position) ?? "") ?? .notch }
        set { defaults.set(newValue.rawValue, forKey: Key.position); onChange?() }
    }

    var netEaseEnabled: Bool {
        get { defaults.object(forKey: Key.netEaseEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.netEaseEnabled); onChange?() }
    }
}
```

- [ ] **Step 2: Implement OverlayController**

```swift
import AppKit
import SwiftUI
import NotchLyricsCore

@MainActor
final class OverlayController {
    private let bridge = SpotifyBridge()
    private let service: LyricsService
    private var window: OverlayWindow
    private var clock = PlaybackClock()

    private var currentTrackID: String?
    private var document: LyricsDocument?
    private var fetchTask: Task<Void, Never>?
    private var displayTimer: Timer?
    private var isPlaying = false
    private var renderedLineStart: TimeInterval?

    init() {
        var providers: [any LyricsProvider] = [LRCLIBProvider(http: URLSessionHTTP())]
        if Settings.shared.netEaseEnabled {
            providers.append(NetEaseProvider(http: URLSessionHTTP()))
        }
        service = LyricsService(providers: providers,
                                cache: LyricsCache(directory: LyricsCache.defaultDirectory()))
        window = OverlayWindow(position: Settings.shared.position)
        window.setContent(LyricView(line: nil, time: 0, position: Settings.shared.position))
        window.reanchor(to: NSScreen.main)
    }

    func start() {
        bridge.onChange = { [weak self] in self?.ingest($0) }
        bridge.start()

        Settings.shared.onChange = { [weak self] in
            guard let self else { return }
            self.window.setPosition(Settings.shared.position, screen: NSScreen.main)
            self.renderedLineStart = nil
            self.render()
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.window.reanchor(to: NSScreen.main) }
            }

        let t = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.render() }
        }
        RunLoop.main.add(t, forMode: .common)
        displayTimer = t
    }

    private func ingest(_ state: PlaybackState?) {
        guard let state else {
            isPlaying = false
            document = nil
            currentTrackID = nil
            fetchTask?.cancel()
            window.fadeOut()
            return
        }

        isPlaying = state.isPlaying
        clock.ingest(position: state.position, at: .now, isPlaying: state.isPlaying)

        guard state.trackID != currentTrackID else { return }
        currentTrackID = state.trackID
        document = nil
        renderedLineStart = nil

        fetchTask?.cancel()
        let query = state.query
        fetchTask = Task { [weak self] in
            let doc = await self?.service.lyrics(for: query)
            await MainActor.run {
                guard let self, self.currentTrackID == query.trackID else { return }
                self.document = doc      // stale results discarded (spec §4)
            }
        }
    }

    private func render() {
        guard isPlaying, let document else {
            window.fadeOut()
            return
        }
        let now = clock.position(at: .now)
        guard let idx = document.index(at: now) else {
            window.fadeOut()
            return
        }
        let line = document.lines[idx]
        guard !line.isBlank else {
            window.fadeOut()
            return
        }

        if renderedLineStart != line.start {
            renderedLineStart = line.start
        }
        window.setContent(LyricView(line: line, time: now, position: window.position))
        window.fadeIn()
    }
}
```

- [ ] **Step 3: Implement MenuBarController**

```swift
import AppKit
import NotchLyricsCore

@MainActor
final class MenuBarController {
    private let item = NSStatusItem.self
    private var statusItem: NSStatusItem!

    func install() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "music.note.list",
                                          accessibilityDescription: "NotchLyrics")
        rebuild()
    }

    private func rebuild() {
        let menu = NSMenu()

        let header = NSMenuItem(title: "Position", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        for p in Position.allCases {
            let mi = NSMenuItem(title: p.displayName,
                                action: #selector(selectPosition(_:)), keyEquivalent: "")
            mi.target = self
            mi.representedObject = p.rawValue
            mi.state = Settings.shared.position == p ? .on : .off
            menu.addItem(mi)
        }

        menu.addItem(.separator())

        let netease = NSMenuItem(title: "Use NetEase as fallback",
                                 action: #selector(toggleNetEase), keyEquivalent: "")
        netease.target = self
        netease.state = Settings.shared.netEaseEnabled ? .on : .off
        menu.addItem(netease)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit NotchLyrics",
                              action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        statusItem.menu = menu
    }

    @objc private func selectPosition(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let p = Position(rawValue: raw) else { return }
        Settings.shared.position = p
        rebuild()
    }

    @objc private func toggleNetEase() {
        Settings.shared.netEaseEnabled.toggle()
        rebuild()
    }
}
```

- [ ] **Step 4: Implement AppDelegate and replace main.swift**

`AppDelegate.swift`:

```swift
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let overlay = OverlayController()
    private let menuBar = MenuBarController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBar.install()
        overlay.start()
    }
}
```

`main.swift` (replaces the Task 9 probe entirely):

```swift
import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // menu-bar only, no Dock icon
let delegate = AppDelegate()
app.delegate = delegate
app.run()
```

- [ ] **Step 5: Build and run**

Run: `swift build && swift run NotchLyricsApp`
Expected: a music-note icon appears in the menu bar; with Spotify playing a track
that has lyrics, a black panel hangs below the notch and the current line sweeps
left to right. Switching position from the menu moves it live.

- [ ] **Step 6: Commit**

```bash
git add Sources/NotchLyricsApp
git commit -m "feat: settings, menu bar and full app wiring"
```

---

### Task 14: App bundle, launcher script, and README

**Files:**
- Create: `Scripts/build-app.sh`
- Create: `README.md`

**Interfaces:**
- Consumes: the built `NotchLyricsApp` executable.
- Produces: `NotchLyrics.app` with an `Info.plist` carrying `LSUIElement` and `NSAppleEventsUsageDescription`, ad-hoc signed.

`NSAppleEventsUsageDescription` is required or macOS denies the Automation
prompt outright. Ad-hoc signing means the TCC grant is tied to the binary's
cdhash, so a rebuild can re-prompt (spec §6).

- [ ] **Step 1: Write the build script**

```bash
#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/NotchLyrics.app"
CONFIG="${1:-release}"

echo "==> Building ($CONFIG)"
swift build -c "$CONFIG" --package-path "$ROOT"
BIN="$(swift build -c "$CONFIG" --package-path "$ROOT" --show-bin-path)/NotchLyricsApp"

echo "==> Assembling bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/NotchLyrics"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>                  <string>NotchLyrics</string>
  <key>CFBundleDisplayName</key>           <string>NotchLyrics</string>
  <key>CFBundleIdentifier</key>            <string>com.local.NotchLyrics</string>
  <key>CFBundleVersion</key>               <string>1.0</string>
  <key>CFBundleShortVersionString</key>    <string>1.0</string>
  <key>CFBundlePackageType</key>           <string>APPL</string>
  <key>CFBundleExecutable</key>            <string>NotchLyrics</string>
  <key>LSMinimumSystemVersion</key>        <string>14.0</string>
  <key>LSUIElement</key>                   <true/>
  <key>NSAppleEventsUsageDescription</key>
  <string>NotchLyrics reads the currently playing track from Spotify to display synced lyrics.</string>
</dict>
PLIST
echo '</plist>' >> "$APP/Contents/Info.plist"

echo "==> Signing (ad-hoc)"
codesign --force --deep --sign - "$APP"

echo "==> Built $APP"
echo "    Run: open $APP"
```

- [ ] **Step 2: Make it executable and build the bundle**

```bash
chmod +x Scripts/build-app.sh
./Scripts/build-app.sh release
```

Expected: `==> Built .../NotchLyrics.app`

- [ ] **Step 3: Verify the bundle**

```bash
plutil -lint NotchLyrics.app/Contents/Info.plist
codesign -dv NotchLyrics.app 2>&1 | head -3
open NotchLyrics.app
```

Expected: `OK`, signature details, and the menu-bar icon appears. Approve the
Automation prompt if macOS shows one.

- [ ] **Step 4: Write the README**

Cover: what it does, the notch-has-no-pixels constraint, build and run
instructions, the four positions, where the cache lives, the Automation
permission requirement and how to reset it (`tccutil reset AppleEvents
com.local.NotchLyrics`), and the ad-hoc-signing re-prompt caveat.

- [ ] **Step 5: Commit**

```bash
git add Scripts README.md .gitignore
git commit -m "feat: app bundle build script and README"
```

---

## Deferred: optional Spotify provider

Not implemented in this plan. Spec §1.8 records why: since 2025-12-22
`open.spotify.com/get_access_token` requires a TOTP derived from a secret
extracted from Spotify's web player JS bundle, and that secret rotates. Because
Spotify's lyrics are line-synced (spec §1.4) they offer no quality gain over
LRCLIB, so the recurring breakage buys nothing.

The `LyricsProvider` protocol is the extension point: implementing
`SpotifyProvider` and appending it to the `providers` array in
`OverlayController.init` is all that would be required, plus a settings toggle
and somewhere to store the `sp_dc` cookie.

---

## Self-Review

**Spec coverage:**

| Spec section | Task |
|---|---|
| §1.1 notch geometry | 5 (test values copied from measurements) |
| §1.2 Spotify AppleScript, ms/s units | 1 (`durationMs`), 9 (bridge) |
| §1.3 latency → 1 Hz + interpolation | 4, 9 |
| §1.4 line-synced → estimated words | 3 |
| §1.5 LRCLIB + NetEase | 6, 12 |
| §1.6 overlay window config | 10 |
| §1.7 MediaRemote rejected | n/a — no task needed |
| §1.8 Spotify provider deferred | Deferred section |
| §3.1 SpotifyBridge | 9 |
| §3.2 PlaybackClock | 4 |
| §3.3 provider chain, ±3 s tolerance | 6, 8 |
| §3.4 LRCParser | 2 |
| §3.5 cache incl. negative results | 7 |
| §3.6 OverlayWindow | 10 |
| §3.7 Anchor, no-notch fallback | 5 |
| §3.8 LyricView sweep | 11 |
| §3.9 MenuBarController | 13 |
| §3.10 Settings | 13 |
| §4 error handling | 8 (provider failure), 13 (stale fetch, no playback), 9 (Spotify absent) |
| §5 testing | 1–8, 12 |
| §6 build and signing | 14 |

**Placeholder scan:** none — every code step contains complete implementations.

**Type consistency:** `LyricsDocument.index(at:)`, `WordToken.progress(at:)`,
`Anchor.frame(for:in:size:)`, `LyricsCache.CacheHit`, `LyricsService.lyrics(for:)`,
`LyricsProvider.fetch(_:)`, `HTTPFetching.get/post`, and `ScreenMetrics.init(_:)`
are used consistently across tasks.

