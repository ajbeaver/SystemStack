import Combine
import SwiftUI

final class AppState: ObservableObject {
    enum SidebarSection: String, CaseIterable, Identifiable {
        case modules = "Modules"
        case layout = "Layout"
        case appearance = "Appearance"
        case general = "General"

        var id: String { rawValue }

        var symbolName: String {
            switch self {
            case .modules:
                return "square.grid.2x2"
            case .layout:
                return "rectangle.3.group"
            case .appearance:
                return "paintbrush"
            case .general:
                return "gearshape"
            }
        }
    }

    enum SpacingMode: String, CaseIterable, Identifiable {
        case compact = "Compact"
        case normal = "Normal"
        case wide = "Wide"

        var id: String { rawValue }

        var token: String {
            switch self {
            case .compact:
                return " "
            case .normal:
                return "  "
            case .wide:
                return "   "
            }
        }
    }

    enum SeparatorStyle: String, CaseIterable, Identifiable {
        case none = "None"
        case dot = "Dot"
        case pipe = "Pipe"
        case slash = "Slash"

        var id: String { rawValue }

        var token: String {
            switch self {
            case .none:
                return ""
            case .dot:
                return "."
            case .pipe:
                return "|"
            case .slash:
                return "/"
            }
        }
    }

    enum DisplayMode: String, CaseIterable, Identifiable {
        case iconOnly = "iconOnly"
        case valueOnly = "valueOnly"
        case iconAndValue = "iconAndValue"

        var id: String { rawValue }

        var title: String {
            switch self {
            case .iconOnly:
                return "Icons only"
            case .valueOnly:
                return "Values only"
            case .iconAndValue:
                return "Icons + values"
            }
        }
    }

    struct AppearanceSettings {
        var displayMode: DisplayMode = .iconAndValue
        var separator: SeparatorStyle = .dot
        var spacing: SpacingMode = .normal
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

    enum ExplicitAppearance: String, CaseIterable, Identifiable {
        case light = "Light"
        case dark = "Dark"

        var id: String { rawValue }
    }

    enum HoverVerbosity: String, CaseIterable, Identifiable {
        case compact = "Compact"
        case verbose = "Verbose"

        var id: String { rawValue }
    }

    enum ClickBehavior: String, CaseIterable, Identifiable {
        case openConfiguration = "Open Configuration"
        case showMenu = "Show Menu"

        var id: String { rawValue }
    }

    enum RefreshRate: String, CaseIterable, Identifiable {
        case oneSecond = "1s"
        case twoSeconds = "2s"
        case fiveSeconds = "5s"

        var id: String { rawValue }
    }

    enum StatusEvent {
        case valuesChanged
        case layoutChanged
    }

    static let shared = AppState()

    let statusEvents = PassthroughSubject<StatusEvent, Never>()

    @Published var selectedSection: SidebarSection? = .modules
    @Published private(set) var orderedModules: [any MenuModule] = AppState.defaultModules()
    @Published var appearanceSettings = AppearanceSettings() {
        didSet {
            statusEvents.send(.layoutChanged)
        }
    }
    @Published var launchAtLogin = false
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
    @Published var followSystemAppearance = true
    @Published var explicitAppearance: ExplicitAppearance = .light
    @Published var hoverVerbosity: HoverVerbosity = .compact
    @Published var showTooltips = true
    @Published var clickBehavior: ClickBehavior = .openConfiguration
    @Published var refreshRate: RefreshRate = .oneSecond
    @Published var reduceRefreshWhenIdle = true
    @Published var hideDockIcon = false

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

    var enabledModules: [any MenuModule] {
        orderedModules.filter { $0.isEnabled }
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

    func moveEnabledModule(draggedID: String, before targetID: String) {
        guard draggedID != targetID,
              let sourceIndex = orderedModules.firstIndex(where: { $0.id == draggedID }),
              let targetIndex = orderedModules.firstIndex(where: { $0.id == targetID }) else {
            return
        }

        let moved = orderedModules.remove(at: sourceIndex)
        let destinationIndex = sourceIndex < targetIndex ? targetIndex - 1 : targetIndex
        orderedModules.insert(moved, at: destinationIndex)

        Task {
            await updateEngine.setModules(orderedModules)
        }

        statusEvents.send(.layoutChanged)
        objectWillChange.send()
    }

    func removeFromLayout(id: String) {
        setModuleEnabled(id: id, isEnabled: false)
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

    func refreshStatusValues() {
        statusEvents.send(.valuesChanged)
    }

    func resetToDefaults() {
        selectedSection = .modules
        orderedModules = AppState.defaultModules()
        appearanceSettings = AppearanceSettings()
        launchAtLogin = false
        symbolSize = .standard
        overflowBehavior = .hideTrailing
        followSystemAppearance = true
        explicitAppearance = .light
        hoverVerbosity = .compact
        showTooltips = true
        clickBehavior = .openConfiguration
        refreshRate = .oneSecond
        reduceRefreshWhenIdle = true
        hideDockIcon = false
        clockSettings = .default(isEnabled: true)
        syncClockModuleSettings()

        Task {
            await updateEngine.setModules(orderedModules)
        }

        statusEvents.send(.layoutChanged)
        objectWillChange.send()
    }

    func menuBarSeparatorText() -> String {
        let spacing = appearanceSettings.spacing.token
        if appearanceSettings.separator == .none {
            return spacing
        }
        return "\(spacing)\(appearanceSettings.separator.token)\(spacing)"
    }

    func plainStatusPreviewText() -> String {
        let segments = enabledModules.map { module in
            switch appearanceSettings.displayMode {
            case .iconOnly:
                return module.symbolName == nil ? "[ ]" : "[*]"
            case .valueOnly:
                return module.displayValue
            case .iconAndValue:
                if module.symbolName == nil {
                    return module.displayValue
                }
                return "[*] \(module.displayValue)"
            }
        }

        guard !segments.isEmpty else { return "SystemStack" }
        return segments.joined(separator: menuBarSeparatorText())
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
            CalendarModule(),
            BatteryModule(),
            NetworkModule(),
            CPUModule(isEnabled: true),
            MemoryModule(isEnabled: true),
            DiskUsageModule(),
            NowPlayingModule(),
            FocusModeModule(),
            VPNModule(),
            BluetoothModule(),
            NotificationsCountModule(),
            WeatherModule(),
            QuickActionsModule(),
            TimerModule(),
            ClipboardModule(),
            CustomTextModule()
        ]
    }
}
