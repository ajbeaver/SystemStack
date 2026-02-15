import AppKit
import Combine
import SwiftUI

@MainActor
final class StatusBarController: NSObject {
    private let appState: AppState
    private let modulePopover = NSPopover()
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
        let rootView = ModuleDetailPopoverView(
            title: appState.title(for: module),
            value: module.displayValue.isEmpty ? "—" : module.displayValue,
            detail: moduleDetailText(for: module),
            openConfiguration: { [weak self] in
                self?.openConfiguration()
            },
            quitApp: { [weak self] in
                self?.quitApp()
            }
        )
        .environmentObject(appState)

        modulePopover.contentSize = NSSize(width: 280, height: 180)
        modulePopover.contentViewController = NSHostingController(rootView: rootView)
        modulePopover.show(relativeTo: anchorButton.bounds, of: anchorButton, preferredEdge: .minY)
    }

    private func refreshActiveModulePopover() {
        guard modulePopover.isShown,
              let moduleID = activePopoverModuleID,
              let module = appState.orderedModules.first(where: { $0.id == moduleID }) as? BaseMenuModule,
              let button = module.statusItem?.button else {
            return
        }

        showModulePopover(for: module, anchorButton: button)
    }

    private func moduleDetailText(for module: BaseMenuModule) -> String {
        if let cpu = module as? CPUModule {
            return cpu.hoverText
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

private struct ModuleDetailPopoverView: View {
    let title: String
    let value: String
    let detail: String
    let openConfiguration: () -> Void
    let quitApp: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)

            Text(value)
                .font(.title3)
                .fontWeight(.semibold)

            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            Spacer(minLength: 4)

            Divider()

            HStack {
                Button("Open Configuration", action: openConfiguration)
                Spacer()
                Button("Quit SystemStack", action: quitApp)
            }
        }
        .padding(12)
        .frame(width: 280, height: 180, alignment: .topLeading)
    }
}
