import SwiftUI
import WhatPortCore

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
    }
}
