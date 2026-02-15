import SwiftUI

struct ModulesView: View {
    @EnvironmentObject private var appState: AppState
    @State private var searchText = ""
    @State private var expandedModuleIDs: Set<String> = []

    var body: some View {
        VStack(spacing: 10) {
            TextField("Search Modules", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 12)
                .padding(.top, 12)

            List {
                ForEach(appState.modules(matching: searchText), id: \.id) { module in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            Button {
                                toggleExpanded(module.id)
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: module.symbolName ?? "questionmark.square")
                                        .foregroundStyle(.secondary)
                                        .frame(width: 16)

                                    Text(module.title)
                                        .foregroundStyle(.primary)
                                }
                            }
                            .buttonStyle(.plain)

                            Spacer()

                            Toggle("", isOn: Binding(
                                get: { module.isEnabled },
                                set: { appState.setModuleEnabled(id: module.id, isEnabled: $0) }
                            ))
                            .labelsHidden()
                        }

                        if expandedModuleIDs.contains(module.id) {
                            inlineSettingsView(for: module)
                                .padding(.leading, 26)
                                .padding(.bottom, 4)
                        }
                    }
                    .padding(.vertical, 3)
                }
            }
            .listStyle(.inset)
        }
        .navigationTitle("Modules")
    }

    private func toggleExpanded(_ id: String) {
        if expandedModuleIDs.contains(id) {
            expandedModuleIDs.remove(id)
        } else {
            expandedModuleIDs.insert(id)
        }
    }

    @ViewBuilder
    private func inlineSettingsView(for module: any MenuModule) -> some View {
        switch module.id {
        case "clock":
            HStack(spacing: 16) {
                Picker("Clock Format", selection: Binding(
                    get: { appState.clockUse24Hour },
                    set: { appState.updateClockSettings(use24Hour: $0) }
                )) {
                    Text("24-Hour").tag(true)
                    Text("12-Hour").tag(false)
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 150)

                Toggle("Show Seconds", isOn: Binding(
                    get: { appState.clockShowSeconds },
                    set: { appState.updateClockSettings(showSeconds: $0) }
                ))
            }
            .font(.subheadline)

        case "battery":
            Text("Show percentage only (phase 1).")
                .font(.subheadline)
                .foregroundStyle(.secondary)

        case "network":
            Text("Network module placeholder.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

        case "cpu":
            Text("CPU module placeholder.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

        case "memory":
            Text("Memory module placeholder.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

        default:
            Text("Module settings placeholder.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}
