import Combine
import SwiftUI

final class AppState: ObservableObject {
    static let maxClockModules = 3

    enum OverflowBehavior: String, CaseIterable, Identifiable {
        case hideTrailing = "Hide Trailing"
        case iconOnlyFallback = "Icon Only Fallback"

        var id: String { rawValue }
    }

    enum StatusEvent {
        case valuesChanged
        case layoutChanged
    }

    static let shared = AppState()

    let statusEvents = PassthroughSubject<StatusEvent, Never>()

    @Published private(set) var orderedModules: [any MenuModule] = AppState.defaultModules()
    @Published var overflowBehavior: OverflowBehavior = .hideTrailing {
        didSet {
            statusEvents.send(.layoutChanged)
        }
    }
    @Published private var clockSettingsByModuleID: [String: ClockSettings] = ["clock": .default(isEnabled: true)]

    private let updateEngine = UpdateEngine()

    init() {
        startEngine()
    }

    deinit {
        let engine = updateEngine
        Task {
            await engine.stop()
        }
    }

    func title(for module: any MenuModule) -> String {
        if let titled = module as? any TitledMenuModule {
            return titled.title
        }
        return module.id.capitalized
    }

    func modules(matching query: String) -> [any MenuModule] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return orderedModules }

        return orderedModules.filter { module in
            let titleText = title(for: module)
            return titleText.localizedCaseInsensitiveContains(text)
                || module.id.localizedCaseInsensitiveContains(text)
        }
    }

    func setModuleEnabled(id: String, isEnabled: Bool) {
        guard let index = orderedModules.firstIndex(where: { $0.id == id }) else { return }
        orderedModules[index].isEnabled = isEnabled

        if var settings = clockSettingsByModuleID[id] {
            settings.isEnabled = isEnabled
            clockSettingsByModuleID[id] = settings
            if let clockModule = orderedModules[index] as? ClockModule {
                clockModule.applySettings(settings)
            }
        }

        Task {
            await updateEngine.setModules(orderedModules)
        }

        statusEvents.send(.layoutChanged)
        objectWillChange.send()
    }

    func clockSettings(for moduleID: String) -> ClockSettings {
        clockSettingsByModuleID[moduleID] ?? .default(isEnabled: true)
    }

    func addClockModule(after moduleID: String?) {
        guard clockModuleCount() < Self.maxClockModules else { return }

        let sourceID = moduleID ?? "clock"
        let sourceSettings = clockSettingsByModuleID[sourceID] ?? .default(isEnabled: true)
        let newID = nextClockModuleID()

        let newClock = ClockModule(
            id: newID,
            title: "Clock",
            isEnabled: sourceSettings.isEnabled,
            settings: sourceSettings
        )

        let insertIndex: Int
        if let moduleID, let index = orderedModules.firstIndex(where: { $0.id == moduleID }) {
            insertIndex = index + 1
        } else {
            insertIndex = 0
        }

        orderedModules.insert(newClock, at: insertIndex)
        clockSettingsByModuleID[newID] = sourceSettings

        Task {
            await updateEngine.setModules(orderedModules)
        }

        statusEvents.send(.layoutChanged)
        objectWillChange.send()
    }

    func canAddClockModule() -> Bool {
        clockModuleCount() < Self.maxClockModules
    }

    func removeClockModule(id: String) {
        guard id.hasPrefix("clock"), id != "clock" else { return }
        guard let index = orderedModules.firstIndex(where: { $0.id == id }) else { return }

        orderedModules.remove(at: index)
        clockSettingsByModuleID.removeValue(forKey: id)

        Task {
            await updateEngine.setModules(orderedModules)
        }

        statusEvents.send(.layoutChanged)
        objectWillChange.send()
    }

    func setModuleShowsValue(id: String, showsValue: Bool) {
        guard let index = orderedModules.firstIndex(where: { $0.id == id }) else { return }
        orderedModules[index].showsValue = showsValue
        statusEvents.send(.layoutChanged)
        objectWillChange.send()
    }

    func updateClockSettings(moduleID: String, _ mutate: (inout ClockSettings) -> Void) {
        var updated = clockSettingsByModuleID[moduleID] ?? .default(isEnabled: true)
        mutate(&updated)
        updated.selectedTimezones = Array(updated.selectedTimezones.prefix(1))

        if let clockEnabled = orderedModules.first(where: { $0.id == moduleID })?.isEnabled {
            updated.isEnabled = clockEnabled
        }

        clockSettingsByModuleID[moduleID] = updated

        if let clockModule = orderedModules.first(where: { $0.id == moduleID }) as? ClockModule {
            clockModule.applySettings(updated)
        }

        statusEvents.send(.layoutChanged)
        objectWillChange.send()
    }

    func resetToDefaults() {
        orderedModules = AppState.defaultModules()
        overflowBehavior = .hideTrailing
        clockSettingsByModuleID = ["clock": .default(isEnabled: true)]

        Task {
            await updateEngine.setModules(orderedModules)
        }

        statusEvents.send(.layoutChanged)
        objectWillChange.send()
    }

    private func startEngine() {
        let statusEvents = self.statusEvents
        Task {
            await updateEngine.setModules(orderedModules)
            await updateEngine.start {
                statusEvents.send(.valuesChanged)
            }
        }
    }

    private static func defaultModules() -> [any MenuModule] {
        [
            ClockModule(id: "clock", title: "Clock", isEnabled: true, settings: .default(isEnabled: true)),
            CPUModule(isEnabled: true),
            MemoryModule(isEnabled: true),
            NetworkModule(isEnabled: false),
            DiskUsageModule(isEnabled: false)
        ]
    }

    private func nextClockModuleID() -> String {
        var index = 1
        while orderedModules.contains(where: { $0.id == "clock.\(index)" }) {
            index += 1
        }
        return "clock.\(index)"
    }

    private func clockModuleCount() -> Int {
        orderedModules.reduce(into: 0) { count, module in
            if module.id.hasPrefix("clock") {
                count += 1
            }
        }
    }
}
