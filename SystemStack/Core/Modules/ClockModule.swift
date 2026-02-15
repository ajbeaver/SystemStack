import Foundation

enum TimezoneMode: String, CaseIterable, Sendable {
    case system
    case utc
    case custom
    case world
}

enum TimezoneLabelStyle: String, CaseIterable, Sendable {
    case short
    case compact
}

struct ClockSettings: Sendable {
    var isEnabled: Bool
    var use24Hour: Bool
    var showSeconds: Bool
    var showAMPM: Bool
    var timezoneMode: TimezoneMode
    var showTimezoneLabel: Bool
    var timezoneLabelStyle: TimezoneLabelStyle
    var selectedTimezones: [String]

    static func `default`(isEnabled: Bool = true) -> ClockSettings {
        ClockSettings(
            isEnabled: isEnabled,
            use24Hour: ClockModule.defaultUse24Hour(),
            showSeconds: false,
            showAMPM: true,
            timezoneMode: .system,
            showTimezoneLabel: true,
            timezoneLabelStyle: .short,
            selectedTimezones: []
        )
    }
}

private actor ClockRuntime {
    private var settings: ClockSettings
    private var formatterByTimeZoneID: [String: DateFormatter] = [:]
    private var formatterNeedsRebuild = true
    private var forceRefresh = true
    private var lastBucket: Int64?

    init(settings: ClockSettings) {
        self.settings = settings
    }

    func applySettings(_ newSettings: ClockSettings) {
        var normalized = newSettings
        normalized.selectedTimezones = Array(normalized.selectedTimezones.prefix(4))

        let changed = settings.use24Hour != normalized.use24Hour
            || settings.showSeconds != normalized.showSeconds
            || settings.showAMPM != normalized.showAMPM
            || settings.timezoneMode != normalized.timezoneMode
            || settings.showTimezoneLabel != normalized.showTimezoneLabel
            || settings.timezoneLabelStyle != normalized.timezoneLabelStyle
            || settings.selectedTimezones != normalized.selectedTimezones
            || settings.isEnabled != normalized.isEnabled

        settings = normalized

        guard changed else { return }
        formatterNeedsRebuild = true
        forceRefresh = true
        lastBucket = nil
    }

    func markFormatterCacheDirty() {
        formatterNeedsRebuild = true
        forceRefresh = true
        lastBucket = nil
    }

    func nextDisplayValue(at date: Date) -> String? {
        let timestamp = date.timeIntervalSince1970
        let bucket = settings.showSeconds ? Int64(timestamp.rounded(.down)) : Int64((timestamp / 60.0).rounded(.down))

        if !forceRefresh, lastBucket == bucket {
            return nil
        }

        lastBucket = bucket
        rebuildFormattersIfNeeded()

        let output = formatDisplayValue(for: date)
        forceRefresh = false
        return output
    }

    private func rebuildFormattersIfNeeded() {
        guard formatterNeedsRebuild else { return }

        var timezoneIDs = resolvedTimezoneIDs(for: settings)
        if settings.timezoneMode == .system {
            timezoneIDs = ["system"]
        }

        var newFormatters: [String: DateFormatter] = [:]
        for id in timezoneIDs {
            guard let timezone = resolveTimeZone(for: id, mode: settings.timezoneMode) else { continue }
            let formatter = DateFormatter()
            formatter.locale = .autoupdatingCurrent
            formatter.timeZone = timezone
            formatter.dateFormat = clockDateFormat(using: settings)
            newFormatters[id] = formatter
        }

        if newFormatters.isEmpty {
            let formatter = DateFormatter()
            formatter.locale = .autoupdatingCurrent
            formatter.timeZone = .current
            formatter.dateFormat = clockDateFormat(using: settings)
            newFormatters["system"] = formatter
        }

        formatterByTimeZoneID = newFormatters
        formatterNeedsRebuild = false
    }

    private func formatDisplayValue(for date: Date) -> String {
        switch settings.timezoneMode {
        case .system:
            let value = formatted(date: date, timezoneID: "system") ?? "—"
            guard settings.showTimezoneLabel else { return value }
            let label = shortZoneLabel(for: "system", at: date)
            return "\(value) \(label)"

        case .utc:
            let value = formatted(date: date, timezoneID: "UTC") ?? "—"
            guard settings.showTimezoneLabel else { return value }

            switch settings.timezoneLabelStyle {
            case .short:
                return "\(value) UTC"
            case .compact:
                return settings.use24Hour ? "\(value)Z" : "\(value) UTC"
            }

        case .custom:
            let ids = resolvedTimezoneIDs(for: settings)
            guard let id = ids.first else {
                let fallback = formatted(date: date, timezoneID: "system") ?? "—"
                guard settings.showTimezoneLabel else { return fallback }
                let label = shortZoneLabel(for: "system", at: date)
                return "\(fallback) \(label)"
            }
            let value = formatted(date: date, timezoneID: id) ?? "—"
            guard settings.showTimezoneLabel else { return value }
            let label = shortZoneLabel(for: id, at: date)
            return "\(value) \(label)"

        case .world:
            let ids = resolvedTimezoneIDs(for: settings)
            if ids.isEmpty {
                let fallback = formatted(date: date, timezoneID: "system") ?? "—"
                guard settings.showTimezoneLabel else { return fallback }
                let label = shortZoneLabel(for: "system", at: date)
                return "\(fallback) \(label)"
            }

            let parts = ids.compactMap { id -> String? in
                guard let value = formatted(date: date, timezoneID: id) else { return nil }
                guard settings.showTimezoneLabel else { return value }
                let label = shortZoneLabel(for: id, at: date)
                return "\(value) \(label)"
            }

            guard !parts.isEmpty else { return "—" }
            let joined = parts.joined(separator: " | ")
            if joined.count > 60 {
                return String(joined.prefix(59)) + "…"
            }
            return joined
        }
    }

    private func formatted(date: Date, timezoneID: String) -> String? {
        let formatter = formatterByTimeZoneID[timezoneID] ?? formatterByTimeZoneID["system"]
        return formatter?.string(from: date)
    }

    private func resolvedTimezoneIDs(for settings: ClockSettings) -> [String] {
        switch settings.timezoneMode {
        case .system:
            return ["system"]
        case .utc:
            return ["UTC"]
        case .custom:
            if let first = settings.selectedTimezones.first,
               TimeZone(identifier: first) != nil {
                return [first]
            }
            return ["system"]
        case .world:
            let ids = settings.selectedTimezones
                .filter { TimeZone(identifier: $0) != nil }
            return ids.isEmpty ? ["system"] : Array(ids.prefix(4))
        }
    }

    private func resolveTimeZone(for id: String, mode: TimezoneMode) -> TimeZone? {
        switch id {
        case "system":
            return .current
        case "UTC":
            return TimeZone(secondsFromGMT: 0)
        default:
            if mode == .utc {
                return TimeZone(secondsFromGMT: 0)
            }
            return TimeZone(identifier: id)
        }
    }

    private func shortZoneLabel(for timezoneID: String, at date: Date) -> String {
        if timezoneID == "system" {
            let current = TimeZone.current
            if let abbreviation = current.abbreviation(for: date), !abbreviation.isEmpty {
                return abbreviation.uppercased()
            }
            return "LOCAL"
        }

        if timezoneID == "UTC" {
            return "UTC"
        }

        guard let timezone = TimeZone(identifier: timezoneID) else {
            return "TZ"
        }

        if let abbreviation = timezone.abbreviation(for: date), !abbreviation.isEmpty {
            return abbreviation.uppercased()
        }

        let city = timezoneID.split(separator: "/").last.map(String.init) ?? timezoneID
        let words = city.replacingOccurrences(of: "_", with: " ").split(separator: " ")
        if words.count >= 2 {
            let initials = words.compactMap { $0.first }.map(String.init).joined().uppercased()
            if !initials.isEmpty { return initials }
        }

        return String(city.prefix(3)).uppercased()
    }

    private func clockDateFormat(using settings: ClockSettings) -> String {
        if settings.use24Hour {
            return settings.showSeconds ? "HH:mm:ss" : "HH:mm"
        }

        let time = settings.showSeconds ? "h:mm:ss" : "h:mm"
        return settings.showAMPM ? "\(time) a" : time
    }
}

final class ClockModule: BaseMenuModule, @unchecked Sendable {
    private let runtime: ClockRuntime

    private let showSecondsLock = NSLock()
    private var showSecondsValue: Bool

    private var timezoneObserver: NSObjectProtocol?
    private var localeObserver: NSObjectProtocol?

    var showSeconds: Bool {
        showSecondsLock.lock()
        defer { showSecondsLock.unlock() }
        return showSecondsValue
    }

    init(isEnabled: Bool = true, settings: ClockSettings? = nil) {
        let resolved = settings ?? .default(isEnabled: isEnabled)
        self.runtime = ClockRuntime(settings: resolved)
        self.showSecondsValue = resolved.showSeconds

        super.init(id: "clock", title: "Clock", symbolName: "clock", isEnabled: isEnabled, defaultDisplayValue: "—")

        self.isEnabled = resolved.isEnabled
        registerSystemObservers()
    }

    deinit {
        if let timezoneObserver {
            NotificationCenter.default.removeObserver(timezoneObserver)
        }
        if let localeObserver {
            NotificationCenter.default.removeObserver(localeObserver)
        }
    }

    func applySettings(_ newSettings: ClockSettings) {
        var normalized = newSettings
        normalized.selectedTimezones = Array(normalized.selectedTimezones.prefix(4))

        isEnabled = normalized.isEnabled

        showSecondsLock.lock()
        showSecondsValue = normalized.showSeconds
        showSecondsLock.unlock()

        Task {
            await runtime.applySettings(normalized)
        }
    }

    override func update() async -> Bool {
        guard let output = await runtime.nextDisplayValue(at: Date()) else {
            return false
        }

        return setDisplayValueIfChanged(output)
    }

    private func registerSystemObservers() {
        timezoneObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name.NSSystemTimeZoneDidChange,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            Task {
                await self.runtime.markFormatterCacheDirty()
            }
        }

        localeObserver = NotificationCenter.default.addObserver(
            forName: NSLocale.currentLocaleDidChangeNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            Task {
                await self.runtime.markFormatterCacheDirty()
            }
        }
    }

    static func defaultUse24Hour() -> Bool {
        let format = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .autoupdatingCurrent) ?? ""
        return !format.contains("a")
    }
}
