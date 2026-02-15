import AppKit
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

        var id: String { rawValue }

        var token: String {
            switch self {
            case .compact:
                return " "
            case .normal:
                return "  "
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

    static let shared = AppState()

    @Published var selectedSection: SidebarSection? = .modules
    @Published private(set) var orderedModules: [any MenuModule] = AppState.defaultModules()
    @Published var appearanceSettings = AppearanceSettings()
    @Published var launchAtLogin = false

    @Published var clockUse24Hour = ClockModule.defaultUse24Hour()
    @Published var clockShowSeconds = false

    private var configurationWindowController: NSWindowController?

    var enabledModules: [any MenuModule] {
        orderedModules.filter { $0.isEnabled }
    }

    func openConfigurationWindow() {
        if let window = configurationWindowController?.window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let rootView = ConfigurationView()
            .environmentObject(self)

        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "SystemStack Configuration"
        window.styleMask.insert(.resizable)
        window.setContentSize(NSSize(width: 980, height: 640))
        window.minSize = NSSize(width: 780, height: 520)
        window.toolbarStyle = .automatic

        let controller = NSWindowController(window: window)
        configurationWindowController = controller
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.configurationWindowController = nil
        }

        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func modules(matching query: String) -> [any MenuModule] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return orderedModules }
        return orderedModules.filter { module in
            module.title.localizedCaseInsensitiveContains(text)
        }
    }

    func setModuleEnabled(id: String, isEnabled: Bool) {
        guard let index = orderedModules.firstIndex(where: { $0.id == id }) else { return }
        orderedModules[index].isEnabled = isEnabled
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
        objectWillChange.send()
    }

    func removeFromLayout(id: String) {
        setModuleEnabled(id: id, isEnabled: false)
    }

    func updateClockSettings(use24Hour: Bool? = nil, showSeconds: Bool? = nil) {
        if let use24Hour {
            clockUse24Hour = use24Hour
        }

        if let showSeconds {
            clockShowSeconds = showSeconds
        }

        syncClockModuleSettings()
        objectWillChange.send()
    }

    func refreshStatusValues() {
        syncClockModuleSettings()
        objectWillChange.send()
    }

    func resetToDefaults() {
        selectedSection = .modules
        orderedModules = AppState.defaultModules()
        appearanceSettings = AppearanceSettings()
        launchAtLogin = false
        clockUse24Hour = ClockModule.defaultUse24Hour()
        clockShowSeconds = false
        syncClockModuleSettings()
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
                return module.statusValueText()
            case .iconAndValue:
                if module.symbolName == nil {
                    return module.statusValueText()
                }
                return "[*] \(module.statusValueText())"
            }
        }

        guard !segments.isEmpty else { return "SystemStack" }
        return segments.joined(separator: menuBarSeparatorText())
    }

    private func syncClockModuleSettings() {
        guard let clockModule = orderedModules.first(where: { $0.id == "clock" }) as? ClockModule else {
            return
        }

        clockModule.use24Hour = clockUse24Hour
        clockModule.showSeconds = clockShowSeconds
    }

    private static func defaultModules() -> [any MenuModule] {
        [
            ClockModule(isEnabled: true),
            CalendarModule(),
            BatteryModule(),
            NetworkModule(),
            CPUUsageModule(isEnabled: true),
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
