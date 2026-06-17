import Combine
import Foundation

// User preferences persisted in UserDefaults. The toggle in Settings binds to a
// @Published property here; AppDelegate subscribes to changes via Combine so
// flipping a toggle live-switches behaviour. This mirrors WhatCable's AppSettings
// pattern, which is what makes the menu-bar/window switch reliable: the setting
// is the single source of truth and the delegate reacts to it, rather than a
// view reaching into the delegate.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private enum Keys {
        static let windowMode = "app.whatport.windowMode"
    }

    // When true, WhatPort runs as a regular Dock app with a window. When false
    // (the default), it lives only in the menu bar.
    @Published var windowMode: Bool {
        didSet {
            guard windowMode != oldValue else { return }
            UserDefaults.standard.set(windowMode, forKey: Keys.windowMode)
        }
    }

    private init() {
        // Absent key -> menu-bar mode. Explicit so the default doesn't silently
        // ride on bool(forKey:) returning false for a missing key.
        windowMode = UserDefaults.standard.object(forKey: Keys.windowMode) as? Bool ?? false
    }
}
