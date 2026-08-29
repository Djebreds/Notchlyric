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
