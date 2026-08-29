import Foundation

public struct QuranProvider: LyricsProvider {
    public let id = "quran"
    /// 7 is Mishary Alafasy (murattal), whose recordings the timings were
    /// measured against.
    public static let defaultReciterID = 7
    /// The API rounds declared durations to whole seconds, so allow a little
    /// slack on top of the real tolerance.
    public static let durationTolerance: TimeInterval = 3

    private let http: any HTTPFetching
    private let reciterID: Int

    public init(http: any HTTPFetching, reciterID: Int = QuranProvider.defaultReciterID) {
        self.http = http; self.reciterID = reciterID
    }

    /// Returns the surah number when this track looks like a recitation.
    public static func surahNumber(for track: TrackQuery) -> Int? {
        let genre = track.quranHint?.genre?.lowercased() ?? ""
        let looksQuranic = genre.contains("quran") || track.album.lowercased().contains("quran")
        guard looksQuranic,
              let n = track.quranHint?.trackNumber,
              (1...114).contains(n)
        else { return nil }
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
            "https://api.quran.com/api/qdc/audio/reciters/\(reciterID)"
            + "/audio_files?chapter=\(surah)&segments=true") else { return nil }
        let (timingData, timingStatus) = try await http.get(timingURL, headers: [:])
        guard timingStatus == 200 else { return nil }
        let timing = try JSONDecoder().decode(TimingResponse.self, from: timingData)
        guard let file = timing.audio_files.first, let verses = file.verse_timings else { return nil }

        // Confirms this really is the recording the timings belong to.
        if let declared = file.duration, declared > 0 {
            let seconds = Double(declared) / 1000
            guard abs(seconds - track.duration) <= Self.durationTolerance else { return nil }
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
