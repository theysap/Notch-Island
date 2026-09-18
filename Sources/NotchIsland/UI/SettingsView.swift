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
    static var versionDescription: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "dev"
        let build = info?["CFBundleVersion"] as? String
        guard let build, build != short else { return short }
        return "\(short) (\(build))"
    }
}
