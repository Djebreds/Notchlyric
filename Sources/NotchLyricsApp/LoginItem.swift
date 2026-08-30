import Foundation
import ServiceManagement

/// Registers the app to start at login.
///
/// `SMAppService.mainApp` registers the bundle itself, so macOS relaunches it
/// after a restart. The grant is per-bundle, and an ad-hoc signature changes on
/// every rebuild, so a rebuilt app may need re-enabling.
@MainActor
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// True when macOS is holding the request for the user to approve in
    /// System Settings rather than having applied it.
    static var needsApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            NSLog("NotchLyrics: login item \(enabled ? "register" : "unregister") failed: \(error)")
            return false
        }
    }

    static var statusDescription: String {
        switch SMAppService.mainApp.status {
        case .enabled:          "enabled"
        case .requiresApproval: "awaiting approval in System Settings"
        case .notFound:         "not registered"
        case .notRegistered:    "not registered"
        @unknown default:       "unknown"
        }
    }
}
