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
    private var lastOrderKey = ""
    private var activePopoverModuleID: String?
    private var configurationWindowController: NSWindowController?

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

        if rebuildOrder {
            for module in modules {
                if let item = module.statusItem {
                    NSStatusBar.system.removeStatusItem(item)
                    module.statusItem = nil
                }
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
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        module.statusItem = item

        guard let button = item.button else { return }
        button.image = nil
        button.title = ""
        button.identifier = NSUserInterfaceItemIdentifier(module.id)
        button.action = #selector(handleModuleClick(_:))
        button.target = self
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func updateVisibleModuleItems() {
        renderLayout()
        refreshActiveModulePopover()
    }

    private func renderLayout() {
        let modules = appState.orderedModules.compactMap { $0 as? BaseMenuModule }.filter(\.isEnabled)
        guard !modules.isEmpty else { return }

        var forceHideValues = false
        applyVisuals(modules, forceHideValues: forceHideValues)

        if fitsWithinAvailableWidth(modules) {
            return
        }

        if appState.overflowBehavior == .iconOnlyFallback {
            forceHideValues = true
            applyVisuals(modules, forceHideValues: forceHideValues)
            if fitsWithinAvailableWidth(modules) {
                return
            }
        }

        hideTrailingUntilFits(modules, forceHideValues: forceHideValues)
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

    private func updateModulePopoverContent(for module: BaseMenuModule) {
        modulePopoverContent.title = appState.title(for: module)
        modulePopoverContent.value = module.displayValue.isEmpty ? "—" : module.displayValue
        modulePopoverContent.detail = moduleDetailText(for: module)
        modulePopoverContent.showsScrollableDetail = module is MemoryModule
        if let cpu = module as? CPUModule, cpu.hoverMode == .perCore {
            let perCoreValues = cpu.perCorePercentages
            modulePopoverContent.showsPerCoreGrid = !perCoreValues.isEmpty
            modulePopoverContent.perCorePercentages = perCoreValues
        } else {
            modulePopoverContent.showsPerCoreGrid = false
            modulePopoverContent.perCorePercentages = []
        }
    }

    private func moduleDetailText(for module: BaseMenuModule) -> String {
        if let cpu = module as? CPUModule {
            return cpu.hoverText
        }
        if let memory = module as? MemoryModule {
            return memory.hoverText
        }
        return "\(moduleShortLabel(for: module)) \(module.displayValue.isEmpty ? "—" : module.displayValue)"
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
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 560),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "SystemStack Configuration"
        window.contentViewController = hostingController
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
    @Published var title = ""
    @Published var value = "—"
    @Published var detail = ""
    @Published var showsScrollableDetail = false
    @Published var showsPerCoreGrid = false
    @Published var perCorePercentages: [Double] = []
}

private struct ModuleDetailPopoverView: View {
    @ObservedObject var content: ModulePopoverContent
    let openConfiguration: () -> Void
    let quitApp: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(content.title)
                .font(.headline)

            Text(content.value)
                .font(.title3)
                .fontWeight(.semibold)

            if content.showsPerCoreGrid {
                CPUPerCoreGridView(values: content.perCorePercentages)
            } else if content.showsScrollableDetail {
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
        .padding(12)
        .frame(width: 280, height: 180, alignment: .topLeading)
    }

    private var detailText: some View {
        Text(content.detail)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(8)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var detailTextUnbounded: some View {
        Text(content.detail)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CPUPerCoreGridView: View {
    let values: [Double]

    var body: some View {
        GeometryReader { proxy in
            let columnCount = suggestedColumnCount(for: proxy.size.width, itemCount: values.count)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func suggestedColumnCount(for width: CGFloat, itemCount: Int) -> Int {
        if itemCount <= 4 { return min(2, max(1, itemCount)) }
        if width >= 300 { return 4 }
        if width >= 220 { return 3 }
        return 2
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
