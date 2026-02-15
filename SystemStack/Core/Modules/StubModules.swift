import Foundation

final class CalendarModule: BaseStubModule {
    init(isEnabled: Bool = false) { super.init(id: "calendar", title: "Calendar", symbolName: "calendar", isEnabled: isEnabled) }
}

final class CPUUsageModule: BaseStubModule {
    init(isEnabled: Bool = true) { super.init(id: "cpu", title: "CPU", symbolName: "cpu", isEnabled: isEnabled) }

    override func statusValueText() -> String { "0%" }
}

final class MemoryModule: BaseStubModule {
    init(isEnabled: Bool = true) { super.init(id: "memory", title: "Memory", symbolName: "memorychip", isEnabled: isEnabled) }

    override func statusValueText() -> String { "0G" }
}

final class DiskUsageModule: BaseStubModule {
    init(isEnabled: Bool = false) { super.init(id: "disk", title: "Disk", symbolName: "internaldrive", isEnabled: isEnabled) }
}

final class NowPlayingModule: BaseStubModule {
    init(isEnabled: Bool = false) { super.init(id: "nowPlaying", title: "Now Playing", symbolName: "music.note", isEnabled: isEnabled) }
}

final class FocusModeModule: BaseStubModule {
    init(isEnabled: Bool = false) { super.init(id: "focus", title: "Focus", symbolName: "moon", isEnabled: isEnabled) }
}

final class VPNModule: BaseStubModule {
    init(isEnabled: Bool = false) { super.init(id: "vpn", title: "VPN", symbolName: "lock.shield", isEnabled: isEnabled) }
}

final class BluetoothModule: BaseStubModule {
    init(isEnabled: Bool = false) { super.init(id: "bluetooth", title: "Bluetooth", symbolName: "bluetooth", isEnabled: isEnabled) }
}

final class NotificationsCountModule: BaseStubModule {
    init(isEnabled: Bool = false) { super.init(id: "notifications", title: "Notifications", symbolName: "bell.badge", isEnabled: isEnabled) }
}

final class WeatherModule: BaseStubModule {
    init(isEnabled: Bool = false) { super.init(id: "weather", title: "Weather", symbolName: "cloud.sun", isEnabled: isEnabled) }
}

final class QuickActionsModule: BaseStubModule {
    init(isEnabled: Bool = false) { super.init(id: "quickActions", title: "Quick Actions", symbolName: "bolt", isEnabled: isEnabled) }
}

final class TimerModule: BaseStubModule {
    init(isEnabled: Bool = false) { super.init(id: "timer", title: "Timer", symbolName: "timer", isEnabled: isEnabled) }
}

final class ClipboardModule: BaseStubModule {
    init(isEnabled: Bool = false) { super.init(id: "clipboard", title: "Clipboard", symbolName: "doc.on.clipboard", isEnabled: isEnabled) }
}

final class CustomTextModule: BaseStubModule {
    var customValue: String

    init(isEnabled: Bool = false, customValue: String = "--") {
        self.customValue = customValue
        super.init(id: "customText", title: "Custom Text", symbolName: "text.cursor", isEnabled: isEnabled)
    }

    override func statusValueText() -> String {
        customValue
    }
}
