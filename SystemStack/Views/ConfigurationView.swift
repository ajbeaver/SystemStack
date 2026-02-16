import AppKit
import ServiceManagement
import SwiftUI

struct ConfigurationView: View {
    private enum TopTab: String, CaseIterable, Identifiable {
        case modules = "Modules"
        case configuration = "Configuration"

        var id: String { rawValue }
    }

    @EnvironmentObject private var appState: AppState
    @State private var selectedModuleID: String?
    @State private var topTab: TopTab = .modules
    @State private var launchAtLoginEnabled = false
    @State private var launchAtLoginAvailable = true
    @State private var launchAtLoginError: String?

    private var filteredModules: [any MenuModule] {
        appState.orderedModules
    }

    private var selectedModule: (any MenuModule)? {
        if let selectedModuleID,
           let selected = appState.orderedModules.first(where: { $0.id == selectedModuleID }) {
            return selected
        }
        return filteredModules.first
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(spacing: 12) {
                Picker("", selection: $topTab) {
                    ForEach(TopTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.top, 14)

                switch topTab {
                case .modules:
                    modulesEditor
                case .configuration:
                    globalConfigurationView
                }
            }
            .frame(width: 490, height: 560, alignment: .top)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.045))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                    )
            )

            Spacer(minLength: 0)
        }
        .frame(width: 560, height: 600, alignment: .top)
        .onAppear {
            refreshLaunchAtLoginState()
        }
    }

    private var modulesEditor: some View {
        HStack(spacing: 0) {
            leftColumn
                .frame(width: 220)

            Divider()

            rightColumn
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 12)
    }

    private var leftColumn: some View {
        VStack(spacing: 10) {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(filteredModules, id: \.id) { module in
                        moduleRow(module)
                    }
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 10)
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
                    Text(moduleHeaderTitle(for: module))
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
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
    }

    private var globalConfigurationView: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Tip: Hold ⌘ and drag menu bar icons to reorder them.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)

            Toggle("Launch at Login", isOn: Binding(
                get: { launchAtLoginEnabled },
                set: { setLaunchAtLogin($0) }
            ))
            .toggleStyle(.switch)
            .disabled(!launchAtLoginAvailable)

            if let launchAtLoginError, !launchAtLoginError.isEmpty {
                Text(launchAtLoginError)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            HStack(spacing: 14) {
                Button("Reset to Defaults") {
                    appState.resetToDefaults()
                }

                Button("Quit") {
                    NSApp.terminate(nil)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)

            Text("\(appName) · v\(appVersion) · Build \(appBuild)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func moduleHeaderTitle(for module: any MenuModule) -> String {
        if module.id == "clock" {
            return "\(appState.title(for: module)) · Default Clock"
        }
        if isGeneratedClockID(module.id) {
            return "\(appState.title(for: module)) · Generated Clock"
        }
        return appState.title(for: module)
    }

    private func isGeneratedClockID(_ id: String) -> Bool {
        guard id.hasPrefix("clock.") else { return false }
        let suffix = id.dropFirst("clock.".count)
        guard !suffix.isEmpty, suffix.first != "0" else { return false }
        return suffix.allSatisfy(\.isNumber)
    }

    private var appName: String {
        Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String
            ?? Bundle.main.infoDictionary?["CFBundleName"] as? String
            ?? "SystemStack"
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    private var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }

    private func refreshLaunchAtLoginState() {
        if #available(macOS 13.0, *) {
            launchAtLoginAvailable = true
            launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
        } else {
            launchAtLoginAvailable = false
            launchAtLoginEnabled = false
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
                launchAtLoginEnabled = enabled
                launchAtLoginError = nil
            } catch {
                launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
                launchAtLoginError = "Unable to update launch setting."
            }
        } else {
            launchAtLoginEnabled = false
            launchAtLoginError = "Launch at Login requires a newer macOS version."
        }
    }

    @ViewBuilder
    private func moduleSettingsView(for module: any MenuModule) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Show Value", isOn: Binding(
                get: { module.showsValue },
                set: { appState.setModuleShowsValue(id: module.id, showsValue: $0) }
            ))
            .toggleStyle(.switch)

            if module.id.hasPrefix("clock") {
                ClockModuleSettingsView(moduleID: module.id)
            } else if module.id == "cpu" {
                CPUHoverSettingsView(moduleID: module.id)
            } else if module.id == "memory" {
                MemoryHoverSettingsView(moduleID: module.id)
            } else if module.id == "disk" {
                DiskHoverSettingsView(moduleID: module.id)
            } else if module.id == "network" {
                NetworkHoverSettingsView(moduleID: module.id)
            }
        }
    }
}

private struct CPUHoverSettingsView: View {
    @EnvironmentObject private var appState: AppState
    let moduleID: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Mode", selection: Binding(
                get: { appState.cpuHoverMode(id: moduleID) },
                set: { appState.setCPUHoverMode(id: moduleID, mode: $0) }
            )) {
                ForEach(CPUModule.HoverMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.menu)

            if appState.cpuHoverMode(id: moduleID) == .sparkline {
                Toggle("Show User", isOn: Binding(
                    get: { appState.cpuShowsSparklineUser(id: moduleID) },
                    set: { appState.setCPUShowsSparklineUser(id: moduleID, shows: $0) }
                ))

                Toggle("Show System", isOn: Binding(
                    get: { appState.cpuShowsSparklineSystem(id: moduleID) },
                    set: { appState.setCPUShowsSparklineSystem(id: moduleID, shows: $0) }
                ))
            }
        }
    }
}

private struct MemoryHoverSettingsView: View {
    @EnvironmentObject private var appState: AppState
    let moduleID: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Show Used", isOn: Binding(
                get: { appState.memoryShowsUsed(id: moduleID) },
                set: { appState.setMemoryShowsUsed(id: moduleID, shows: $0) }
            ))

            Toggle("Show Available", isOn: Binding(
                get: { appState.memoryShowsAvailable(id: moduleID) },
                set: { appState.setMemoryShowsAvailable(id: moduleID, shows: $0) }
            ))

            Toggle("Show Swap Used", isOn: Binding(
                get: { appState.memoryShowsSwapUsed(id: moduleID) },
                set: { appState.setMemoryShowsSwapUsed(id: moduleID, shows: $0) }
            ))
        }
    }
}

private struct DiskHoverSettingsView: View {
    @EnvironmentObject private var appState: AppState
    let moduleID: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Mode", selection: Binding(
                get: { appState.diskHoverMode(id: moduleID) },
                set: { appState.setDiskHoverMode(id: moduleID, mode: $0) }
            )) {
                ForEach(DiskUsageModule.HoverMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.menu)

            if appState.diskHoverMode(id: moduleID) == .capacity {
                Toggle("Show Used", isOn: Binding(
                    get: { appState.diskShowsCapacityUsed(id: moduleID) },
                    set: { appState.setDiskShowsCapacityUsed(id: moduleID, shows: $0) }
                ))

                Toggle("Show Available", isOn: Binding(
                    get: { appState.diskShowsCapacityAvailable(id: moduleID) },
                    set: { appState.setDiskShowsCapacityAvailable(id: moduleID, shows: $0) }
                ))

                Toggle("Show Total", isOn: Binding(
                    get: { appState.diskShowsCapacityTotal(id: moduleID) },
                    set: { appState.setDiskShowsCapacityTotal(id: moduleID, shows: $0) }
                ))
            } else {
                Toggle("Show Volume List", isOn: Binding(
                    get: { appState.diskShowsVolumeList(id: moduleID) },
                    set: { appState.setDiskShowsVolumeList(id: moduleID, shows: $0) }
                ))
            }
        }
    }
}

private struct NetworkHoverSettingsView: View {
    @EnvironmentObject private var appState: AppState
    let moduleID: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Mode", selection: Binding(
                get: { appState.networkHoverMode(id: moduleID) },
                set: { appState.setNetworkHoverMode(id: moduleID, mode: $0) }
            )) {
                ForEach(NetworkModule.HoverMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.menu)

            Picker("Units", selection: Binding(
                get: { appState.networkSpeedUnitMode(id: moduleID) },
                set: { appState.setNetworkSpeedUnitMode(id: moduleID, mode: $0) }
            )) {
                ForEach(NetworkModule.SpeedUnitMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.menu)

            if appState.networkSpeedUnitMode(id: moduleID) == .fixed {
                Picker("Fixed Unit", selection: Binding(
                    get: { appState.networkFixedSpeedUnit(id: moduleID) },
                    set: { appState.setNetworkFixedSpeedUnit(id: moduleID, unit: $0) }
                )) {
                    ForEach(NetworkModule.FixedSpeedUnit.allCases) { unit in
                        Text(unit.rawValue).tag(unit)
                    }
                }
                .pickerStyle(.menu)
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
                    appState.updateClockSettings(moduleID: moduleID) { clockSettings in
                        clockSettings.use24Hour = value
                    }
                }
            ))

            Toggle("Show Seconds", isOn: Binding(
                get: { appState.clockSettings(for: moduleID).showSeconds },
                set: { value in
                    appState.updateClockSettings(moduleID: moduleID) { clockSettings in
                        clockSettings.showSeconds = value
                    }
                }
            ))

            Toggle("Show AM/PM", isOn: Binding(
                get: { appState.clockSettings(for: moduleID).showAMPM },
                set: { value in
                    appState.updateClockSettings(moduleID: moduleID) { clockSettings in
                        clockSettings.showAMPM = value
                    }
                }
            ))
            .disabled(settings.use24Hour)

            Toggle("Show Timezone Label", isOn: Binding(
                get: { appState.clockSettings(for: moduleID).showTimezoneLabel },
                set: { value in
                    appState.updateClockSettings(moduleID: moduleID) { clockSettings in
                        clockSettings.showTimezoneLabel = value
                    }
                }
            ))

            Picker("Timezone Mode", selection: Binding(
                get: { appState.clockSettings(for: moduleID).timezoneMode },
                set: { value in
                    appState.updateClockSettings(moduleID: moduleID) { clockSettings in
                        clockSettings.timezoneMode = value
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

                    timezoneResultsView(search: customTimezoneSearch)
                        .frame(height: 120)
                }
            }

            HStack {
                if moduleID == "clock" {
                    Label("Default Clock", systemImage: "clock.badge.checkmark")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    appState.addClockModule(after: moduleID)
                } label: {
                    Label("Add Clock", systemImage: "plus")
                }
                .buttonStyle(.plain)
                .disabled(!appState.canAddClockModule())
            }

            if !appState.canAddClockModule() {
                Text("Maximum of \(AppState.maxClockModules) clocks reached.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if isGeneratedClockID(moduleID) {
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

    private func isGeneratedClockID(_ id: String) -> Bool {
        guard id.hasPrefix("clock.") else { return false }
        let suffix = id.dropFirst("clock.".count)
        guard !suffix.isEmpty, suffix.first != "0" else { return false }
        return suffix.allSatisfy(\.isNumber)
    }
}
