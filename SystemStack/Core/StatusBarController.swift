import AppKit
import Combine
import SwiftUI

@MainActor
final class StatusBarController: NSObject {
    private let appState: AppState
    private let popover = NSPopover()
    private let contextMenu = NSMenu()

    private var cancellables = Set<AnyCancellable>()
    private var cachedSymbolImages: [String: NSImage] = [:]
    private var lastOrderKey = ""
    private weak var activeAnchorButton: NSStatusBarButton?

    init(appState: AppState) {
        self.appState = appState
        super.init()
        configurePopover()
        configureContextMenu()
        observeState()
        syncStatusItems(rebuildOrder: true)
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 520, height: 560)
        popover.contentViewController = NSHostingController(
            rootView: ConfigurationView().environmentObject(appState)
        )
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
    }

    private func renderLayout() {
        let modules = appState.orderedModules.compactMap { $0 as? BaseMenuModule }.filter(\.isEnabled)
        guard !modules.isEmpty else { return }

        var mode = appState.appearanceSettings.displayMode
        applyVisuals(modules, mode: mode)

        if fitsWithinAvailableWidth(modules) {
            return
        }

        if appState.overflowBehavior == .iconOnlyFallback, mode != .iconOnly {
            mode = .iconOnly
            applyVisuals(modules, mode: mode)
            if fitsWithinAvailableWidth(modules) {
                return
            }
        }

        hideTrailingUntilFits(modules, mode: mode)
    }

    private func applyVisuals(_ modules: [BaseMenuModule], mode: AppState.DisplayMode) {
        for module in modules {
            module.statusItem?.isVisible = true
            updateStatusItem(
                for: module,
                mode: mode
            )
        }
    }

    private func updateStatusItem(
        for module: BaseMenuModule,
        mode: AppState.DisplayMode
    ) {
        guard let button = module.statusItem?.button else { return }

        let value = module.displayValue.isEmpty ? "—" : module.displayValue
        let image = mode == .valueOnly ? nil : moduleImage(for: module)

        switch mode {
        case .iconOnly:
            button.image = image
            button.title = image == nil ? value : ""
        case .valueOnly:
            button.image = nil
            button.title = value
        case .iconAndValue:
            button.image = image
            button.title = value
        }

        button.toolTip = value
    }

    private func moduleImage(for module: BaseMenuModule) -> NSImage? {
        guard let symbolName = module.symbolName else { return nil }
        let pointSize = symbolPointSize()
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

    private func symbolPointSize() -> CGFloat {
        switch appState.symbolSize {
        case .small:
            return 11
        case .standard:
            return 13
        }
    }

    private func hideTrailingUntilFits(_ modules: [BaseMenuModule], mode: AppState.DisplayMode) {
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
                updateStatusItem(for: module, mode: mode)
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

        activeAnchorButton = button

        if event.type == .rightMouseUp {
            NSMenu.popUpContextMenu(contextMenu, with: event, for: button)
            return
        }

        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    @objc private func openConfiguration() {
        if popover.isShown {
            popover.performClose(nil)
            return
        }

        guard let button = activeAnchorButton ?? firstVisibleButton() else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
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
}
