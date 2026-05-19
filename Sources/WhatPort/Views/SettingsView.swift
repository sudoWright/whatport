import SwiftUI
import ServiceManagement
import WhatPortAppKit

struct SettingsView: View {
    // SMAppService.mainApp manages the "Launch at Login" state.
    // It uses the modern ServiceManagement framework (macOS 13+),
    // which is the Apple-recommended replacement for the older
    // SMLoginItemSetEnabled API. No helper app bundle needed.
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Settings
            VStack(alignment: .leading, spacing: 16) {
                Text("Settings")
                    .font(.title3.weight(.semibold))

                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .toggleStyle(.switch)
                    .font(.body)
                    .onChange(of: launchAtLogin) { _, newValue in
                        setLaunchAtLogin(newValue)
                    }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            Spacer()

            // Plugin settings sections (license status, dev override, etc.)
            ForEach(
                Array(PluginRegistry.shared.settingsSections.enumerated()),
                id: \.offset
            ) { _, builder in
                builder()
            }

            // About
            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("WhatPort")
                    .font(.subheadline.weight(.medium))
                Text("Version \(appVersion)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Reset toggle if the operation failed
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
