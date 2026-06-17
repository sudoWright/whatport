import AppKit
import Combine
import SwiftUI
import WhatPortCore
import WhatPortIOKit
import WhatPortAppKit
import WhatPortPlugins

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var mainWindow: NSWindow?
    private var footerContext: FooterContext?
    private let portManager = PortManager()
    private let dataSource = LivePortDataSource()
    private var dataTask: Task<Void, Never>?
    private var isSupported = true
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let iconURL = Bundle.whatPortResources.url(forResource: "AppIcon", withExtension: "png"),
           let iconImage = NSImage(contentsOf: iconURL) {
            NSApplication.shared.applicationIconImage = iconImage
        }

        isSupported = HardwareCheck.isAppleSilicon()

        // Move any existing login-item users onto the keep-alive agent so the
        // overnight-survival behaviour applies without them re-toggling.
        LaunchAtLogin.migrateFromMainAppIfNeeded()

        // Register Pro plugins (no-op in the OSS build)
        bootstrapPlugins(registry: .shared)

        // Run plugin launch hooks (licence bootstrap, StoreKit, etc.)
        let registry = PluginRegistry.shared
        Task {
            for hook in registry.launchHooks {
                await hook()
            }
        }

        // Run plugin portManager hooks (attach recorder, observers, etc.)
        for hook in registry.portManagerHooks {
            hook(portManager)
        }

        if isSupported {
            startDataPipeline()
            registerForWake()
        }

        // Menu-bar vs window/Dock mode. The toggle in Settings writes
        // AppSettings.windowMode; we apply the current value now and live-switch
        // whenever it changes.
        applyDisplayMode(windowMode: AppSettings.shared.windowMode)

        AppSettings.shared.$windowMode
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] windowMode in
                self?.applyDisplayMode(windowMode: windowMode)
            }
            .store(in: &cancellables)
    }

    func applicationWillTerminate(_ notification: Notification) {
        dataTask?.cancel()
        dataSource.stop()

        // Run plugin teardown hooks
        for hook in PluginRegistry.shared.teardownHooks {
            hook()
        }
    }

    // In window mode, closing the last window quits like a normal app. In menu
    // bar mode there is no window, so this never fires. During a window -> menu
    // bar switch the setting is already false when the window closes, so the
    // teardown-close doesn't quit the app.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        AppSettings.shared.windowMode
    }

    // MARK: - Display mode

    private func applyDisplayMode(windowMode: Bool) {
        if windowMode {
            tearDownMenuBar()
            NSApp.setActivationPolicy(.regular)
            setUpWindow()
            NSApp.activate(ignoringOtherApps: true)
        } else {
            tearDownWindow()
            // Set the policy before creating the status item: creating it while
            // still .regular can place it incorrectly on some macOS versions.
            NSApp.setActivationPolicy(.accessory)
            setUpMenuBar()
        }
    }

    // One FooterContext, shared by whichever surface (popover or window) is up.
    private func makeFooterContext() -> FooterContext {
        if let footerContext { return footerContext }
        let context = FooterContext(portManager: portManager)
        context.dismissPopover = { [weak self] in
            self?.popover?.performClose(nil)
        }
        footerContext = context
        return context
    }

    @ViewBuilder
    private func surfaceContent() -> some View {
        if isSupported {
            PortListView(portManager: portManager, footerContext: makeFooterContext())
        } else {
            UnsupportedView()
        }
    }

    // MARK: - Menu bar mode

    private func setUpMenuBar() {
        if statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            if let button = item.button {
                if let iconURL = Bundle.whatPortResources.url(forResource: "MenuBarIcon", withExtension: "png") {
                    let image = NSImage(contentsOf: iconURL)
                    image?.isTemplate = true  // lets macOS handle light/dark mode
                    image?.size = NSSize(width: 18, height: 18)
                    button.image = image
                }
                button.imagePosition = .imageLeading
                button.action = #selector(togglePopover)
                button.target = self
            }
            statusItem = item
            updateBadge()
        }

        if popover == nil {
            let popover = NSPopover()
            popover.behavior = .transient
            popover.contentSize = NSSize(width: 320, height: 560)
            popover.contentViewController = NSHostingController(rootView: surfaceContent())
            self.popover = popover
        }
    }

    private func tearDownMenuBar() {
        if let popover, popover.isShown { popover.performClose(nil) }
        popover = nil
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItem = nil
    }

    // MARK: - Window mode

    private func setUpWindow() {
        if let mainWindow {
            mainWindow.makeKeyAndOrderFront(nil)
            return
        }

        let hosting = NSHostingController(rootView: surfaceContent())
        let window = NSWindow(contentViewController: hosting)
        window.title = "WhatPort"
        // Not .resizable: the content is a fixed-width (320pt) popover layout
        // that doesn't reflow, so a fixed-size window is intentional.
        window.styleMask = [.titled, .closable, .miniaturizable]
        // Don't deallocate on close: applicationShouldTerminateAfterLastWindowClosed
        // decides whether closing quits the app.
        window.isReleasedWhenClosed = false
        window.center()
        mainWindow = window
        window.makeKeyAndOrderFront(nil)
    }

    private func tearDownWindow() {
        mainWindow?.delegate = nil
        mainWindow?.close()
        mainWindow = nil
    }

    // MARK: - Data pipeline

    private func startDataPipeline() {
        let stream = dataSource.observePortUpdates()

        dataTask = Task {
            await dataSource.start()

            for await snapshot in stream {
                let managerSnapshot = SnapshotAdapter.convert(snapshot)
                portManager.applySnapshot(managerSnapshot)
                updateBadge()
            }
        }
    }

    private func updateBadge() {
        // No-op in window mode (no status item).
        guard let button = statusItem?.button else { return }
        let active = portManager.activePortCount
        let total = portManager.portCount

        if total > 0 {
            button.title = " \(active)/\(total)"
        } else {
            button.title = ""
        }
    }

    private func registerForWake() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.dataSource.handleWake()
        }
    }

    @objc private func togglePopover() {
        guard let popover, let button = statusItem?.button else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
