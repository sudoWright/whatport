import SwiftUI
import WhatPortAppKit

struct SettingsView: View {
    // Launch-at-Login is a keep-alive LaunchAgent (see LaunchAtLogin): it starts
    // WhatPort at login and relaunches it if macOS stops it to free memory, while
    // still honouring a clean Quit.
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    // Window mode runs WhatPort as a regular Dock app with a standard window,
    // instead of menu-bar-only. AppDelegate observes this setting and switches
    // live when it changes.
    @ObservedObject private var settings = AppSettings.shared

    // Font-size multiplier for every panel. The slider below writes here and the
    // panels read it through the fontScale environment, so text resizes live.
    @ObservedObject private var fontScale = FontScaleStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Settings
            VStack(alignment: .leading, spacing: 16) {
                Text("Settings")
                    .scaledFont(.title3, weight: .semibold)

                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Launch at Login", isOn: $launchAtLogin)
                        .toggleStyle(.switch)
                        .scaledFont(.body)
                        .onChange(of: launchAtLogin) { _, newValue in
                            setLaunchAtLogin(newValue)
                        }

                    Text("Keeps recording running, and restarts WhatPort if it's stopped unexpectedly (for example, when macOS quits it to free memory). A normal Quit still quits. Turn this off to stop it relaunching.")
                        .scaledFont(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Show in Dock", isOn: $settings.windowMode)
                        .toggleStyle(.switch)
                        .scaledFont(.body)

                    Text("Runs WhatPort as a normal app with a Dock icon and a window, instead of living in the menu bar. Closing the window quits the app.")
                        .scaledFont(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Font size")
                            .scaledFont(.body)
                        Spacer()
                        Text(verbatim: "\(Int((fontScale.fontSize * 100).rounded()))%")
                            .scaledFont(.body)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 8) {
                        Image(systemName: "textformat.size.smaller")
                            .scaledFont(.body)
                            .foregroundStyle(.secondary)
                        Slider(value: $fontScale.fontSize, in: FontScaleStore.range, step: 0.1)
                        Image(systemName: "textformat.size.larger")
                            .scaledFont(.body)
                            .foregroundStyle(.secondary)
                    }

                    Text("Resizes text across every panel. Useful on high-resolution displays where the default text feels small.")
                        .scaledFont(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            Spacer()

            // Plugin settings sections (license status, Flight Recorder data, etc.)
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
                    .scaledFont(.subheadline, weight: .medium)
                Text("Version \(appVersion)")
                    .scaledFont(.footnote)
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
        // Resync the toggle to the real state if register/unregister failed, so it
        // never shows a value that didn't take.
        if !LaunchAtLogin.setEnabled(enabled) {
            launchAtLogin = LaunchAtLogin.isEnabled
        }
    }
}
