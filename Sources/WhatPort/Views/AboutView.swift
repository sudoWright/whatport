import SwiftUI

// Standalone "About WhatPort" card, shown in its own small window from the
// menu-bar right-click menu. Mirrors the shape of a standard macOS About panel:
// icon, name, version, a one-line description, and links out.
struct AboutView: View {
    // URLs also used by the right-click menu's "WhatPort on GitHub" item.
    static let gitHubURL = URL(string: "https://github.com/darrylmorley/whatport")!
    static let websiteURL = URL(string: "https://whatport.app")!

    var body: some View {
        VStack(spacing: 12) {
            if let icon = Self.appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 72, height: 72)
            }

            VStack(spacing: 3) {
                Text("WhatPort")
                    .font(.title2.weight(.semibold))
                Text("Version \(appVersion) (\(buildNumber))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text("Real-time USB-C port status for your Mac.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Link("GitHub", destination: Self.gitHubURL)
                Link("Website", destination: Self.websiteURL)
            }
            .font(.body)

            Text("\u{00A9} 2026 WhatPort")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        .padding(24)
        .frame(width: 300)
    }

    private static var appIcon: NSImage? {
        if let url = Bundle.whatPortResources.url(forResource: "AppIcon", withExtension: "png") {
            return NSImage(contentsOf: url)
        }
        return NSApplication.shared.applicationIconImage
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }
}
