import SwiftUI
import NotchLyricsCore

/// Drives the overlay at 60 Hz without rebuilding the hosting view each frame.
@MainActor
final class LyricModel: ObservableObject {
    @Published var line: LyricLine?
    @Published var time: TimeInterval = 0
    @Published var position: Position = .notch
}

struct LyricHost: View {
    @ObservedObject var model: LyricModel
    var body: some View {
        LyricView(line: model.line, time: model.time, position: model.position)
    }
}
