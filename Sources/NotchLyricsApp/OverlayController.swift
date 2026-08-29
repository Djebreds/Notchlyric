import AppKit
import SwiftUI
import NotchLyricsCore

@MainActor
final class OverlayController {
    private let bridge = SpotifyBridge()
    private let service: LyricsService
    private let model = LyricModel()
    private let window: OverlayWindow
    private var clock = PlaybackClock()

    private var currentTrackID: String?
    private var document: LyricsDocument?
    private var fetchTask: Task<Void, Never>?
    private var displayTimer: Timer?
    private var isPlaying = false

    init() {
        var providers: [any LyricsProvider] = [LRCLIBProvider(http: URLSessionHTTP())]
        if Settings.shared.netEaseEnabled {
            providers.append(NetEaseProvider(http: URLSessionHTTP()))
        }
        service = LyricsService(providers: providers,
                                cache: LyricsCache(directory: LyricsCache.defaultDirectory()))

        window = OverlayWindow(position: Settings.shared.position)
        model.position = Settings.shared.position
        window.setContent(LyricHost(model: model))
        window.reanchor(to: NSScreen.main)
    }

    func start() {
        bridge.onChange = { [weak self] in self?.ingest($0) }
        bridge.start()

        Settings.shared.onChange = { [weak self] in
            guard let self else { return }
            self.model.position = Settings.shared.position
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
            window.fadeOut()
            return
        }

        isPlaying = state.isPlaying
        clock.ingest(position: state.position, at: .now, isPlaying: state.isPlaying)

        guard state.trackID != currentTrackID else { return }
        currentTrackID = state.trackID
        document = nil

        fetchTask?.cancel()
        let query = state.query
        fetchTask = Task { [weak self] in
            guard let self else { return }
            let doc = await self.service.lyrics(for: query)
            // Discard results that arrived after the track already changed (spec §4).
            guard self.currentTrackID == query.trackID else { return }
            self.document = doc
        }
    }

    private func render() {
        guard isPlaying, let document else {
            model.line = nil
            window.fadeOut()
            return
        }
        let now = clock.position(at: .now)
        guard let idx = document.index(at: now), !document.lines[idx].isBlank else {
            model.line = nil
            window.fadeOut()
            return
        }
        model.line = document.lines[idx]
        model.time = now
        window.fadeIn()
    }
}
