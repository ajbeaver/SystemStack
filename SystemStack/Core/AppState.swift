import Combine
import SwiftUI

final class AppState: ObservableObject {
    enum DisplayMode: String, CaseIterable, Identifiable {
        case iconOnly
        case iconAndValue

        var id: String { rawValue }

        var title: String {
            switch self {
            case .iconOnly:
                return "Icons only"
            case .iconAndValue:
                return "Icons + values"
            }
        }
    }

    struct AppearanceSettings {
        var displayMode: DisplayMode = .iconAndValue
    }

    enum SymbolSize: String, CaseIterable, Identifiable {
        case small = "Small"
        case standard = "Standard"

        var id: String { rawValue }
    }

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
    @Published var appearanceSettings = AppearanceSettings() {
        didSet {
            statusEvents.send(.layoutChanged)
        }
    }
    @Published var symbolSize: SymbolSize = .standard {
        didSet {
            statusEvents.send(.layoutChanged)
        }
    }
    @Published var overflowBehavior: OverflowBehavior = .hideTrailing {
        didSet {
            statusEvents.send(.layoutChanged)
        }
    }
    @Published var clockSettings = ClockSettings.default(isEnabled: true)

    private let updateEngine = UpdateEngine()

    init() {
        syncClockModuleSettings()
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

        if id == "clock" {
            var updated = clockSettings
            updated.isEnabled = isEnabled
            clockSettings = updated
            syncClockModuleSettings()
        }

        Task {
            await updateEngine.setModules(orderedModules)
        }

        statusEvents.send(.layoutChanged)
        objectWillChange.send()
    }

    func updateClockSettings(_ mutate: (inout ClockSettings) -> Void) {
        var updated = clockSettings
        mutate(&updated)
        updated.selectedTimezones = Array(updated.selectedTimezones.prefix(4))

        if !updated.use24Hour, updated.timezoneLabelStyle == .compact {
            updated.timezoneLabelStyle = .short
        }

        if let clockEnabled = orderedModules.first(where: { $0.id == "clock" })?.isEnabled {
            updated.isEnabled = clockEnabled
        }

        clockSettings = updated
        syncClockModuleSettings()
        statusEvents.send(.layoutChanged)
        objectWillChange.send()
    }

    func resetToDefaults() {
        orderedModules = AppState.defaultModules()
        appearanceSettings = AppearanceSettings()
        symbolSize = .standard
        overflowBehavior = .hideTrailing
        clockSettings = .default(isEnabled: true)
        syncClockModuleSettings()

        Task {
            await updateEngine.setModules(orderedModules)
        }

        statusEvents.send(.layoutChanged)
        objectWillChange.send()
    }

    private func syncClockModuleSettings() {
        guard let clockModule = orderedModules.first(where: { $0.id == "clock" }) as? ClockModule else {
            return
        }

        clockModule.applySettings(clockSettings)
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
            ClockModule(isEnabled: true, settings: .default(isEnabled: true)),
            CPUModule(isEnabled: true),
            MemoryModule(isEnabled: true),
            NetworkModule(isEnabled: false),
            DiskUsageModule(isEnabled: false)
        ]
    }
}
