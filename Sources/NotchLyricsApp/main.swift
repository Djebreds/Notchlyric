import AppKit
import NotchLyricsCore

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

@MainActor
final class ProbeDelegate: NSObject, NSApplicationDelegate {
    let bridge = SpotifyBridge()
    var ticks = 0
    func applicationDidFinishLaunching(_ n: Notification) {
        bridge.onChange = { [weak self] state in
            guard let self else { return }
            self.ticks += 1
            if let s = state {
                print("[\(self.ticks)] \(s.isPlaying ? "▶" : "❚❚") \(s.title) — \(s.artist) "
                    + "| \(String(format: "%.2f", s.position))/\(String(format: "%.2f", s.duration))s")
            } else {
                print("[\(self.ticks)] no playback")
            }
            if self.ticks >= 5 { NSApp.terminate(nil) }
        }
        bridge.start()
    }
}
let probeDelegate = ProbeDelegate()
app.delegate = probeDelegate
app.run()
