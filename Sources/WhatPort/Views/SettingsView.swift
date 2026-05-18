import SwiftUI
import ServiceManagement

struct SettingsView: View {
    // SMAppService.mainApp manages the "Launch at Login" state.
    // It uses the modern ServiceManagement framework (macOS 13+),
    // which is the Apple-recommended replacement for the older
    // SMLoginItemSetEnabled API. No helper app bundle needed.
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Toggle("Launch at Login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, newValue in
                    setLaunchAtLogin(newValue)
                }
        }
        .formStyle(.grouped)
        .frame(width: 280)
        .padding(14)
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
