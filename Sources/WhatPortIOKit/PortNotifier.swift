import Foundation
import IOKit

// Watches for IOKit state-change notifications on USB-C port services.
//
// We register kIOGeneralInterest on IOPortTransportStateCC services.
// When a cable is plugged/unplugged, the kernel fires ~113 notifications.
// We coalesce these into a single "something changed" signal using a short
// debounce (0.1s). The caller re-reads all state on that signal.
//
// Key IOKit concepts used here:
//
// IONotificationPortRef: a port that receives IOKit messages. We set a
// dispatch queue on it so callbacks fire on that queue (not the run loop).
//
// IOServiceAddMatchingNotification: fires when a service APPEARS or
// DISAPPEARS. We use this to find IOPortTransportStateCC services.
//
// IOServiceAddInterestNotification: fires when a service's PROPERTIES
// change. We register this on each IOPortTransportStateCC to detect
// plug/unplug state changes.
//
// Unmanaged<T>: IOKit callbacks are C functions that receive a void pointer
// (refcon). We pass a pointer to `self` through Unmanaged so the C callback
// can call back into Swift. passUnretained/takeUnretainedValue means we
// don't change the retain count (the object is kept alive by the caller).

final class PortNotifier: @unchecked Sendable {
    private var notifyPort: IONotificationPortRef?
    private var matchedIterator: io_iterator_t = 0
    private var interestNotifications: [UInt64: io_object_t] = [:]
    private var onChange: (@Sendable () -> Void)?
    private let queue = DispatchQueue(label: "uk.whatport.notifier")
    private var debounceTask: Task<Void, Never>?

    func start(onChange: @escaping @Sendable () -> Void) {
        self.onChange = onChange

        let port = IONotificationPortCreate(kIOMainPortDefault)
        IONotificationPortSetDispatchQueue(port, queue)
        notifyPort = port

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        // Watch for IOPortTransportStateCC services appearing
        let matchCallback: IOServiceMatchingCallback = { refcon, iter in
            guard let refcon else { return }
            let notifier = Unmanaged<PortNotifier>.fromOpaque(refcon).takeUnretainedValue()
            notifier.handleMatched(iter)
        }

        var iter: io_iterator_t = 0
        let matching = IOServiceMatching("IOPortTransportStateCC")
        let kr = IOServiceAddMatchingNotification(
            port,
            kIOMatchedNotification,
            matching,
            matchCallback,
            selfPtr,
            &iter
        )

        if kr == KERN_SUCCESS {
            matchedIterator = iter
            // Drain the iterator to arm it (IOKit requirement) and register
            // interest on existing services
            handleMatched(iter)
        }
    }

    func stop() {
        debounceTask?.cancel()
        debounceTask = nil

        for (_, notification) in interestNotifications {
            IOObjectRelease(notification)
        }
        interestNotifications.removeAll()

        if matchedIterator != 0 {
            IOObjectRelease(matchedIterator)
            matchedIterator = 0
        }

        if let port = notifyPort {
            IONotificationPortDestroy(port)
            notifyPort = nil
        }

        onChange = nil
    }

    // Called when IOPortTransportStateCC services appear.
    // We must drain the iterator (IOKit won't fire again until drained)
    // and register interest notifications on each service.
    private func handleMatched(_ iter: io_iterator_t) {
        while case let service = IOIteratorNext(iter), service != 0 {
            registerInterest(for: service)
            IOObjectRelease(service)
        }
    }

    private func registerInterest(for service: io_service_t) {
        guard let notifyPort else { return }

        var entryID: UInt64 = 0
        IORegistryEntryGetRegistryEntryID(service, &entryID)
        guard interestNotifications[entryID] == nil else { return }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        let interestCallback: IOServiceInterestCallback = { refcon, _, _, _ in
            guard let refcon else { return }
            let notifier = Unmanaged<PortNotifier>.fromOpaque(refcon).takeUnretainedValue()
            notifier.scheduleDebounce()
        }

        var notification: io_object_t = 0
        let kr = IOServiceAddInterestNotification(
            notifyPort,
            service,
            kIOGeneralInterest,
            interestCallback,
            selfPtr,
            &notification
        )

        if kr == KERN_SUCCESS {
            interestNotifications[entryID] = notification
        }
    }

    // Coalesce rapid-fire notifications into a single callback.
    // A plug event fires ~113 notifications in quick succession.
    // We wait 100ms after the last one before signaling.
    private func scheduleDebounce() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
            self?.onChange?()
        }
    }
}
