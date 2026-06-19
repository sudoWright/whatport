import SwiftUI
import WhatPortAppKit

struct UnsupportedView: View {
    @ObservedObject private var fontScale = FontScaleStore.shared

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .scaledFont(.title)
                .foregroundStyle(.orange)
            Text("Unsupported Hardware")
                .scaledFont(.headline)
            Text("WhatPort requires a Mac with Apple Silicon (M1 or later). Intel Macs use different USB-C controllers that this app cannot read.")
                .scaledFont(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .scaledFont(.caption)
        }
        .padding(20)
        .frame(width: 280)
        .environment(\.fontScale, fontScale.fontSize)
    }
}
