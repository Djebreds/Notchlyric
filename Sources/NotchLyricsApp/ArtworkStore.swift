import AppKit

/// Loads and caches album art for the track being played.
///
/// Spotify supplies an https URL; Apple Music art is extracted to a file first,
/// so both arrive here as a URL string.
@MainActor
final class ArtworkStore {
    private var cache: [String: NSImage] = [:]
    private var inFlight: Set<String> = []
    private(set) var current: NSImage?

    /// Clears immediately so a new track never shows the previous one's art.
    func setTrack(artworkURL: String?) {
        current = nil
        guard let key = artworkURL, !key.isEmpty else { return }
        if let hit = cache[key] { current = hit; return }
        guard !inFlight.contains(key) else { return }
        inFlight.insert(key)
        Task { [weak self] in
            let image = await Self.load(key)
            guard let self else { return }
            self.inFlight.remove(key)
            guard let image else { return }
            self.cache[key] = image
            // Only apply if this is still the track we were asked about.
            if artworkURL == key { self.current = image }
        }
    }

    private static func load(_ urlString: String) async -> NSImage? {
        guard let url = URL(string: urlString) else { return nil }
        if url.isFileURL {
            return NSImage(contentsOf: url)
        }
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return NSImage(data: data)
    }
}
