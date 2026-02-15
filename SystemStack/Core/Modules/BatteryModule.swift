import AppKit
import Foundation

final class BatteryModule: BaseMenuModule, @unchecked Sendable {
    var fullDisplayValue: String { "Battery (disabled)" }
    var statusImage: NSImage? { nil }

    init(isEnabled: Bool = false) {
        super.init(
            id: "battery",
            title: "Battery",
            symbolName: "battery.100",
            isEnabled: isEnabled,
            defaultDisplayValue: "--"
        )
    }

    override func update() async -> Bool {
        false
    }
}
