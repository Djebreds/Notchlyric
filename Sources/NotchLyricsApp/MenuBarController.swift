import AppKit
import NotchLyricsCore

@MainActor
final class MenuBarController {
    private var statusItem: NSStatusItem!
    /// Invoked by the Re-sync Now menu item.
    var onResync: (() -> Void)?

    func install() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "music.note.list",
                                          accessibilityDescription: "NotchLyrics")
        rebuild()
    }

    private func rebuild() {
        let menu = NSMenu()

        let resync = NSMenuItem(title: "Re-sync Now", action: #selector(resyncNow), keyEquivalent: "r")
        resync.target = self
        menu.addItem(resync)
        menu.addItem(.separator())

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

        let styleHeader = NSMenuItem(title: "Lyric Style", action: nil, keyEquivalent: "")
        styleHeader.isEnabled = false
        menu.addItem(styleHeader)

        for s in SweepStyle.allCases {
            let mi = NSMenuItem(title: s.displayName,
                                action: #selector(selectStyle(_:)), keyEquivalent: "")
            mi.target = self
            mi.representedObject = s.rawValue
            mi.state = Settings.shared.sweepStyle == s ? .on : .off
            menu.addItem(mi)
        }

        menu.addItem(.separator())

        let romanize = NSMenuItem(title: "Romanize Japanese / Chinese / Korean",
                                  action: #selector(toggleRomanize), keyEquivalent: "")
        romanize.target = self
        romanize.state = Settings.shared.romanizeCJK ? .on : .off
        menu.addItem(romanize)

        let netease = NSMenuItem(title: "Use NetEase as fallback",
                                 action: #selector(toggleNetEase), keyEquivalent: "")
        netease.target = self
        netease.state = Settings.shared.netEaseEnabled ? .on : .off
        menu.addItem(netease)

        menu.addItem(.separator())

        let login = NSMenuItem(title: LoginItem.needsApproval
                                 ? "Launch at Login (approve in Settings)"
                                 : "Launch at Login",
                               action: #selector(toggleLoginItem), keyEquivalent: "")
        login.target = self
        login.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit NotchLyrics",
                                action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem.menu = menu
    }

    @objc private func resyncNow() {
        onResync?()
    }

    @objc private func selectPosition(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let p = Position(rawValue: raw) else { return }
        Settings.shared.position = p
        rebuild()
    }

    @objc private func selectStyle(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let s = SweepStyle(rawValue: raw) else { return }
        Settings.shared.sweepStyle = s
        rebuild()
    }

    @objc private func toggleRomanize() {
        Settings.shared.romanizeCJK.toggle()
        rebuild()
    }

    @objc private func toggleLoginItem() {
        LoginItem.setEnabled(!LoginItem.isEnabled)
        rebuild()
    }

    @objc private func toggleNetEase() {
        Settings.shared.netEaseEnabled.toggle()
        rebuild()
    }
}
