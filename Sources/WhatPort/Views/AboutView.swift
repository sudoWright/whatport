import SwiftUI
import WhatPortAppKit

// Standalone "About WhatPort" card, shown in its own small window from the
// menu-bar right-click menu. Mirrors the shape of a standard macOS About panel:
// icon, name, version, a one-line description, and links out.
struct AboutView: View {
    // URLs also used by the right-click menu's "WhatPort on GitHub" item.
    static let gitHubURL = URL(string: "https://github.com/darrylmorley/whatport")!
    static let websiteURL = URL(string: "https://whatport.app")!

    // Its own window, so it injects the font scale itself rather than inheriting
    // it from the popover tree.
    @ObservedObject private var fontScale = FontScaleStore.shared

    var body: some View {
        VStack(spacing: 12) {
            if let icon = Self.appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 72, height: 72)
            }

            VStack(spacing: 3) {
                Text("WhatPort")
                    .scaledFont(.title2, weight: .semibold)
                Text("Version \(appVersion) (\(buildNumber))")
                    .scaledFont(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text("Real-time USB-C port status for your Mac.")
                .scaledFont(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Link("GitHub", destination: Self.gitHubURL)
                Link("Website", destination: Self.websiteURL)
            }
            .scaledFont(.body)

            Text("\u{00A9} 2026 WhatPort")
                .scaledFont(.footnote)
                .foregroundStyle(.tertiary)
        }
        .padding(24)
        .frame(width: 300)
        .environment(\.fontScale, fontScale.fontSize)
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
