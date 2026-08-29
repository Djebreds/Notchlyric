import Foundation
import AppKit
import NotchLyricsCore

private final class MusicScriptRunner: @unchecked Sendable {
    /// Music.app reports duration in SECONDS; Spotify reports milliseconds.
    private static let source = """
    tell application "Music"
      if it is not running then return "NOTRUNNING"
      set s to (player state as text)
      if s is "stopped" then return "STOPPED"
      set t to current track
      set g to ""
      try
        set g to (genre of t)
      end try
      set tn to 0
      try
        set tn to (track number of t)
      end try
      set artPath to ""
      try
        if (count of artworks of t) > 0 then
          set aw to artwork 1 of t
          set artPath to (POSIX path of (path to temporary items)) & "nl-art-" & (persistent ID of t)
          set fh to open for access (POSIX file artPath) with write permission
          set eof fh to 0
          write (raw data of aw) to fh
          close access fh
        end if
      on error
        try
          close access (POSIX file artPath)
        end try
        set artPath to ""
      end try
      return s & "\t" & (persistent ID of t) & "\t" & (name of t) & "\t" ¬
        & (artist of t) & "\t" & (album of t) & "\t" & (duration of t) & "\t" ¬
        & (player position) & "\t" & tn & "\t" & g & "\t" & artPath
    end tell
    """

    private let script: NSAppleScript?
    private let queue = DispatchQueue(label: "com.local.NotchLyrics.music")

    init() {
        script = NSAppleScript(source: Self.source)
        var err: NSDictionary?
        script?.compileAndReturnError(&err)
        if let err { NSLog("NotchLyrics: Music AppleScript compile failed: \(err)") }
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

@MainActor
final class MusicBridge: PlaybackSource {
    let id = "music"
    static let notificationName = Notification.Name("com.apple.iTunes.playerInfo")

    var onChange: ((PlaybackState?) -> Void)?

    private let runner = MusicScriptRunner()
    private var timer: Timer?
    private var lastWasPlaying = false

    func start() {
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(changed), name: Self.notificationName, object: nil)
        schedule(interval: 1)
        poll()
    }

    func stop() {
        timer?.invalidate(); timer = nil
        DistributedNotificationCenter.default().removeObserver(self)
    }

    @objc private func changed() { poll() }

    private func schedule(interval: TimeInterval) {
        timer?.invalidate()
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        t.tolerance = interval * 0.2
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func poll() {
        runner.run { raw in
            Task { @MainActor [weak self] in self?.handle(raw) }
        }
    }

    private func handle(_ raw: String?) {
        let state = Self.parse(raw)
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
        guard f.count >= 9,
              let seconds = Double(f[5].trimmingCharacters(in: .whitespaces)),
              let position = Double(f[6].trimmingCharacters(in: .whitespaces))
        else { return nil }
        let track = Int(f[7].trimmingCharacters(in: .whitespaces))
        let genre = f[8].trimmingCharacters(in: .whitespaces)
        return PlaybackState(
            trackID: "music:" + f[1], title: f[2], artist: f[3], album: f[4],
            durationMs: Int((seconds * 1000).rounded()), position: position,
            isPlaying: f[0] == "playing",
            trackNumber: (track ?? 0) > 0 ? track : nil,
            genre: genre.isEmpty ? nil : genre,
            artworkURL: {
                guard f.count > 9 else { return nil }
                let p = f[9].trimmingCharacters(in: .whitespaces)
                return p.isEmpty ? nil : URL(fileURLWithPath: p).absoluteString
            }())
    }
}
