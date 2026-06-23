import SwiftUI
import WhatPortCore

// Posted when the user invokes Settings (Cmd+, or the menu item). AppDelegate
// listens and opens our in-popover/in-window settings panel.
extension Notification.Name {
    static let openSettingsRequested = Notification.Name("openSettingsRequested")
}

// @main marks this as the app's entry point.
// The App protocol is SwiftUI's top-level container.
@main
struct WhatPortApp: App {
    // @NSApplicationDelegateAdaptor bridges AppKit's AppDelegate pattern
    // into SwiftUI. We need it because NSStatusItem (the menu bar icon)
    // is an AppKit API with no SwiftUI equivalent.
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // We don't use a window - the UI lives in the menu bar popover.
        // Settings scene is required but empty for now.
        Settings { EmptyView() }
            .commands {
                // Replace SwiftUI's default Settings item (which would open the
                // empty Settings scene above) with one that opens our own
                // settings panel, keeping the standard Cmd+, shortcut. Quit
                // (Cmd+Q) is left as SwiftUI's standard menu item.
                CommandGroup(replacing: .appSettings) {
                    Button("Settings\u{2026}") {
                        NotificationCenter.default.post(name: .openSettingsRequested, object: nil)
                    }
                    .keyboardShortcut(",", modifiers: .command)
                }
                // Manual update check. This app menu only shows in window/Dock
                // mode; in menu-bar mode the same action lives on the status
                // item's right-click menu (AppDelegate), so both modes can
                // trigger a check.
                CommandGroup(after: .appInfo) {
                    Button("Check for Updates\u{2026}") {
                        UpdateChecker.shared.check(silent: false)
                    }
                }
            }
    }
}
