import AppKit
import SwiftUI
import NotchLyricsCore

@MainActor
final class OverlayController {
    private let sources: [any PlaybackSource] = [SpotifyBridge(), MusicBridge()]
    private var arbiter = SourceArbiter()
    private let service: LyricsService
    private let model = LyricModel()
    private let window: OverlayWindow
    private var clock = PlaybackClock()

    private var currentTrackID: String?
    private var document: LyricsDocument?
    private var fetchTask: Task<Void, Never>?
    private var displayTimer: Timer?
    private var isPlaying = false
    private var isFetching = false
    private let fonts = QCFFontStore()
    private let artwork = ArtworkStore()

    init() {
        var providers: [any LyricsProvider] = [
            QuranProvider(http: URLSessionHTTP()),
            LRCLIBProvider(http: URLSessionHTTP()),
        ]
        if Settings.shared.netEaseEnabled {
            providers.append(NetEaseProvider(http: URLSessionHTTP()))
        }
        service = LyricsService(providers: providers,
                                cache: LyricsCache(directory: LyricsCache.defaultDirectory()))

        window = OverlayWindow(position: Settings.shared.position)
        model.position = Settings.shared.position
        model.style = Settings.shared.sweepStyle
        model.romanize = Settings.shared.romanizeCJK
        model.fontResolver = { [fonts] page in fonts.fontName(forPage: page) }
        window.setContent(LyricHost(model: model))
        window.reanchor(to: NSScreen.main)
    }

    func start() {
        for source in sources {
            let sourceID = source.id
            source.onChange = { [weak self] state in
                guard let self else { return }
                switch self.arbiter.update(sourceID: sourceID, state: state, at: .now) {
                case .update(let fresh): self.ingest(fresh)
                case .hide:              self.ingest(nil)
                case .unchanged:         break
                }
            }
            source.start()
        }

        Settings.shared.onChange = { [weak self] in
            guard let self else { return }
            self.model.position = Settings.shared.position
            self.model.style = Settings.shared.sweepStyle
            self.model.romanize = Settings.shared.romanizeCJK
            self.window.setPosition(Settings.shared.position, screen: NSScreen.main)
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.window.reanchor(to: NSScreen.main) }
            }

        let t = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.render() }
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
            isFetching = false
            model.line = nil
            window.setState(.hidden)
            return
        }

        isPlaying = state.isPlaying
        clock.ingest(position: state.position, at: .now, isPlaying: state.isPlaying)

        guard state.trackID != currentTrackID else { return }
        currentTrackID = state.trackID
        artwork.setTrack(artworkURL: state.artworkURL)
        document = nil
        model.line = nil
        isFetching = true

        fetchTask?.cancel()
        let query = state.query
        fetchTask = Task { [weak self] in
            guard let self else { return }
            let doc = await self.service.lyrics(for: query)
            // Discard results that arrived after the track already changed (spec §4).
            guard self.currentTrackID == query.trackID else { return }
            if let doc, doc.script == .arabic {
                let pages = Set(doc.lines.flatMap { $0.words.compactMap(\.fontPage) })
                await self.fonts.prefetch(pages: pages)
                guard self.currentTrackID == query.trackID else { return }
            }
            self.model.script = doc?.script ?? .latin
            self.window.script = doc?.script ?? .latin
            self.window.reanchor(to: NSScreen.main)
            self.document = doc
            self.isFetching = false
        }
    }

    private func render() {
        window.setHovered(window.containsCursor())

        guard isPlaying else {
            window.setState(.hidden)
            return
        }
        guard let document else {
            // Mid-fetch after a track change: hold the panel dimmed rather than
            // blinking it out. Once a fetch finishes with nothing, hide.
            model.isIdle = true
            model.artwork = artwork.current
            window.setState(isFetching || artwork.current != nil ? .idle : .hidden)
            return
        }
        let now = clock.position(at: .now)
        guard let idx = document.index(at: now), !document.lines[idx].isBlank else {
            // Instrumental break: album art if we have it, else the last line.
            model.isIdle = true
            model.artwork = artwork.current
            window.setState(.idle)
            return
        }
        model.isIdle = false
        model.line = document.lines[idx]
        model.time = now
        window.setState(.active)
    }
}
