import Foundation
import ServiceManagement
import os

private let launchLog = Logger(subsystem: "app.whatport.whatport", category: "LaunchAtLogin")

// Manages the "Launch at Login" background item.
//
// Uses SMAppService.agent (a per-user LaunchAgent) rather than .mainApp, so
// launchd both starts WhatPort at login (RunAtLoad) and relaunches it within
// seconds if macOS terminates the menu-bar app under memory pressure
// (KeepAlive = { SuccessfulExit = false }). A deliberate user Quit exits cleanly
// (status 0) and is NOT relaunched. This is what keeps the Flight Recorder
// running overnight: a system kill becomes a few-second gap, not hours of
// silence. The bundled plist lives at
// Contents/Library/LaunchAgents/app.whatport.whatport.agent.plist.
enum LaunchAtLogin {
    static let agentPlistName = "app.whatport.whatport.agent.plist"

    private static var service: SMAppService {
        SMAppService.agent(plistName: agentPlistName)
    }

    static var isEnabled: Bool {
        service.status == .enabled
    }

    // Register or unregister the agent. Returns false if the operation failed, so
    // the caller can resync any UI toggle to the real state rather than show a
    // value that didn't take.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
            return true
        } catch {
            launchLog.error(
                "Launch-at-login \(enabled ? "register" : "unregister", privacy: .public) failed: \(error.localizedDescription, privacy: .public)"
            )
            return false
        }
    }

    // One-time upgrade: users who enabled the old SMAppService.mainApp login item
    // are moved to the keep-alive agent so the survival behaviour applies without
    // them re-toggling. The old item is unregistered first so we never leave two
    // registrations behind. No-op when the old item was never enabled.
    static func migrateFromMainAppIfNeeded() {
        guard SMAppService.mainApp.status == .enabled else { return }
        do {
            try SMAppService.mainApp.unregister()
        } catch {
            // If the old item won't unregister it's harmless (both point at the
            // same executable); we still register the agent below so the user
            // keeps launch-at-login.
            launchLog.error("Unregistering legacy login item failed: \(error.localizedDescription, privacy: .public)")
        }
        // Register the keep-alive agent unless it's already registered. Guarding
        // on isEnabled avoids a no-op re-register (and log noise) on every launch
        // in the rare case the legacy item keeps reporting .enabled after a failed
        // unregister, which would otherwise re-run this migration each time.
        if !isEnabled {
            setEnabled(true)
        }
    }
}
