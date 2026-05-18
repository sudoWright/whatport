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
// 1. start() registers IOKit notifications and begins the power poll timer
// 2. On notification (debounced): reads all state, yields a snapshot
// 3. On poll tick (3s): reads power only, yields a snapshot
// 4. stop() cancels everything
//
// @unchecked Sendable: we manage thread safety manually via the serial queue
// and nonisolated(unsafe) markers. The PortNotifier already dispatches on its
// own queue, and we access mutable state only from controlled contexts.

public final class LivePortDataSource: @unchecked Sendable, PortDataSource {
    private let notifier = PortNotifier()
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

        // Yield an initial snapshot immediately
        yieldSnapshot()

        // Start notification-driven updates
        notifier.start { [weak self] in
            self?.yieldSnapshot()
        }

        // Start power polling (3-second interval)
        startPowerPoll()
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
        continuation?.finish()
        continuation = nil
    }

    private func yieldSnapshot() {
        let snapshot = SnapshotReader.takeSnapshot()
        continuation?.yield(snapshot)
    }

    private func startPowerPoll() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { break }
                guard let self, self.isRunning else { break }
                self.yieldSnapshot()
            }
        }
    }
}
