import SwiftUI

struct UnsupportedView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title)
                .foregroundStyle(.orange)
            Text("Unsupported Hardware")
                .font(.headline)
            Text("WhatPort requires a Mac with Apple Silicon (M1 or later). Intel Macs use different USB-C controllers that this app cannot read.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .font(.caption)
        }
        .padding(20)
        .frame(width: 280)
    }
}
