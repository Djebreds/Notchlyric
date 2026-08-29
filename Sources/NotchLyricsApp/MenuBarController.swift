import AppKit
import NotchLyricsCore

@MainActor
final class MenuBarController {
    private var statusItem: NSStatusItem!

    func install() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "music.note.list",
                                          accessibilityDescription: "NotchLyrics")
        rebuild()
    }

    private func rebuild() {
        let menu = NSMenu()

        let header = NSMenuItem(title: "Position", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        for p in Position.allCases {
            let mi = NSMenuItem(title: p.displayName,
                                action: #selector(selectPosition(_:)), keyEquivalent: "")
            mi.target = self
            mi.representedObject = p.rawValue
            mi.state = Settings.shared.position == p ? .on : .off
            menu.addItem(mi)
        }

        menu.addItem(.separator())

        let netease = NSMenuItem(title: "Use NetEase as fallback",
                                 action: #selector(toggleNetEase), keyEquivalent: "")
        netease.target = self
        netease.state = Settings.shared.netEaseEnabled ? .on : .off
        menu.addItem(netease)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit NotchLyrics",
                                action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem.menu = menu
    }

    @objc private func selectPosition(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let p = Position(rawValue: raw) else { return }
        Settings.shared.position = p
        rebuild()
    }

    @objc private func toggleNetEase() {
        Settings.shared.netEaseEnabled.toggle()
        rebuild()
    }
}
