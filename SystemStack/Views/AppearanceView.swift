import SwiftUI

struct AppearanceView: View {
    @EnvironmentObject private var appState: AppState

    private var displayModeBinding: Binding<AppState.DisplayMode> {
        Binding(
            get: { appState.appearanceSettings.displayMode },
            set: {
                var settings = appState.appearanceSettings
                settings.displayMode = $0
                appState.appearanceSettings = settings
            }
        )
    }

    private var separatorBinding: Binding<AppState.SeparatorStyle> {
        Binding(
            get: { appState.appearanceSettings.separator },
            set: {
                var settings = appState.appearanceSettings
                settings.separator = $0
                appState.appearanceSettings = settings
            }
        )
    }

    private var spacingBinding: Binding<AppState.SpacingMode> {
        Binding(
            get: { appState.appearanceSettings.spacing },
            set: {
                var settings = appState.appearanceSettings
                settings.spacing = $0
                appState.appearanceSettings = settings
            }
        )
    }

    var body: some View {
        Form {
            Section("Menu Bar Style") {
                Picker("Display Mode", selection: displayModeBinding) {
                    ForEach(AppState.DisplayMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Separator", selection: separatorBinding) {
                    ForEach(AppState.SeparatorStyle.allCases) { separator in
                        Text(separator.rawValue).tag(separator)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Spacing", selection: spacingBinding) {
                    ForEach(AppState.SpacingMode.allCases) { spacing in
                        Text(spacing.rawValue).tag(spacing)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Preview") {
                Text(appState.plainStatusPreviewText())
                    .font(.system(.body, design: .monospaced))
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Appearance")
    }
}
