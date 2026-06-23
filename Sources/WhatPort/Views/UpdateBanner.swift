import SwiftUI
import WhatPortAppKit

// Shown at the top of the port list when a newer release is available. Drives
// the self-update flow (download, verify, swap) via Installer, falling back to
// the GitHub release page when the in-place update can't run here.
struct UpdateBanner: View {
    let update: AvailableUpdate
    @ObservedObject private var installer = Installer.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(.tint)
                Text("WhatPort \(update.version) available")
                    .scaledFont(.subheadline, weight: .semibold)
                Spacer()
            }

            content
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.tint.opacity(0.08))
    }

    @ViewBuilder
    private var content: some View {
        switch installer.state {
        case .idle:
            HStack(spacing: 10) {
                if update.downloadURL != nil {
                    Button("Update") { installer.install(update) }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
                Button("Release Notes") { NSWorkspace.shared.open(update.url) }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                Spacer()
            }
            .scaledFont(.footnote)

        case .downloading:
            progressRow("Downloading\u{2026}")
        case .verifying:
            progressRow("Verifying\u{2026}")
        case .installing:
            progressRow("Installing\u{2026}")

        case .failed(let message):
            VStack(alignment: .leading, spacing: 6) {
                Text("Update failed: \(message)")
                    .scaledFont(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    if update.downloadURL != nil {
                        Button("Retry") { installer.install(update) }
                            .controlSize(.small)
                    }
                    Button("Release Notes") { NSWorkspace.shared.open(update.url) }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                    Spacer()
                }
                .scaledFont(.footnote)
            }

        case .blocked(let message):
            VStack(alignment: .leading, spacing: 6) {
                Text(message)
                    .scaledFont(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Release Notes") { NSWorkspace.shared.open(update.url) }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .scaledFont(.footnote)
            }
        }
    }

    private func progressRow(_ label: String) -> some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(label)
                .scaledFont(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }
}
