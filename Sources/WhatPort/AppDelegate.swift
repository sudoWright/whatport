import AppKit
import SwiftUI
import WhatPortCore
import WhatPortIOKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var settingsWindow: NSWindow?
    private let portManager = PortManager()
    private let dataSource = LivePortDataSource()
    private var dataTask: Task<Void, Never>?
    private var isSupported = true

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        if let iconURL = Bundle.module.url(forResource: "AppIcon", withExtension: "png"),
           let iconImage = NSImage(contentsOf: iconURL) {
            NSApplication.shared.applicationIconImage = iconImage
        }

        isSupported = HardwareCheck.isAppleSilicon()

        setupStatusItem()
        setupPopover()

        if isSupported {
            startDataPipeline()
            registerForWake()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        dataTask?.cancel()
        dataSource.stop()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        guard let button = statusItem?.button else { return }

        if let iconURL = Bundle.module.url(forResource: "MenuBarIcon", withExtension: "png") {
            let image = NSImage(contentsOf: iconURL)
            image?.isTemplate = true  // lets macOS handle light/dark mode
            image?.size = NSSize(width: 18, height: 18)
            button.image = image
        }
        button.imagePosition = .imageLeading
        button.action = #selector(togglePopover)
        button.target = self
    }

    private func setupPopover() {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 320, height: 200)

        if isSupported {
            popover.contentViewController = NSHostingController(
                rootView: PortListView(
                    portManager: portManager,
                    onSettings: { [weak self] in self?.showSettings() }
                )
            )
        } else {
            popover.contentViewController = NSHostingController(
                rootView: UnsupportedView()
            )
        }

        self.popover = popover
    }

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

    func showSettings() {
        // Close the popover so it doesn't overlap
        popover?.performClose(nil)

        if let existing = settingsWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 100),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "WhatPort Settings"
        window.contentViewController = NSHostingController(rootView: SettingsView())
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = window
    }

    @objc private func togglePopover() {
        guard let popover, let button = statusItem?.button else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
}
