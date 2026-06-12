import Foundation
import IOKit

// Watches for IOKit state-change notifications on USB-C port services and
// signals "something changed" so the caller can re-read all state.
//
// Two complementary mechanisms, because a plug/unplug shows up in IOKit in
// more than one way:
//
// 1. Matching notifications (IOServiceAddMatchingNotification): fire when a
//    service APPEARS or is TERMINATED. A plug often brings up new transport
//    services (USB3 / DisplayPort / CIO) and a device; an unplug tears them
//    down. We treat any appear/terminate on a watched class as a change.
//
// 2. Interest notifications (IOServiceAddInterestNotification, kIOGeneral
//    interest): fire when an existing service's PROPERTIES change. The CC
//    service is persistent per port, so a cable plugged into an otherwise
//    empty port toggles its "Active" property without any service appearing.
//    We register interest on every watched service to catch that.
//
// Earlier this only watched IOPortTransportStateCC and only registered
// interest, so a plug that appeared as a new service (rather than a CC
// property change) was missed until the 3s poll, which read as intermittent
// "catch-up" lag. Watching the transport classes and signalling on
// appearance/termination closes that gap.
//
// All notifications are coalesced with a short debounce (a plug fires ~100
// notifications in a burst); the caller re-reads all state once things settle.

final class PortNotifier: @unchecked Sendable {
    // Classes whose appearance / termination / property changes indicate a
    // port state change. CC covers cable-only plugs into empty ports; the
    // transport classes cover links coming up when a device is connected.
    private static let watchedClasses = [
        "IOPortTransportStateCC",
        "IOPortTransportStateUSB3",
        "IOPortTransportStateDisplayPort",
        "IOPortTransportStateCIO",
    ]

    private var notifyPort: IONotificationPortRef?
    private var matchedIterators: [io_iterator_t] = []
    private var interestNotifications: [UInt64: io_object_t] = [:]
    private var onChange: (@Sendable () -> Void)?
    private let queue = DispatchQueue(label: "uk.whatport.notifier")
    private var debounceTask: Task<Void, Never>?
    // Suppresses the change signal during the initial arming drain, so we
    // don't fire a redundant re-read right after start() (the caller already
    // takes an initial snapshot).
    private var isArming = false

    func start(onChange: @escaping @Sendable () -> Void) {
        self.onChange = onChange

        let port = IONotificationPortCreate(kIOMainPortDefault)
        IONotificationPortSetDispatchQueue(port, queue)
        notifyPort = port

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        let matchCallback: IOServiceMatchingCallback = { refcon, iter in
            guard let refcon else { return }
            let notifier = Unmanaged<PortNotifier>.fromOpaque(refcon).takeUnretainedValue()
            notifier.handleMatched(iter)
        }

        let terminateCallback: IOServiceMatchingCallback = { refcon, iter in
            guard let refcon else { return }
            let notifier = Unmanaged<PortNotifier>.fromOpaque(refcon).takeUnretainedValue()
            notifier.handleTerminated(iter)
        }

        isArming = true
        for className in Self.watchedClasses {
            // Watch services appearing.
            var appearIter: io_iterator_t = 0
            if IOServiceAddMatchingNotification(
                port, kIOMatchedNotification, IOServiceMatching(className),
                matchCallback, selfPtr, &appearIter
            ) == KERN_SUCCESS {
                matchedIterators.append(appearIter)
                handleMatched(appearIter)  // drain to arm + register interest
            }

            // Watch services terminating (unplug).
            var termIter: io_iterator_t = 0
            if IOServiceAddMatchingNotification(
                port, kIOTerminatedNotification, IOServiceMatching(className),
                terminateCallback, selfPtr, &termIter
            ) == KERN_SUCCESS {
                matchedIterators.append(termIter)
                handleTerminated(termIter)  // arm
            }
        }
        isArming = false
    }

    func stop() {
        debounceTask?.cancel()
        debounceTask = nil

        for (_, notification) in interestNotifications {
            IOObjectRelease(notification)
        }
        interestNotifications.removeAll()

        for iter in matchedIterators {
            IOObjectRelease(iter)
        }
        matchedIterators.removeAll()

        if let port = notifyPort {
            IONotificationPortDestroy(port)
            notifyPort = nil
        }

        onChange = nil
    }

    // A watched service appeared (or, during start, already exists). Register
    // interest on it for future property changes, and signal a change unless
    // we're still arming.
    private func handleMatched(_ iter: io_iterator_t) {
        var sawService = false
        while case let service = IOIteratorNext(iter), service != 0 {
            registerInterest(for: service)
            IOObjectRelease(service)
            sawService = true
        }
        if sawService && !isArming {
            scheduleDebounce()
        }
    }

    // A watched service terminated (unplug). Release its interest notification
    // so the table doesn't accumulate stale entries across plug cycles, and
    // signal a change.
    private func handleTerminated(_ iter: io_iterator_t) {
        var sawService = false
        while case let service = IOIteratorNext(iter), service != 0 {
            var entryID: UInt64 = 0
            IORegistryEntryGetRegistryEntryID(service, &entryID)
            if let notification = interestNotifications.removeValue(forKey: entryID) {
                IOObjectRelease(notification)
            }
            IOObjectRelease(service)
            sawService = true
        }
        if sawService && !isArming {
            scheduleDebounce()
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
    // A plug event fires ~100 notifications in quick succession.
    // We wait 80ms after the last one before signalling.
    private func scheduleDebounce() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled else { return }
            self?.onChange?()
        }
    }
}
