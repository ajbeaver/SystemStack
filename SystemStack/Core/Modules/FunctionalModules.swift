import Foundation
import IOKit.ps

final class ClockModule: BaseStubModule {
    var use24Hour: Bool
    var showSeconds: Bool

    init(isEnabled: Bool = true, use24Hour: Bool = ClockModule.defaultUse24Hour(), showSeconds: Bool = false) {
        self.use24Hour = use24Hour
        self.showSeconds = showSeconds
        super.init(id: "clock", title: "Clock", symbolName: "clock", isEnabled: isEnabled)
    }

    override func statusValueText() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent

        switch (use24Hour, showSeconds) {
        case (true, true):
            formatter.dateFormat = "HH:mm:ss"
        case (true, false):
            formatter.dateFormat = "HH:mm"
        case (false, true):
            formatter.dateFormat = "h:mm:ss a"
        case (false, false):
            formatter.dateFormat = "h:mm a"
        }

        return formatter.string(from: Date())
    }

    static func defaultUse24Hour() -> Bool {
        let format = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .autoupdatingCurrent) ?? ""
        return !format.contains("a")
    }
}

final class BatteryModule: BaseStubModule {
    init(isEnabled: Bool = false) {
        super.init(id: "battery", title: "Battery", symbolName: "battery.100", isEnabled: isEnabled)
    }

    override func statusValueText() -> String {
        guard let powerInfo = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let powerSources = IOPSCopyPowerSourcesList(powerInfo)?.takeRetainedValue() as? [CFTypeRef],
              let source = powerSources.first,
              let description = IOPSGetPowerSourceDescription(powerInfo, source)?.takeUnretainedValue() as? [String: Any],
              let current = description[kIOPSCurrentCapacityKey as String] as? Int,
              let max = description[kIOPSMaxCapacityKey as String] as? Int,
              max > 0 else {
            return "--"
        }

        let percent = Int((Double(current) / Double(max) * 100).rounded())
        return "\(percent)%"
    }
}

final class NetworkModule: BaseStubModule {
    init(isEnabled: Bool = false) {
        super.init(id: "network", title: "Network", symbolName: "arrow.up.arrow.down", isEnabled: isEnabled)
    }

    override func statusValueText() -> String {
        "U0 D0"
    }
}
