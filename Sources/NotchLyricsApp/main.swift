import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // menu-bar only, no Dock icon

// One-shot setup so launch-at-login can be enabled without clicking the menu.
// Uses SMAppService, the same mechanism the menu toggle uses, so there is only
// ever one registration to reason about.
if CommandLine.arguments.contains("--enable-login-item") {
    let ok = MainActor.assumeIsolated { LoginItem.setEnabled(true) }
    let status = MainActor.assumeIsolated { LoginItem.statusDescription }
    print("login item: \(ok ? "registered" : "FAILED") — status: \(status)")
    exit(ok ? 0 : 1)
}
let delegate = AppDelegate()
app.delegate = delegate
app.run()
