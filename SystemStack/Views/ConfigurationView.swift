import AppKit
import SwiftUI

struct ConfigurationView: View {
    private enum TopTab: String, CaseIterable, Identifiable {
        case modules = "Modules"
        case configuration = "Configuration"

        var id: String { rawValue }
    }

    @EnvironmentObject private var appState: AppState
    @State private var searchText = ""
    @State private var selectedModuleID: String?
    @State private var topTab: TopTab = .modules

    private var filteredModules: [any MenuModule] {
        appState.modules(matching: searchText)
    }

    private var selectedModule: (any MenuModule)? {
        if let selectedModuleID,
           let selected = appState.orderedModules.first(where: { $0.id == selectedModuleID }) {
            return selected
        }
        return filteredModules.first
    }

    var body: some View {
        VStack(spacing: 10) {
            Picker("", selection: $topTab) {
                ForEach(TopTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
            .padding(.top, 10)

            switch topTab {
            case .modules:
                modulesEditor
            case .configuration:
                globalConfigurationView
            }
        }
        .frame(width: 520, height: 560, alignment: .topLeading)
    }

    private var modulesEditor: some View {
        HStack(spacing: 0) {
            leftColumn
                .frame(width: 200)

            Divider()

            rightColumn
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var leftColumn: some View {
        VStack(spacing: 10) {
            TextField("Search Modules", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 10)
                .padding(.top, 10)

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(filteredModules, id: \.id) { module in
                        moduleRow(module)
                    }
                }
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 10)
        }
    }

    private func moduleRow(_ module: any MenuModule) -> some View {
        let isSelected = module.id == (selectedModule?.id ?? "")

        return HStack(spacing: 8) {
            Image(systemName: module.symbolName ?? "questionmark.square")
                .foregroundStyle(.secondary)
                .frame(width: 14)

            Text(appState.title(for: module))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(module.displayValue.isEmpty ? "—" : module.displayValue)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Toggle("", isOn: Binding(
                get: { module.isEnabled },
                set: { appState.setModuleEnabled(id: module.id, isEnabled: $0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .scaleEffect(0.8)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            selectedModuleID = module.id
        }
    }

    private var rightColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let module = selectedModule {
                    Text(appState.title(for: module))
                        .font(.title3)
                        .fontWeight(.semibold)
                        .padding(.top, 10)

                    moduleSettingsView(for: module)
                } else {
                    Text("Select a module from the left.")
                        .foregroundStyle(.secondary)
                        .padding(.top, 18)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
    }

    private var globalConfigurationView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                GroupBox("Layout") {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("Overflow Behavior", selection: $appState.overflowBehavior) {
                            ForEach(AppState.OverflowBehavior.allCases) { behavior in
                                Text(behavior.rawValue).tag(behavior)
                            }
                        }

                        Text("Tip: Hold ⌘ and drag menu bar icons to reorder them.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(8)
                }

                GroupBox("Control") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            Button("Reset to Defaults") {
                                appState.resetToDefaults()
                            }

                            Button("Quit") {
                                NSApp.terminate(nil)
                            }
                        }

                        Text(versionString)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(8)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
    }

    private var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "Version \(version) (\(build))"
    }

    @ViewBuilder
    private func moduleSettingsView(for module: any MenuModule) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Show Value", isOn: Binding(
                get: { module.showsValue },
                set: { appState.setModuleShowsValue(id: module.id, showsValue: $0) }
            ))

            if module.id.hasPrefix("clock") {
                ClockModuleSettingsView(moduleID: module.id)
            }
        }
    }
}

private struct ClockModuleSettingsView: View {
    @EnvironmentObject private var appState: AppState
    let moduleID: String
    @State private var customTimezoneSearch = ""

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
        let settings = appState.clockSettings(for: moduleID)

        VStack(alignment: .leading, spacing: 10) {
            Toggle("Use 24-Hour Time", isOn: Binding(
                get: { appState.clockSettings(for: moduleID).use24Hour },
                set: { value in
                    appState.updateClockSettings(moduleID: moduleID) { settings in
                        settings.use24Hour = value
                    }
                }
            ))

            Toggle("Show Seconds", isOn: Binding(
                get: { appState.clockSettings(for: moduleID).showSeconds },
                set: { value in
                    appState.updateClockSettings(moduleID: moduleID) { settings in
                        settings.showSeconds = value
                    }
                }
            ))

            Toggle("Show AM/PM", isOn: Binding(
                get: { appState.clockSettings(for: moduleID).showAMPM },
                set: { value in
                    appState.updateClockSettings(moduleID: moduleID) { settings in
                        settings.showAMPM = value
                    }
                }
            ))
            .disabled(settings.use24Hour)

            Toggle("Show Timezone Label", isOn: Binding(
                get: { appState.clockSettings(for: moduleID).showTimezoneLabel },
                set: { value in
                    appState.updateClockSettings(moduleID: moduleID) { settings in
                        settings.showTimezoneLabel = value
                    }
                }
            ))

            Picker("Timezone Mode", selection: Binding(
                get: { appState.clockSettings(for: moduleID).timezoneMode },
                set: { value in
                    appState.updateClockSettings(moduleID: moduleID) { settings in
                        settings.timezoneMode = value
                    }
                }
            )) {
                Text("System").tag(TimezoneMode.system)
                Text("UTC").tag(TimezoneMode.utc)
                Text("Custom").tag(TimezoneMode.custom)
            }
            .pickerStyle(.segmented)

            if settings.timezoneMode == .custom {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Search timezones", text: $customTimezoneSearch)
                        .textFieldStyle(.roundedBorder)

                    Button {
                        appState.addClockModule(after: moduleID)
                    } label: {
                        Label("Add Clock", systemImage: "plus")
                    }
                    .buttonStyle(.plain)
                    .disabled(!appState.canAddClockModule())

                    if !appState.canAddClockModule() {
                        Text("Maximum of \(AppState.maxClockModules) clocks reached.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    timezoneResultsView(
                        search: customTimezoneSearch
                    )
                    .frame(height: 120)
                }
            }

            if moduleID != "clock" {
                Divider()
                    .padding(.top, 4)

                Button(role: .destructive) {
                    appState.removeClockModule(id: moduleID)
                } label: {
                    Label("Delete Clock", systemImage: "trash")
                }
                .buttonStyle(.plain)
            }
        }
        .font(.subheadline)
    }

    private func timezoneDisplayName(_ id: String) -> String {
        let localized = TimeZone(identifier: id)?.localizedName(for: .standard, locale: .autoupdatingCurrent)
        return localized.map { "\($0) (\(id))" } ?? id
    }

    private func filteredTimezones(search: String) -> [String] {
        let trimmed = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        return allTimezones.filter { id in
            let lowered = trimmed.lowercased()
            if id.lowercased().contains(lowered) {
                return true
            }
            let localized = TimeZone(identifier: id)?.localizedName(for: .standard, locale: .autoupdatingCurrent) ?? ""
            return localized.lowercased().contains(lowered)
        }
        .prefix(80)
        .map { $0 }
    }

    @ViewBuilder
    private func timezoneResultsView(search: String) -> some View {
        let trimmed = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let results = filteredTimezones(search: search)

        if trimmed.isEmpty {
            EmptyView()
        } else if results.isEmpty {
            Text("No matching timezones.")
                .foregroundStyle(.secondary)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(results, id: \.self) { timezoneID in
                        quickPickButton(
                            timezoneID: timezoneID,
                            title: timezoneDisplayName(timezoneID)
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func quickPickButton(timezoneID: String, title: String) -> some View {
        Button {
            selectCustomTimezone(timezoneID)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isCustomSelected(timezoneID) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(.secondary)
                Text(title)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

    private func isCustomSelected(_ id: String) -> Bool {
        appState.clockSettings(for: moduleID).selectedTimezones.contains(id)
    }

    private func selectCustomTimezone(_ id: String) {
        appState.updateClockSettings(moduleID: moduleID) { settings in
            settings.selectedTimezones = [id]
        }
    }
}
