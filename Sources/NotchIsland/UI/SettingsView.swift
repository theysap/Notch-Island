import SwiftUI

struct SettingsView: View {
    @Bindable var settings: AppSettings
    let updates: UpdateChecker

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
                Toggle("Show menu bar icon", isOn: $settings.showsMenuBarIcon)
            }

            Section {
                Toggle("Hide the island while paused", isOn: $settings.hidesWhenPaused)
            } footer: {
                Text("When off, the island stays in place with playback paused.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle(
                    "Check for updates automatically",
                    isOn: $settings.checksForUpdatesAutomatically)
            } footer: {
                Text(
                    """
                    Looks for a new release on GitHub when the app starts and \
                    every few hours after. Nothing is downloaded until you ask \
                    for it, and an update that does not match the checksum \
                    published with it is discarded.
                    """
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Version", value: AppInfo.versionDescription)
                LabeledContent("Model", value: MacModel.identifier)
                LabeledContent("Updates") {
                    updateStatus
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 380)
        .scenePadding()
        .fixedSize()
    }

    @ViewBuilder
    private var updateStatus: some View {
        switch updates.state {
        case .available(let release):
            Button("Install \(release.version.description)") {
                updates.installAvailableUpdate()
            }
            .disabled(!updates.canInstall)

        case .checking:
            Text("Checking…").foregroundStyle(.secondary)

        case .downloading(let fraction):
            Text("Downloading \(Int(fraction * 100))%").foregroundStyle(.secondary)

        case .installing:
            Text("Installing…").foregroundStyle(.secondary)

        case .upToDate:
            Text("Up to date").foregroundStyle(.secondary)

        case .failed(let message):
            Text(message).foregroundStyle(.secondary).lineLimit(2)

        case .idle:
            Button("Check Now") {
                Task { await updates.check(userInitiated: true) }
            }
        }
    }
}

enum AppInfo {
    /// The released version, and only that.
    ///
    /// The bundle also carries a build number derived from the commit count,
    /// because macOS wants one that always increases. It is not shown: a
    /// build is not something anyone can download, and a number that moves
    /// with every commit only invites the question of which one you have.
    /// Releases are what exist, so releases are what is displayed.
    static var versionDescription: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }
}
