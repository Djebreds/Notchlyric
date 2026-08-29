import Foundation
import NotchLyricsCore

/// A player the app can follow. Emits nil when that player has nothing playing.
@MainActor
protocol PlaybackSource: AnyObject {
    var id: String { get }
    var onChange: ((PlaybackState?) -> Void)? { get set }
    func start()
    func stop()
}
