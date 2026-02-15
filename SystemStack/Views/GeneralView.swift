import SwiftUI

struct GeneralView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch at Login", isOn: $appState.launchAtLogin)
                Text("Placeholder only in this phase.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Configuration") {
                Button("Reset to Defaults") {
                    appState.resetToDefaults()
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("General")
    }
}
