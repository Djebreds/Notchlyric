import Foundation

public actor LyricsCache {
    public enum CacheHit: Equatable, Sendable {
        case found(LyricsDocument)
        case knownMissing
    }

    /// Bump whenever stored word timings or document shape change, so entries
    /// written by an older build are discarded instead of silently reused.
    public static let schemaVersion = 7

    private struct Entry: Codable {
        var document: LyricsDocument?
        var storedAt: Date
        var version: Int?
    }

    private let directory: URL
    private let negativeTTL: TimeInterval

    /// How long a "no lyrics" result stays valid.
    ///
    /// Kept short: these are community databases, so a track with no timed
    /// lyrics today may well have them tomorrow, and a stale miss is invisible
    /// to the user — it just looks like the app is broken.
    public static let defaultNegativeTTL: TimeInterval = 3600

    public init(directory: URL, negativeTTL: TimeInterval = LyricsCache.defaultNegativeTTL) {
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
              let entry = try? JSONDecoder().decode(Entry.self, from: data),
              entry.version == Self.schemaVersion
        else { return nil }

        if let doc = entry.document { return .found(doc) }
        guard Date().timeIntervalSince(entry.storedAt) < negativeTTL else { return nil }
        return .knownMissing
    }

    public func store(trackID: String, document: LyricsDocument?) {
        let entry = Entry(document: document, storedAt: Date(), version: Self.schemaVersion)
        guard let data = try? JSONEncoder().encode(entry) else { return }
        try? data.write(to: url(for: trackID), options: .atomic)
    }

    /// Forgets one track, so the next lookup asks the providers again.
    public func remove(trackID: String) {
        try? FileManager.default.removeItem(at: url(for: trackID))
    }

    private func url(for trackID: String) -> URL {
        let safe = trackID.map { $0.isLetter || $0.isNumber ? String($0) : "_" }.joined()
        return directory.appendingPathComponent("\(safe).json")
    }
}
