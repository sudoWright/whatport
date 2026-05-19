import SwiftUI
import WhatPortCore

// Context passed to plugin footer button builders.
//
// Gives buttons access to navigation (show a panel in the popover)
// and the popover dismissal callback (so opening a window can close
// the popover first).
//
// @Observable so SwiftUI views automatically re-render when
// showingPanelIndex changes.

@MainActor
@Observable
public final class FooterContext {
    public let portManager: PortManager

    // Dismiss the popover (set by AppDelegate)
    public var dismissPopover: (() -> Void)?

    // When non-nil, PortListView shows the panel at this index
    // instead of the port list. Set by plugin buttons.
    public var showingPanelIndex: Int?

    public init(portManager: PortManager) {
        self.portManager = portManager
    }

    // Convenience for plugins to show a panel
    public func showPanel(_ index: Int) {
        showingPanelIndex = index
    }

    // Convenience to dismiss back to the port list
    public func dismissPanel() {
        showingPanelIndex = nil
    }
}
