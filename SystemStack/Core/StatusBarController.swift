import AppKit
import Combine
import SwiftUI

@MainActor
final class StatusBarController: NSObject {
    private let appState: AppState
    private let modulePopover = NSPopover()
    private let modulePopoverContent = ModulePopoverContent()
    private let contextMenu = NSMenu()

    private var cancellables = Set<AnyCancellable>()
    private var cachedSymbolImages: [String: NSImage] = [:]
    private var statusItemsByModuleID: [String: NSStatusItem] = [:]
    private var lastOrderKey = ""
    private var activePopoverModuleID: String?
    private var configurationWindowController: NSWindowController?
    private var valuesRefreshScheduled = false
    private var popoverRefreshScheduled = false

    init(appState: AppState) {
        self.appState = appState
        super.init()
        configureModulePopover()
        configureContextMenu()
        observeState()
        syncStatusItems(rebuildOrder: true)
    }

    private func configureModulePopover() {
        modulePopover.behavior = .transient
        modulePopover.animates = true
        modulePopover.contentSize = NSSize(width: 280, height: 180)

        let rootView = ModuleDetailPopoverView(
            content: modulePopoverContent,
            openConfiguration: { [weak self] in
                self?.openConfiguration()
            },
            quitApp: { [weak self] in
                self?.quitApp()
            }
        )
        .environmentObject(appState)
        modulePopover.contentViewController = NSHostingController(rootView: rootView)
    }

    private func configureContextMenu() {
        let openItem = NSMenuItem(
            title: "Open Configuration",
            action: #selector(openConfiguration),
            keyEquivalent: ""
        )
        openItem.target = self

        let quitItem = NSMenuItem(
            title: "Quit",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self

        contextMenu.items = [openItem, NSMenuItem.separator(), quitItem]
    }

    private func observeState() {
        appState.statusEvents
            .sink { [weak self] event in
                guard let self else { return }

                switch event {
                case .valuesChanged:
                    self.updateVisibleModuleItems()
                case .layoutChanged:
                    let nextOrderKey = self.orderKey()
                    let rebuild = nextOrderKey != self.lastOrderKey
                    self.syncStatusItems(rebuildOrder: rebuild)
                }
            }
            .store(in: &cancellables)
    }

    private func syncStatusItems(rebuildOrder: Bool) {
        let modules = appState.orderedModules.compactMap { $0 as? BaseMenuModule }
        let moduleIDs = Set(modules.map(\.id))

        // Remove stale status items for modules that no longer exist.
        let staleModuleIDs = statusItemsByModuleID.keys.filter { !moduleIDs.contains($0) }
        for moduleID in staleModuleIDs {
            if let item = statusItemsByModuleID[moduleID] {
                NSStatusBar.system.removeStatusItem(item)
            }
            statusItemsByModuleID.removeValue(forKey: moduleID)
        }

        for module in modules {
            module.statusItem = statusItemsByModuleID[module.id]
        }

        if rebuildOrder {
            for (_, item) in statusItemsByModuleID {
                NSStatusBar.system.removeStatusItem(item)
            }
            statusItemsByModuleID.removeAll()
            for module in modules {
                module.statusItem = nil
            }
            lastOrderKey = orderKey()
        }

        for module in modules {
            if module.isEnabled {
                if module.statusItem == nil {
                    createStatusItem(for: module)
                }
                module.statusItem?.isVisible = true
            } else {
                module.statusItem?.isVisible = false
            }
        }

        renderLayout()
    }

    private func createStatusItem(for module: BaseMenuModule) {
        if let existing = statusItemsByModuleID[module.id] {
            module.statusItem = existing
            return
        }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        module.statusItem = item
        statusItemsByModuleID[module.id] = item

        guard let button = item.button else { return }
        button.image = nil
        button.title = ""
        button.identifier = NSUserInterfaceItemIdentifier(module.id)
        button.action = #selector(handleModuleClick(_:))
        button.target = self
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func updateVisibleModuleItems() {
        guard !valuesRefreshScheduled else { return }
        valuesRefreshScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.valuesRefreshScheduled = false
            self.renderLayout()
            self.scheduleActivePopoverRefresh()
        }
    }

    private func renderLayout() {
        let modules = appState.orderedModules.compactMap { $0 as? BaseMenuModule }.filter(\.isEnabled)
        guard !modules.isEmpty else { return }

        applyVisuals(modules, forceHideValues: false)
        if !fitsWithinAvailableWidth(modules) {
            hideTrailingUntilFits(modules, forceHideValues: false)
        }
    }

    private func applyVisuals(_ modules: [BaseMenuModule], forceHideValues: Bool) {
        for module in modules {
            module.statusItem?.isVisible = true
            updateStatusItem(
                for: module,
                forceHideValues: forceHideValues
            )
        }
    }

    private func updateStatusItem(
        for module: BaseMenuModule,
        forceHideValues: Bool
    ) {
        guard let button = module.statusItem?.button else { return }

        let value = module.displayValue.isEmpty ? "—" : module.displayValue
        let image = moduleImage(for: module)
        let shouldShowValue = module.showsValue && !forceHideValues

        if shouldShowValue {
            button.image = image
            button.title = value
        } else {
            button.image = image
            button.title = image == nil ? value : ""
        }
        button.toolTip = nil
    }

    private func moduleImage(for module: BaseMenuModule) -> NSImage? {
        guard let symbolName = module.symbolName else { return nil }
        let pointSize: CGFloat = 13
        let cacheKey = "\(symbolName)-\(pointSize)"

        if let cached = cachedSymbolImages[cacheKey] {
            return cached
        }

        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
        guard let image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: nil
        )?.withSymbolConfiguration(config) else {
            return nil
        }

        image.isTemplate = true
        cachedSymbolImages[cacheKey] = image
        return image
    }

    private func moduleShortLabel(for module: BaseMenuModule) -> String {
        switch module.id {
        case "cpu":
            return "CPU"
        case "memory":
            return "Mem"
        case "clock":
            return "Time"
        case "network":
            return "Net"
        case "disk":
            return "Disk"
        default:
            return appState.title(for: module)
        }
    }

    private func hideTrailingUntilFits(_ modules: [BaseMenuModule], forceHideValues: Bool) {
        var visibleCount = modules.count

        while visibleCount > 1 {
            let visible = Array(modules.prefix(visibleCount))
            if fitsWithinAvailableWidth(visible) {
                break
            }
            visibleCount -= 1
        }

        for (index, module) in modules.enumerated() {
            if index < visibleCount {
                module.statusItem?.isVisible = true
                updateStatusItem(for: module, forceHideValues: forceHideValues)
            } else {
                module.statusItem?.isVisible = false
            }
        }
    }

    private func fitsWithinAvailableWidth(_ modules: [BaseMenuModule]) -> Bool {
        guard !modules.isEmpty else { return true }

        let totalWidth = modules.reduce(CGFloat(0)) { partial, module in
            guard module.statusItem?.isVisible == true,
                  let button = module.statusItem?.button else {
                return partial
            }
            return partial + button.intrinsicContentSize.width
        }

        let available = availableStatusWidth()
        return totalWidth <= available
    }

    private func availableStatusWidth() -> CGFloat {
        let screenWidth = firstVisibleButton()?.window?.screen?.visibleFrame.width
            ?? NSScreen.main?.visibleFrame.width
            ?? 1280
        return min(screenWidth * 0.45, 620)
    }

    private func orderKey() -> String {
        appState.orderedModules.enumerated().reduce(into: "") { result, pair in
            if pair.offset > 0 {
                result.append(",")
            }
            result.append(pair.element.id)
        }
    }

    @objc private func handleModuleClick(_ sender: Any?) {
        guard let event = NSApp.currentEvent,
              let button = sender as? NSStatusBarButton else {
            return
        }

        if event.type == .rightMouseUp {
            NSMenu.popUpContextMenu(contextMenu, with: event, for: button)
            return
        }

        guard let module = moduleFor(button: button) else { return }

        if modulePopover.isShown, activePopoverModuleID == module.id {
            modulePopover.performClose(sender)
            activePopoverModuleID = nil
            return
        }

        showModulePopover(for: module, anchorButton: button)
    }

    @objc private func openConfiguration() {
        showConfigurationWindow()
        modulePopover.performClose(nil)
        activePopoverModuleID = nil
        NSApp.activate(ignoringOtherApps: true)
    }

    private func firstVisibleButton() -> NSStatusBarButton? {
        let modules = appState.orderedModules.compactMap { $0 as? BaseMenuModule }
        for module in modules where module.isEnabled {
            if let button = module.statusItem?.button {
                return button
            }
        }
        return nil
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    private func moduleFor(button: NSStatusBarButton) -> BaseMenuModule? {
        guard let identifier = button.identifier?.rawValue else { return nil }
        return appState.orderedModules.first(where: { $0.id == identifier }) as? BaseMenuModule
    }

    private func showModulePopover(for module: BaseMenuModule, anchorButton: NSStatusBarButton) {
        activePopoverModuleID = module.id
        updateModulePopoverContent(for: module)
        modulePopover.show(relativeTo: anchorButton.bounds, of: anchorButton, preferredEdge: .minY)
    }

    private func refreshActiveModulePopover() {
        guard modulePopover.isShown,
              let moduleID = activePopoverModuleID,
              let module = appState.orderedModules.first(where: { $0.id == moduleID }) as? BaseMenuModule else {
            return
        }

        updateModulePopoverContent(for: module)
    }

    private func scheduleActivePopoverRefresh() {
        guard modulePopover.isShown, !popoverRefreshScheduled else { return }
        popoverRefreshScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.popoverRefreshScheduled = false
            self.refreshActiveModulePopover()
        }
    }

    private func updateModulePopoverContent(for module: BaseMenuModule) {
        var snapshot = modulePopoverContent.snapshot
        snapshot.title = appState.title(for: module)
        snapshot.value = module.displayValue.isEmpty ? "—" : module.displayValue
        snapshot.detail = moduleDetailText(for: module)
        if let disk = module as? DiskUsageModule {
            snapshot.showsScrollableDetail = disk.hoverMode == .volumes
        } else if let network = module as? NetworkModule {
            snapshot.showsScrollableDetail = network.hoverMode == .interface
        } else {
            snapshot.showsScrollableDetail = module is MemoryModule
        }
        if let cpu = module as? CPUModule, cpu.hoverMode == .perCore {
            let perCoreValues = cpu.perCorePercentages
            snapshot.showsPerCoreGrid = !perCoreValues.isEmpty
            snapshot.perCorePercentages = perCoreValues
        } else {
            snapshot.showsPerCoreGrid = false
            snapshot.perCorePercentages = []
        }
        modulePopoverContent.apply(snapshot: snapshot)
    }

    private func moduleDetailText(for module: BaseMenuModule) -> String {
        if let cpu = module as? CPUModule {
            return cpu.hoverText
        }
        if let memory = module as? MemoryModule {
            return memory.hoverText
        }
        if let disk = module as? DiskUsageModule {
            return disk.hoverText
        }
        if let network = module as? NetworkModule {
            return network.hoverText
        }
        if module is ClockModule {
            return clockDetailText(for: module.id, at: Date())
        }
        return "\(moduleShortLabel(for: module)) \(module.displayValue.isEmpty ? "—" : module.displayValue)"
    }

    private func clockDetailText(for moduleID: String, at date: Date) -> String {
        let timezone = resolvedClockTimeZone(for: moduleID)
        let dateFormatter = DateFormatter()
        dateFormatter.locale = .autoupdatingCurrent
        dateFormatter.timeZone = timezone
        dateFormatter.dateFormat = "EEEE, MMMM d"
        let dateText = dateFormatter.string(from: date)

        let timezoneName = fullTimeZoneName(for: timezone, at: date)
        let offsetText = utcOffsetText(for: timezone, at: date)

        return """
        \(dateText)
        \(timezoneName)
        \(offsetText)
        """
    }

    private func resolvedClockTimeZone(for moduleID: String) -> TimeZone {
        let settings = appState.clockSettings(for: moduleID)
        switch settings.timezoneMode {
        case .system:
            return .current
        case .utc:
            return TimeZone(secondsFromGMT: 0) ?? .current
        case .custom:
            if let id = settings.selectedTimezones.first, let timezone = TimeZone(identifier: id) {
                return timezone
            }
            return .current
        }
    }

    private func fullTimeZoneName(for timezone: TimeZone, at date: Date) -> String {
        let style: TimeZone.NameStyle = timezone.isDaylightSavingTime(for: date) ? .daylightSaving : .standard
        return timezone.localizedName(for: style, locale: .autoupdatingCurrent) ?? timezone.identifier
    }

    private func utcOffsetText(for timezone: TimeZone, at date: Date) -> String {
        let seconds = timezone.secondsFromGMT(for: date)
        let sign = seconds >= 0 ? "+" : "-"
        let absolute = abs(seconds)
        let hours = absolute / 3600
        let minutes = (absolute % 3600) / 60
        if minutes == 0 {
            return "UTC\(sign)\(hours)"
        }
        return String(format: "UTC%@%d:%02d", sign, hours, minutes)
    }

    private func showConfigurationWindow() {
        let windowController: NSWindowController
        if let existing = configurationWindowController, let window = existing.window {
            windowController = existing
            window.makeKeyAndOrderFront(nil)
            return
        }

        let rootView = ConfigurationView().environmentObject(appState)
        let hostingController = NSHostingController(rootView: rootView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 540),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "SystemStack Settings"
        window.contentViewController = hostingController
        window.minSize = NSSize(width: 500, height: 540)
        window.center()
        window.isReleasedWhenClosed = false
        window.level = .normal

        windowController = NSWindowController(window: window)
        configurationWindowController = windowController
        windowController.showWindow(nil)
    }
}

@MainActor
private final class ModulePopoverContent: ObservableObject {
    @Published private(set) var snapshot = ModulePopoverSnapshot()

    func apply(snapshot: ModulePopoverSnapshot) {
        guard self.snapshot != snapshot else { return }
        self.snapshot = snapshot
    }
}

private struct ModuleDetailPopoverView: View {
    @ObservedObject var content: ModulePopoverContent
    let openConfiguration: () -> Void
    let quitApp: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(content.snapshot.title)
                .font(.headline)

            Text(content.snapshot.value)
                .font(.title3)
                .fontWeight(.semibold)

            if content.snapshot.showsPerCoreGrid {
                CPUPerCoreGridView(values: content.snapshot.perCorePercentages)
            } else if content.snapshot.showsScrollableDetail {
                ScrollView(.vertical) {
                    detailTextUnbounded
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                detailText
            }

            Spacer(minLength: 4)

            Divider()

            HStack {
                Button("Settings", action: openConfiguration)
                Spacer()
                Button("Quit", action: quitApp)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 10)
        .frame(width: 280, height: 180, alignment: .topLeading)
    }

    private var detailText: some View {
        Text(content.snapshot.detail)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(8)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var detailTextUnbounded: some View {
        Text(content.snapshot.detail)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ModulePopoverSnapshot: Equatable {
    var title = ""
    var value = "—"
    var detail = ""
    var showsScrollableDetail = false
    var showsPerCoreGrid = false
    var perCorePercentages: [Double] = []
}

private struct CPUPerCoreGridView: View {
    let values: [Double]

    var body: some View {
        let columnCount = suggestedColumnCount(itemCount: values.count)
        let rows = gridRows(columnCount: columnCount)

        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, entry in
                            Text(entry)
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if row.count < columnCount {
                            ForEach(0 ..< (columnCount - row.count), id: \.self) { _ in
                                Text("")
                                    .font(.caption)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func suggestedColumnCount(itemCount: Int) -> Int {
        if itemCount <= 4 { return min(2, max(1, itemCount)) }
        if itemCount <= 8 { return 2 }
        if itemCount <= 16 { return 3 }
        return 4
    }

    private func gridRows(columnCount: Int) -> [[String]] {
        guard columnCount > 0 else { return [] }

        let entries = values.enumerated().map { index, value in
            String(format: "Core %2d: %3d%%", index + 1, Int(value.rounded()))
        }

        let rowCount = Int(ceil(Double(entries.count) / Double(columnCount)))
        var rows: [[String]] = Array(repeating: [], count: rowCount)

        for (index, entry) in entries.enumerated() {
            rows[index / columnCount].append(entry)
        }

        return rows
    }
}
