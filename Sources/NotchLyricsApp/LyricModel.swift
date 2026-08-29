import SwiftUI
import NotchLyricsCore

/// Drives the overlay at 60 Hz without rebuilding the hosting view each frame.
@MainActor
final class LyricModel: ObservableObject {
    @Published var line: LyricLine?
    @Published var time: TimeInterval = 0
    @Published var position: Position = .notch
    @Published var style: SweepStyle = .scale
    @Published var script: Script = .latin
    @Published var fontResolver: (Int) -> String? = { _ in nil }
}

struct LyricHost: View {
    @ObservedObject var model: LyricModel
    var body: some View {
        if model.script == .arabic {
            QuranView(line: model.line, time: model.time, fontName: model.fontResolver)
        } else {
            LyricView(line: model.line, time: model.time,
                      position: model.position, style: model.style)
        }
    }
}
