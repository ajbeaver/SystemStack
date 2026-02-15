import AppKit
import Combine
import SwiftUI

final class StatusBarController: NSObject {
    private let appState: AppState
    private let popover = NSPopover()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let contextMenu = NSMenu()

    private var cancellables = Set<AnyCancellable>()
    private var refreshTimer: Timer?

    init(appState: AppState) {
        self.appState = appState
        super.init()
        configurePopover()
        configureStatusItem()
        configureContextMenu()
        observeState()
        startRefreshTimer()
        updateStatusItemTitle()
    }

    deinit {
        refreshTimer?.invalidate()
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 330, height: 220)
        popover.contentViewController = NSHostingController(
            rootView: PopoverView().environmentObject(appState)
        )
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.image = nil
        button.title = ""
        button.action = #selector(handleStatusItemClick(_:))
        button.target = self
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
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
        appState.objectWillChange
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.updateStatusItemTitle()
                }
            }
            .store(in: &cancellables)
    }

    private func startRefreshTimer() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.appState.refreshStatusValues()
        }
        refreshTimer?.tolerance = 0.2
    }

    private func updateStatusItemTitle() {
        guard let button = statusItem.button else { return }
        let enabledModules = appState.enabledModules

        guard !enabledModules.isEmpty else {
            button.attributedTitle = NSAttributedString(string: "SystemStack")
            return
        }

        let output = NSMutableAttributedString()

        for (index, module) in enabledModules.enumerated() {
            if index > 0 {
                output.append(NSAttributedString(string: appState.menuBarSeparatorText()))
            }
            appendSegment(for: module, to: output)
        }

        button.attributedTitle = output
    }

    private func appendSegment(for module: any MenuModule, to text: NSMutableAttributedString) {
        let valueText = module.statusValueText()

        switch appState.appearanceSettings.displayMode {
        case .iconOnly:
            if !appendSymbol(module.symbolName, to: text) {
                text.append(NSAttributedString(string: valueText))
            }
        case .valueOnly:
            text.append(NSAttributedString(string: valueText))
        case .iconAndValue:
            let addedIcon = appendSymbol(module.symbolName, to: text)
            if addedIcon {
                text.append(NSAttributedString(string: " "))
            }
            text.append(NSAttributedString(string: valueText))
        }
    }

    @discardableResult
    private func appendSymbol(_ symbolName: String?, to text: NSMutableAttributedString) -> Bool {
        guard let symbolName,
              let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) else {
            return false
        }

        image.size = NSSize(width: 11, height: 11)
        let attachment = NSTextAttachment()
        attachment.image = image
        text.append(NSAttributedString(attachment: attachment))
        return true
    }

    @objc private func handleStatusItemClick(_ sender: Any?) {
        guard let event = NSApp.currentEvent, let button = statusItem.button else { return }

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
        appState.openConfigurationWindow()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
