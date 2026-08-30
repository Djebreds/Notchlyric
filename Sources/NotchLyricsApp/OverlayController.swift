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
    /// Set by a manual re-sync so the next fetch bypasses the cache.
    private var forceRefresh = false
    private var renderedLineStart: TimeInterval?
    private let fonts = QCFFontStore()

    init() {
        // Quran, then NetEase, LRCLIB, lrcmux, with Kugou last.
        var providers: [any LyricsProvider] = [QuranProvider(http: URLSessionHTTP())]
        if Settings.shared.netEaseEnabled {
            providers.append(NetEaseProvider(http: URLSessionHTTP()))
        }
        // LRCLIB ahead of lrcmux: its entries are more often timed against the
        // master actually being played, and correct alignment beats lrcmux's
        // measured-but-differently-timed words.
        providers.append(LRCLIBProvider(http: URLSessionHTTP()))
        providers.append(LrcmuxProvider(http: URLSessionHTTP()))
        if Settings.shared.netEaseEnabled {
            providers.append(KugouProvider(http: URLSessionHTTP()))
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

    /// Manual re-sync: discard drift, forget what we cached for this track, and
    /// ask the player and the providers again from scratch.
    ///
    /// Covers both ways this goes wrong — a clock that has drifted, and a
    /// document that is missing or belongs to the wrong recording.
    func resync() {
        clock.reset()
        renderedLineStart = nil
        model.line = nil
        document = nil
        isFetching = true
        forceRefresh = true

        let trackID = currentTrackID
        currentTrackID = nil          // force the next state to look like a new track
        fetchTask?.cancel()

        for source in sources { source.stop(); source.start() }   // re-poll immediately

        if let trackID {
            Task { [weak self] in
                await self?.service.forget(trackID: trackID)
            }
        }
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
        document = nil
        model.line = nil
        isFetching = true

        fetchTask?.cancel()
        let query = state.query
        fetchTask = Task { [weak self] in
            guard let self else { return }
            let doc = await self.service.lyrics(for: query, refresh: self.forceRefresh)
            // Discard results that arrived after the track already changed (spec §4).
            guard self.currentTrackID == query.trackID else { return }
            self.model.script = doc?.script ?? .latin
            self.window.script = doc?.script ?? .latin
            self.window.reanchor(to: NSScreen.main)
            self.document = doc
            self.isFetching = false
            self.forceRefresh = false

            // Fonts load behind the lyrics, not in front of them. A long surah
            // needs dozens of page fonts (48 for al-Baqarah); waiting for all of
            // them before showing anything leaves the overlay stuck on the idle
            // note. Words render in the system Arabic face until their page
            // font registers, and the 60 Hz redraw picks it up automatically.
            if let doc, doc.script == .arabic {
                let pages = Set(doc.lines.flatMap { $0.words.compactMap(\.fontPage) })
                Task { [weak self] in await self?.fonts.prefetch(pages: pages) }
            }
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
            window.setState(isFetching ? .idle : .hidden)
            return
        }
        let now = SyncOffset.apply(clock.position(at: .now), offset: Settings.shared.syncOffset)
        guard let idx = document.index(at: now), !document.lines[idx].isBlank else {
            // Instrumental break: a neutral note, not the sentence that ended.
            model.isIdle = true
            window.setState(.idle)
            return
        }
        model.isIdle = false
        // Assigning an unchanged line would invalidate the whole view tree
        // 60 times a second; only the time actually needs to move.
        let line = document.lines[idx]
        if renderedLineStart != line.start {
            renderedLineStart = line.start
            model.line = line
        }
        model.time = now
        window.setState(.active)
    }
}
