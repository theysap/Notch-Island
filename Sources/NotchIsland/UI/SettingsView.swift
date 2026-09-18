import SwiftUI

struct SettingsView: View {
    @Bindable var settings: AppSettings

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
                LabeledContent("Version", value: AppInfo.versionDescription)
                LabeledContent("Model", value: MacModel.identifier)
            }
        }
        .formStyle(.grouped)
        .frame(width: 380)
        .scenePadding()
        .fixedSize()
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
