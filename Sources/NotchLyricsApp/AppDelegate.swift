import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let overlay = OverlayController()
    private let menuBar = MenuBarController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBar.install()
        overlay.start()
    }
}
