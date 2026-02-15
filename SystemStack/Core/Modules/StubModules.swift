import Foundation

final class CalendarModule: BaseMenuModule, @unchecked Sendable {
    init(isEnabled: Bool = false) { super.init(id: "calendar", title: "Calendar", symbolName: "calendar", isEnabled: isEnabled) }
}

final class NowPlayingModule: BaseMenuModule, @unchecked Sendable {
    init(isEnabled: Bool = false) { super.init(id: "nowPlaying", title: "Now Playing", symbolName: "music.note", isEnabled: isEnabled) }
}

final class FocusModeModule: BaseMenuModule, @unchecked Sendable {
    init(isEnabled: Bool = false) { super.init(id: "focus", title: "Focus", symbolName: "moon", isEnabled: isEnabled) }
}

final class VPNModule: BaseMenuModule, @unchecked Sendable {
    init(isEnabled: Bool = false) { super.init(id: "vpn", title: "VPN", symbolName: "lock.shield", isEnabled: isEnabled) }
}

final class BluetoothModule: BaseMenuModule, @unchecked Sendable {
    init(isEnabled: Bool = false) { super.init(id: "bluetooth", title: "Bluetooth", symbolName: "bluetooth", isEnabled: isEnabled) }
}

final class NotificationsCountModule: BaseMenuModule, @unchecked Sendable {
    init(isEnabled: Bool = false) { super.init(id: "notifications", title: "Notifications", symbolName: "bell.badge", isEnabled: isEnabled) }
}

final class WeatherModule: BaseMenuModule, @unchecked Sendable {
    init(isEnabled: Bool = false) { super.init(id: "weather", title: "Weather", symbolName: "cloud.sun", isEnabled: isEnabled) }
}

final class QuickActionsModule: BaseMenuModule, @unchecked Sendable {
    init(isEnabled: Bool = false) { super.init(id: "quickActions", title: "Quick Actions", symbolName: "bolt", isEnabled: isEnabled) }
}

final class TimerModule: BaseMenuModule, @unchecked Sendable {
    init(isEnabled: Bool = false) { super.init(id: "timer", title: "Timer", symbolName: "timer", isEnabled: isEnabled) }
}

final class ClipboardModule: BaseMenuModule, @unchecked Sendable {
    init(isEnabled: Bool = false) { super.init(id: "clipboard", title: "Clipboard", symbolName: "doc.on.clipboard", isEnabled: isEnabled) }
}

final class CustomTextModule: BaseMenuModule, @unchecked Sendable {
    var customValue: String

    init(isEnabled: Bool = false, customValue: String = "—") {
        self.customValue = customValue
        super.init(id: "customText", title: "Custom Text", symbolName: "text.cursor", isEnabled: isEnabled, defaultDisplayValue: customValue)
    }

    override func update() async -> Bool {
        setDisplayValueIfChanged(customValue)
    }
}
