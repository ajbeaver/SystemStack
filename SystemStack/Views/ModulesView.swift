import SwiftUI

struct ModulesView: View {
    @EnvironmentObject private var appState: AppState
    @State private var searchText = ""
    @State private var expandedModuleIDs: Set<String> = []

    @State private var customTimezoneSearch = ""
    @State private var worldTimezoneSearch = ""

    private let allTimezones: [String] = {
        TimeZone.knownTimeZoneIdentifiers.sorted { lhs, rhs in
            let left = TimeZone(identifier: lhs)?.localizedName(for: .standard, locale: .autoupdatingCurrent) ?? lhs
            let right = TimeZone(identifier: rhs)?.localizedName(for: .standard, locale: .autoupdatingCurrent) ?? rhs
            if left == right {
                return lhs < rhs
            }
            return left < right
        }
    }()

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

                                    Text(appState.title(for: module))
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

    private func timezoneDisplayName(_ id: String) -> String {
        let localized = TimeZone(identifier: id)?.localizedName(for: .standard, locale: .autoupdatingCurrent)
        return localized.map { "\($0) (\(id))" } ?? id
    }

    private func filteredTimezones(search: String) -> [String] {
        let trimmed = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return Array(allTimezones.prefix(120)) }

        return allTimezones.filter { id in
            let lowered = trimmed.lowercased()
            if id.lowercased().contains(lowered) {
                return true
            }
            let localized = TimeZone(identifier: id)?.localizedName(for: .standard, locale: .autoupdatingCurrent) ?? ""
            return localized.lowercased().contains(lowered)
        }
        .prefix(120)
        .map { $0 }
    }

    private func isWorldSelected(_ id: String) -> Bool {
        appState.clockSettings.selectedTimezones.contains(id)
    }

    private func toggleWorldTimezone(_ id: String) {
        appState.updateClockSettings { settings in
            var selected = settings.selectedTimezones
            if let index = selected.firstIndex(of: id) {
                selected.remove(at: index)
            } else if selected.count < 4 {
                selected.append(id)
            }
            settings.selectedTimezones = selected
        }
    }

    @ViewBuilder
    private func inlineSettingsView(for module: any MenuModule) -> some View {
        switch module.id {
        case "clock":
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Use 24-Hour Time", isOn: Binding(
                    get: { appState.clockSettings.use24Hour },
                    set: { value in
                        appState.updateClockSettings { settings in
                            settings.use24Hour = value
                        }
                    }
                ))

                Toggle("Show Seconds", isOn: Binding(
                    get: { appState.clockSettings.showSeconds },
                    set: { value in
                        appState.updateClockSettings { settings in
                            settings.showSeconds = value
                        }
                    }
                ))

                Toggle("Show AM/PM", isOn: Binding(
                    get: { appState.clockSettings.showAMPM },
                    set: { value in
                        appState.updateClockSettings { settings in
                            settings.showAMPM = value
                        }
                    }
                ))
                .disabled(appState.clockSettings.use24Hour)

                Toggle("Show Timezone Label", isOn: Binding(
                    get: { appState.clockSettings.showTimezoneLabel },
                    set: { value in
                        appState.updateClockSettings { settings in
                            settings.showTimezoneLabel = value
                        }
                    }
                ))

                Picker("Timezone Label Style", selection: Binding(
                    get: { appState.clockSettings.timezoneLabelStyle },
                    set: { value in
                        appState.updateClockSettings { settings in
                            settings.timezoneLabelStyle = value
                        }
                    }
                )) {
                    Text("Short (UTC)").tag(TimezoneLabelStyle.short)
                    Text("Compact (Z)")
                        .tag(TimezoneLabelStyle.compact)
                        .disabled(!appState.clockSettings.use24Hour)
                }
                .pickerStyle(.segmented)
                .disabled(!appState.clockSettings.showTimezoneLabel)

                Picker("Timezone Mode", selection: Binding(
                    get: { appState.clockSettings.timezoneMode },
                    set: { value in
                        appState.updateClockSettings { settings in
                            settings.timezoneMode = value
                        }
                    }
                )) {
                    Text("System").tag(TimezoneMode.system)
                    Text("UTC").tag(TimezoneMode.utc)
                    Text("Custom").tag(TimezoneMode.custom)
                    Text("World").tag(TimezoneMode.world)
                }
                .pickerStyle(.segmented)

                if appState.clockSettings.timezoneMode == .custom {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Search timezones", text: $customTimezoneSearch)
                            .textFieldStyle(.roundedBorder)

                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 4) {
                                ForEach(filteredTimezones(search: customTimezoneSearch), id: \.self) { timezoneID in
                                    Button {
                                        appState.updateClockSettings { settings in
                                            settings.selectedTimezones = [timezoneID]
                                        }
                                    } label: {
                                        HStack(spacing: 8) {
                                            Image(systemName: appState.clockSettings.selectedTimezones.first == timezoneID ? "checkmark.circle.fill" : "circle")
                                                .foregroundStyle(.secondary)
                                            Text(timezoneDisplayName(timezoneID))
                                                .foregroundStyle(.primary)
                                                .lineLimit(1)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .frame(height: 120)
                    }
                }

                if appState.clockSettings.timezoneMode == .world {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Select up to 4 timezones")
                            .foregroundStyle(.secondary)

                        TextField("Search timezones", text: $worldTimezoneSearch)
                            .textFieldStyle(.roundedBorder)

                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 4) {
                                ForEach(filteredTimezones(search: worldTimezoneSearch), id: \.self) { timezoneID in
                                    Button {
                                        toggleWorldTimezone(timezoneID)
                                    } label: {
                                        HStack(spacing: 8) {
                                            Image(systemName: isWorldSelected(timezoneID) ? "checkmark.circle.fill" : "circle")
                                                .foregroundStyle(.secondary)
                                            Text(timezoneDisplayName(timezoneID))
                                                .foregroundStyle(.primary)
                                                .lineLimit(1)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .frame(height: 140)
                    }
                }
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
