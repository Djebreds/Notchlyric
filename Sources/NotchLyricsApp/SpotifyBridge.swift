import Foundation
import AppKit
import NotchLyricsCore

/// Owns the compiled AppleScript and runs it off the main thread.
///
/// `@unchecked Sendable` is sound because every access to `script` happens on
/// the private serial queue.
private final class ScriptRunner: @unchecked Sendable {
    /// `duration` is milliseconds and `player position` is seconds (spec §1.2).
    private static let source = """
    tell application "Spotify"
      if it is not running then return "NOTRUNNING"
      set theState to (player state as text)
      if theState is "stopped" then return "STOPPED"
      set theTrack to current track
      return theState & "\t" & (id of theTrack) & "\t" & (name of theTrack) & "\t" ¬
        & (artist of theTrack) & "\t" & (album of theTrack) & "\t" ¬
        & (duration of theTrack) & "\t" & (player position)
    end tell
    """

    private let script: NSAppleScript?
    private let queue = DispatchQueue(label: "com.local.NotchLyrics.applescript")

    init() {
        script = NSAppleScript(source: Self.source)
        var err: NSDictionary?
        script?.compileAndReturnError(&err)   // pay the 251 ms cold cost once
        if let err { NSLog("NotchLyrics: AppleScript compile failed: \(err)") }
    }

    func run(_ completion: @escaping @Sendable (String?) -> Void) {
        queue.async { [weak self] in
            guard let script = self?.script else { return completion(nil) }
            var err: NSDictionary?
            let out = script.executeAndReturnError(&err).stringValue
            completion(err == nil ? out : nil)
        }
    }
}

/// Reads Spotify playback via AppleScript.
///
/// Spotify exposes no lyrics property (spec §1.2), so this supplies only track
/// identity and position; lyrics come from LyricsService.
@MainActor
final class SpotifyBridge: PlaybackSource {
    let id = "spotify"
    static let notificationName = Notification.Name("com.spotify.client.PlaybackStateChanged")

    var onChange: ((PlaybackState?) -> Void)?

    private let runner = ScriptRunner()
    private var timer: Timer?
    private var lastWasPlaying = false

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
        let t = Timer(timeInterval: interval, repeats: true) { _ in
            Task { @MainActor [weak self] in self?.poll() }
        }
        t.tolerance = interval * 0.2
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func poll() {
        runner.run { raw in
            Task { @MainActor [weak self] in self?.handle(raw: raw) }
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
        guard f.count == 7,
              let durationMs = Int(f[5].trimmingCharacters(in: .whitespaces)),
              let position = Double(f[6].trimmingCharacters(in: .whitespaces))
        else { return nil }
        return PlaybackState(trackID: f[1], title: f[2], artist: f[3], album: f[4],
                             durationMs: durationMs, position: position,
                             isPlaying: f[0] == "playing")
    }
}
