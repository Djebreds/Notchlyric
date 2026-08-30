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

        var anyProviderFailed = false

        for provider in providers {
            do {
                if let doc = try await provider.fetch(track) {
                    await cache.store(trackID: track.trackID, document: doc)
                    return doc
                }
            } catch {
                // A transient failure is not evidence that the track has no
                // lyrics. Remembering it as a miss would blank the track until
                // the TTL expired, which looks like the app is broken.
                anyProviderFailed = true
                log.error("provider \(provider.id, privacy: .public) failed: \(error)")
            }
        }

        if !anyProviderFailed {
            await cache.store(trackID: track.trackID, document: nil)
        }
        return nil
    }
}
