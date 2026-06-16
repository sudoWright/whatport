import Foundation
import WhatPortCore

// The production implementation of PortDataSource.
// Combines notification-driven state changes with timer-based power polling
// into a single AsyncStream of snapshots.
//
// AsyncStream is Swift's way to bridge callback-based or timer-based events
// into async/await code. You create one with a "continuation" that you yield
// values into. The consumer awaits values with `for await snapshot in stream`.
//
// Lifecycle:
// 1. start() opens the SMC connection and begins the poll timer + notifications
// 2. On notification (debounced): reads all state, yields a snapshot
// 3. On poll tick (pollInterval): reads all state, yields a snapshot
// 4. stop() cancels everything and closes the SMC connection
//
// Notifications give sub-second response to plug/unplug events.
// The poll timer catches everything else (power changes, transport
// state updates) and acts as a safety net for any missed notifications.
//
// @unchecked Sendable: we manage thread safety manually via the serial queue
// and nonisolated(unsafe) markers. The PortNotifier already dispatches on its
// own queue, and we access mutable state only from controlled contexts.

public final class LivePortDataSource: @unchecked Sendable, PortDataSource {
    // How often the poll timer reads state. Per-port power-OUT now comes from the
    // SMC, which updates ~1 Hz, so we poll at 1s to track the live draw (the old
    // PowerOutDetails source froze under load, making a faster poll pointless).
    private static let pollInterval: Duration = .seconds(1)

    private let notifier = PortNotifier()
    // One persisted SMC connection, opened in start() and closed in stop(),
    // reused for every snapshot instead of re-opening per poll. Its reads are
    // lock-guarded so the notifier callback and the poll task can share it.
    private let smc = SMCPowerReader()
    private nonisolated(unsafe) var pollTask: Task<Void, Never>?
    private nonisolated(unsafe) var continuation: AsyncStream<PortSnapshot>.Continuation?
    private nonisolated(unsafe) var isRunning = false

    public init() {}

    public func observePortUpdates() -> AsyncStream<PortSnapshot> {
        AsyncStream { continuation in
            self.continuation = continuation

            continuation.onTermination = { @Sendable _ in
                self.stop()
            }
        }
    }

    public func start() async {
        guard !isRunning else { return }
        isRunning = true

        // Open the shared SMC connection once for the session.
        smc.open()

        // Yield an initial snapshot immediately
        yieldSnapshot()

        // Start notification-driven updates
        notifier.start { [weak self] in
            self?.yieldSnapshot()
        }

        // Start polling (pollInterval). Reads all state, not just power.
        // Acts as a safety net alongside notifications and drives live power.
        startPollTimer()
    }

    // Call this from the app layer when the system wakes from sleep.
    // NSWorkspace.didWakeNotification lives in AppKit, so the app target
    // registers for it and calls this method.
    public func handleWake() {
        yieldSnapshot()
    }

    public func stop() {
        isRunning = false
        notifier.stop()
        pollTask?.cancel()
        pollTask = nil
        smc.close()
        continuation?.finish()
        continuation = nil
    }

    private func yieldSnapshot() {
        let snapshot = SnapshotReader.takeSnapshot(smc: smc)
        continuation?.yield(snapshot)
    }

    private func startPollTimer() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.pollInterval)
                guard !Task.isCancelled else { break }
                guard let self, self.isRunning else { break }
                self.yieldSnapshot()
            }
        }
    }
}
