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
    /// Forgets one track so the next lookup consults the providers again.
    public func forget(trackID: String) async {
        await cache.remove(trackID: trackID)
    }

    /// - Parameter refresh: skip whatever is cached and ask the providers
    ///   again. A manual re-sync uses this to get past a wrong match or a
    ///   remembered miss.
    public func lyrics(for track: TrackQuery, refresh: Bool = false) async -> LyricsDocument? {
        if refresh {
            await cache.remove(trackID: track.trackID)
        } else {
            switch await cache.load(trackID: track.trackID) {
            case .found(let doc): return doc
            case .knownMissing:   return nil
            case nil:             break
            }
        }

        var anyProviderFailed = false
        var best: (document: LyricsDocument, score: Double)?

        for provider in providers {
            do {
                guard let doc = try await provider.fetch(track) else { continue }

                // Sources often hold a different recording of the same song,
                // whose timings drift against the audio. Score each candidate
                // against the track instead of trusting whichever answers
                // first, so a badly matched entry cannot win by position.
                let score = FitScore.of(doc, track: track)
                if best == nil || score > best!.score {
                    best = (doc, score)
                }
                // A candidate that clearly matches this recording is taken
                // straight away, so the common case costs no extra requests.
                if FitScore.isGoodEnough(score) { break }
            } catch {
                // A transient failure is not evidence that the track has no
                // lyrics. Remembering it as a miss would blank the track until
                // the TTL expired, which looks like the app is broken.
                anyProviderFailed = true
                log.error("provider \(provider.id, privacy: .public) failed: \(error)")
            }
        }

        if let best {
            await cache.store(trackID: track.trackID, document: best.document)
            return best.document
        }

        if !anyProviderFailed {
            await cache.store(trackID: track.trackID, document: nil)
        }
        return nil
    }
}
