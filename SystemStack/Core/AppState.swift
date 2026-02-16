import Combine
import Foundation
import SwiftUI

final class AppState: ObservableObject {
    static let maxClockModules = 3

    enum StatusEvent {
        case valuesChanged
        case layoutChanged
    }

    static let shared = AppState()

    let statusEvents = PassthroughSubject<StatusEvent, Never>()

    @Published private(set) var orderedModules: [any MenuModule]
    @Published private var clockSettingsByModuleID: [String: ClockSettings]

    private let updateEngine = UpdateEngine()
    private static let persistenceKey = "SystemStack.AppState.v1"

    private struct PersistedState: Codable {
        struct CPUConfig: Codable {
            var mode: String
            var showUser: Bool
            var showSystem: Bool
        }

        struct MemoryConfig: Codable {
            var showUsed: Bool
            var showAvailable: Bool
            var showSwapUsed: Bool
        }

        struct DiskConfig: Codable {
            var mode: String
            var showUsed: Bool
            var showAvailable: Bool
            var showTotal: Bool
            var showVolumeList: Bool
        }

        struct NetworkConfig: Codable {
            var mode: String
            var speedUnitMode: String
            var fixedSpeedUnit: String
        }

        var moduleOrder: [String]
        var moduleEnabled: [String: Bool]
        var moduleShowsValue: [String: Bool]
        var clockSettingsByModuleID: [String: ClockSettings]
        var cpuConfigByModuleID: [String: CPUConfig]
        var memoryConfigByModuleID: [String: MemoryConfig]
        var diskConfigByModuleID: [String: DiskConfig]
        var networkConfigByModuleID: [String: NetworkConfig]
    }

    init() {
        let defaults = AppState.defaultModules()
        let defaultClockSettings = ["clock": ClockSettings.default(isEnabled: true)]

        if let persisted = Self.loadPersistedState() {
            let restored = Self.restoreState(from: persisted, defaults: defaults, defaultClockSettings: defaultClockSettings)
            orderedModules = restored.modules
            clockSettingsByModuleID = restored.clockSettings
            if restored.didNormalize {
                persistState()
            }
        } else {
            orderedModules = defaults
            clockSettingsByModuleID = defaultClockSettings
        }

        _ = normalizeClockStateInMemory()
        startEngine()
    }

    deinit {
        let engine = updateEngine
        Task {
            await engine.stop()
        }
    }

    func title(for module: any MenuModule) -> String {
        if let titled = module as? any TitledMenuModule {
            return titled.title
        }
        return module.id.capitalized
    }

    func modules(matching query: String) -> [any MenuModule] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return orderedModules }

        return orderedModules.filter { module in
            let titleText = title(for: module)
            return titleText.localizedCaseInsensitiveContains(text)
                || module.id.localizedCaseInsensitiveContains(text)
        }
    }

    func setModuleEnabled(id: String, isEnabled: Bool) {
        guard let index = orderedModules.firstIndex(where: { $0.id == id }) else { return }
        orderedModules[index].isEnabled = isEnabled

        if var settings = clockSettingsByModuleID[id] {
            settings.isEnabled = isEnabled
            clockSettingsByModuleID[id] = settings
            if let clockModule = orderedModules[index] as? ClockModule {
                clockModule.applySettings(settings)
            }
        }

        Task {
            await updateEngine.setModules(orderedModules)
        }

        persistState()
        statusEvents.send(.layoutChanged)
        objectWillChange.send()
    }

    func clockSettings(for moduleID: String) -> ClockSettings {
        clockSettingsByModuleID[moduleID] ?? .default(isEnabled: true)
    }

    func addClockModule(after moduleID: String?) {
        guard clockModuleCount() < Self.maxClockModules else { return }

        let sourceID: String
        if let moduleID, isClockModuleID(moduleID) {
            sourceID = moduleID
        } else {
            sourceID = "clock"
        }
        let sourceSettings = clockSettingsByModuleID[sourceID] ?? .default(isEnabled: true)
        let newID = nextClockModuleID()

        let newClock = ClockModule(
            id: newID,
            title: "Clock",
            isEnabled: sourceSettings.isEnabled,
            settings: sourceSettings
        )

        let insertIndex = (orderedModules.lastIndex(where: { $0.id.hasPrefix("clock") }) ?? -1) + 1

        orderedModules.insert(newClock, at: insertIndex)
        clockSettingsByModuleID[newID] = sourceSettings
        _ = normalizeClockStateInMemory()

        Task {
            await updateEngine.setModules(orderedModules)
        }

        persistState()
        statusEvents.send(.layoutChanged)
        objectWillChange.send()
    }

    func canAddClockModule() -> Bool {
        clockModuleCount() < Self.maxClockModules
    }

    func removeClockModule(id: String) {
        guard isGeneratedClockID(id) else { return }
        guard let index = orderedModules.firstIndex(where: { $0.id == id }) else { return }

        orderedModules.remove(at: index)
        clockSettingsByModuleID.removeValue(forKey: id)
        _ = normalizeClockStateInMemory()

        Task {
            await updateEngine.setModules(orderedModules)
        }

        persistState()
        statusEvents.send(.layoutChanged)
        objectWillChange.send()
    }

    func setModuleShowsValue(id: String, showsValue: Bool) {
        guard let index = orderedModules.firstIndex(where: { $0.id == id }) else { return }
        orderedModules[index].showsValue = showsValue
        persistState()
        statusEvents.send(.layoutChanged)
        objectWillChange.send()
    }

    func cpuHoverMode(id: String) -> CPUModule.HoverMode {
        guard let cpu = orderedModules.first(where: { $0.id == id }) as? CPUModule else {
            return .sparkline
        }
        return cpu.hoverMode
    }

    func setCPUHoverMode(id: String, mode: CPUModule.HoverMode) {
        guard let cpu = orderedModules.first(where: { $0.id == id }) as? CPUModule else { return }
        cpu.hoverMode = mode
        persistState()
        statusEvents.send(.valuesChanged)
        objectWillChange.send()
    }

    func cpuShowsSparklineUser(id: String) -> Bool {
        guard let cpu = orderedModules.first(where: { $0.id == id }) as? CPUModule else {
            return true
        }
        return cpu.showsSparklineUser
    }

    func setCPUShowsSparklineUser(id: String, shows: Bool) {
        guard let cpu = orderedModules.first(where: { $0.id == id }) as? CPUModule else { return }
        cpu.showsSparklineUser = shows
        persistState()
        statusEvents.send(.valuesChanged)
        objectWillChange.send()
    }

    func cpuShowsSparklineSystem(id: String) -> Bool {
        guard let cpu = orderedModules.first(where: { $0.id == id }) as? CPUModule else {
            return true
        }
        return cpu.showsSparklineSystem
    }

    func setCPUShowsSparklineSystem(id: String, shows: Bool) {
        guard let cpu = orderedModules.first(where: { $0.id == id }) as? CPUModule else { return }
        cpu.showsSparklineSystem = shows
        persistState()
        statusEvents.send(.valuesChanged)
        objectWillChange.send()
    }

    func memoryShowsUsed(id: String) -> Bool {
        guard let memory = orderedModules.first(where: { $0.id == id }) as? MemoryModule else {
            return true
        }
        return memory.showsUsed
    }

    func setMemoryShowsUsed(id: String, shows: Bool) {
        guard let memory = orderedModules.first(where: { $0.id == id }) as? MemoryModule else { return }
        memory.showsUsed = shows
        persistState()
        statusEvents.send(.valuesChanged)
        objectWillChange.send()
    }

    func memoryShowsAvailable(id: String) -> Bool {
        guard let memory = orderedModules.first(where: { $0.id == id }) as? MemoryModule else {
            return true
        }
        return memory.showsAvailable
    }

    func setMemoryShowsAvailable(id: String, shows: Bool) {
        guard let memory = orderedModules.first(where: { $0.id == id }) as? MemoryModule else { return }
        memory.showsAvailable = shows
        persistState()
        statusEvents.send(.valuesChanged)
        objectWillChange.send()
    }

    func memoryShowsSwapUsed(id: String) -> Bool {
        guard let memory = orderedModules.first(where: { $0.id == id }) as? MemoryModule else {
            return true
        }
        return memory.showsSwapUsed
    }

    func setMemoryShowsSwapUsed(id: String, shows: Bool) {
        guard let memory = orderedModules.first(where: { $0.id == id }) as? MemoryModule else { return }
        memory.showsSwapUsed = shows
        persistState()
        statusEvents.send(.valuesChanged)
        objectWillChange.send()
    }

    func diskHoverMode(id: String) -> DiskUsageModule.HoverMode {
        guard let disk = orderedModules.first(where: { $0.id == id }) as? DiskUsageModule else {
            return .capacity
        }
        return disk.hoverMode
    }

    func setDiskHoverMode(id: String, mode: DiskUsageModule.HoverMode) {
        guard let disk = orderedModules.first(where: { $0.id == id }) as? DiskUsageModule else { return }
        disk.hoverMode = mode
        persistState()
        statusEvents.send(.valuesChanged)
        objectWillChange.send()
    }

    func diskShowsCapacityUsed(id: String) -> Bool {
        guard let disk = orderedModules.first(where: { $0.id == id }) as? DiskUsageModule else {
            return true
        }
        return disk.showsCapacityUsed
    }

    func setDiskShowsCapacityUsed(id: String, shows: Bool) {
        guard let disk = orderedModules.first(where: { $0.id == id }) as? DiskUsageModule else { return }
        disk.showsCapacityUsed = shows
        persistState()
        statusEvents.send(.valuesChanged)
        objectWillChange.send()
    }

    func diskShowsCapacityAvailable(id: String) -> Bool {
        guard let disk = orderedModules.first(where: { $0.id == id }) as? DiskUsageModule else {
            return true
        }
        return disk.showsCapacityAvailable
    }

    func setDiskShowsCapacityAvailable(id: String, shows: Bool) {
        guard let disk = orderedModules.first(where: { $0.id == id }) as? DiskUsageModule else { return }
        disk.showsCapacityAvailable = shows
        persistState()
        statusEvents.send(.valuesChanged)
        objectWillChange.send()
    }

    func diskShowsCapacityTotal(id: String) -> Bool {
        guard let disk = orderedModules.first(where: { $0.id == id }) as? DiskUsageModule else {
            return true
        }
        return disk.showsCapacityTotal
    }

    func setDiskShowsCapacityTotal(id: String, shows: Bool) {
        guard let disk = orderedModules.first(where: { $0.id == id }) as? DiskUsageModule else { return }
        disk.showsCapacityTotal = shows
        persistState()
        statusEvents.send(.valuesChanged)
        objectWillChange.send()
    }

    func diskShowsVolumeList(id: String) -> Bool {
        guard let disk = orderedModules.first(where: { $0.id == id }) as? DiskUsageModule else {
            return true
        }
        return disk.showsVolumeList
    }

    func setDiskShowsVolumeList(id: String, shows: Bool) {
        guard let disk = orderedModules.first(where: { $0.id == id }) as? DiskUsageModule else { return }
        disk.showsVolumeList = shows
        persistState()
        statusEvents.send(.valuesChanged)
        objectWillChange.send()
    }

    func networkHoverMode(id: String) -> NetworkModule.HoverMode {
        guard let network = orderedModules.first(where: { $0.id == id }) as? NetworkModule else {
            return .throughput
        }
        return network.hoverMode
    }

    func setNetworkHoverMode(id: String, mode: NetworkModule.HoverMode) {
        guard let network = orderedModules.first(where: { $0.id == id }) as? NetworkModule else { return }
        network.hoverMode = mode
        persistState()
        statusEvents.send(.valuesChanged)
        objectWillChange.send()
    }

    func networkSpeedUnitMode(id: String) -> NetworkModule.SpeedUnitMode {
        guard let network = orderedModules.first(where: { $0.id == id }) as? NetworkModule else {
            return .auto
        }
        return network.speedUnitMode
    }

    func setNetworkSpeedUnitMode(id: String, mode: NetworkModule.SpeedUnitMode) {
        guard let network = orderedModules.first(where: { $0.id == id }) as? NetworkModule else { return }
        network.speedUnitMode = mode
        persistState()
        statusEvents.send(.valuesChanged)
        objectWillChange.send()
    }

    func networkFixedSpeedUnit(id: String) -> NetworkModule.FixedSpeedUnit {
        guard let network = orderedModules.first(where: { $0.id == id }) as? NetworkModule else {
            return .mbps
        }
        return network.fixedSpeedUnit
    }

    func setNetworkFixedSpeedUnit(id: String, unit: NetworkModule.FixedSpeedUnit) {
        guard let network = orderedModules.first(where: { $0.id == id }) as? NetworkModule else { return }
        network.fixedSpeedUnit = unit
        persistState()
        statusEvents.send(.valuesChanged)
        objectWillChange.send()
    }

    func updateClockSettings(moduleID: String, _ mutate: (inout ClockSettings) -> Void) {
        var updated = clockSettingsByModuleID[moduleID] ?? .default(isEnabled: true)
        mutate(&updated)
        updated.selectedTimezones = Array(updated.selectedTimezones.prefix(1))

        if let clockEnabled = orderedModules.first(where: { $0.id == moduleID })?.isEnabled {
            updated.isEnabled = clockEnabled
        }

        clockSettingsByModuleID[moduleID] = updated

        if let clockModule = orderedModules.first(where: { $0.id == moduleID }) as? ClockModule {
            clockModule.applySettings(updated)
        }

        persistState()
        statusEvents.send(.layoutChanged)
        objectWillChange.send()
    }

    func resetToDefaults() {
        orderedModules = AppState.defaultModules()
        clockSettingsByModuleID = ["clock": .default(isEnabled: true)]

        Task {
            await updateEngine.setModules(orderedModules)
        }

        persistState()
        statusEvents.send(.layoutChanged)
        objectWillChange.send()
    }

    private func startEngine() {
        let statusEvents = self.statusEvents
        Task {
            await updateEngine.setModules(orderedModules)
            await updateEngine.start {
                statusEvents.send(.valuesChanged)
            }
        }
    }

    private static func defaultModules() -> [any MenuModule] {
        [
            ClockModule(id: "clock", title: "Clock", isEnabled: true, settings: .default(isEnabled: true)),
            CPUModule(isEnabled: true),
            MemoryModule(isEnabled: true),
            NetworkModule(isEnabled: false),
            DiskUsageModule(isEnabled: false)
        ]
    }

    private func nextClockModuleID() -> String {
        var index = 1
        while orderedModules.contains(where: { $0.id == "clock.\(index)" }) {
            index += 1
        }
        return "clock.\(index)"
    }

    private func clockModuleCount() -> Int {
        orderedModules.reduce(into: 0) { count, module in
            if isClockModuleID(module.id) {
                count += 1
            }
        }
    }

    private static func isGeneratedClockID(_ id: String) -> Bool {
        guard id.hasPrefix("clock.") else { return false }
        let suffix = id.dropFirst("clock.".count)
        guard !suffix.isEmpty, suffix.first != "0" else { return false }
        return suffix.allSatisfy(\.isNumber)
    }

    private static func isClockModuleID(_ id: String) -> Bool {
        id == "clock" || isGeneratedClockID(id)
    }

    private func isGeneratedClockID(_ id: String) -> Bool {
        Self.isGeneratedClockID(id)
    }

    private func isClockModuleID(_ id: String) -> Bool {
        Self.isClockModuleID(id)
    }

    @discardableResult
    private func normalizeClockStateInMemory() -> Bool {
        let originalOrder = orderedModules.map(\.id)
        let originalSettingsKeys = Set(clockSettingsByModuleID.keys)
        var normalizedModules: [any MenuModule] = []
        var seenIDs = Set<String>()
        var keptGenerated = 0
        var sawDefaultClock = false
        var didChange = false

        for module in orderedModules {
            let id = module.id
            if seenIDs.contains(id) {
                didChange = true
                continue
            }
            seenIDs.insert(id)

            if id == "clock" {
                if sawDefaultClock {
                    didChange = true
                    continue
                }
                sawDefaultClock = true
                normalizedModules.append(module)
                continue
            }

            if Self.isGeneratedClockID(id) {
                if keptGenerated < (Self.maxClockModules - 1) {
                    keptGenerated += 1
                    normalizedModules.append(module)
                } else {
                    didChange = true
                }
                continue
            }

            if id.hasPrefix("clock") {
                didChange = true
                continue
            }

            normalizedModules.append(module)
        }

        if !sawDefaultClock {
            normalizedModules.insert(
                ClockModule(id: "clock", title: "Clock", isEnabled: true, settings: .default(isEnabled: true)),
                at: 0
            )
            didChange = true
        }

        var normalizedClockSettings: [String: ClockSettings] = [:]
        for module in normalizedModules where Self.isClockModuleID(module.id) {
            let id = module.id
            var settings = clockSettingsByModuleID[id] ?? .default(isEnabled: module.isEnabled)
            if settings.isEnabled != module.isEnabled {
                settings.isEnabled = module.isEnabled
                didChange = true
            }
            normalizedClockSettings[id] = settings

            if let clock = module as? ClockModule {
                clock.applySettings(settings)
            }
        }

        let normalizedOrder = normalizedModules.map(\.id)
        if normalizedOrder != originalOrder {
            didChange = true
        }
        if Set(normalizedClockSettings.keys) != originalSettingsKeys {
            didChange = true
        }

        if didChange {
            orderedModules = normalizedModules
            clockSettingsByModuleID = normalizedClockSettings
        }

        return didChange
    }

    private func persistState() {
        let state = PersistedState(
            moduleOrder: orderedModules.map(\.id),
            moduleEnabled: Dictionary(uniqueKeysWithValues: orderedModules.map { ($0.id, $0.isEnabled) }),
            moduleShowsValue: Dictionary(uniqueKeysWithValues: orderedModules.map { ($0.id, $0.showsValue) }),
            clockSettingsByModuleID: clockSettingsByModuleID,
            cpuConfigByModuleID: cpuConfigByModuleID(),
            memoryConfigByModuleID: memoryConfigByModuleID(),
            diskConfigByModuleID: diskConfigByModuleID(),
            networkConfigByModuleID: networkConfigByModuleID()
        )

        guard let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(data, forKey: Self.persistenceKey)
    }

    private static func loadPersistedState() -> PersistedState? {
        guard let data = UserDefaults.standard.data(forKey: persistenceKey) else { return nil }
        return try? JSONDecoder().decode(PersistedState.self, from: data)
    }

    private func cpuConfigByModuleID() -> [String: PersistedState.CPUConfig] {
        var result: [String: PersistedState.CPUConfig] = [:]
        for module in orderedModules {
            guard let cpu = module as? CPUModule else { continue }
            result[cpu.id] = .init(
                mode: cpu.hoverMode.rawValue,
                showUser: cpu.showsSparklineUser,
                showSystem: cpu.showsSparklineSystem
            )
        }
        return result
    }

    private func memoryConfigByModuleID() -> [String: PersistedState.MemoryConfig] {
        var result: [String: PersistedState.MemoryConfig] = [:]
        for module in orderedModules {
            guard let memory = module as? MemoryModule else { continue }
            result[memory.id] = .init(
                showUsed: memory.showsUsed,
                showAvailable: memory.showsAvailable,
                showSwapUsed: memory.showsSwapUsed
            )
        }
        return result
    }

    private func diskConfigByModuleID() -> [String: PersistedState.DiskConfig] {
        var result: [String: PersistedState.DiskConfig] = [:]
        for module in orderedModules {
            guard let disk = module as? DiskUsageModule else { continue }
            result[disk.id] = .init(
                mode: disk.hoverMode.rawValue,
                showUsed: disk.showsCapacityUsed,
                showAvailable: disk.showsCapacityAvailable,
                showTotal: disk.showsCapacityTotal,
                showVolumeList: disk.showsVolumeList
            )
        }
        return result
    }

    private func networkConfigByModuleID() -> [String: PersistedState.NetworkConfig] {
        var result: [String: PersistedState.NetworkConfig] = [:]
        for module in orderedModules {
            guard let network = module as? NetworkModule else { continue }
            result[network.id] = .init(
                mode: network.hoverMode.rawValue,
                speedUnitMode: network.speedUnitMode.rawValue,
                fixedSpeedUnit: network.fixedSpeedUnit.rawValue
            )
        }
        return result
    }

    private static func restoreState(
        from state: PersistedState,
        defaults: [any MenuModule],
        defaultClockSettings: [String: ClockSettings]
    ) -> (modules: [any MenuModule], clockSettings: [String: ClockSettings], didNormalize: Bool) {
        var clockSettings = state.clockSettingsByModuleID
        var normalizedOrder = state.moduleOrder
        var didNormalize = false

        if !normalizedOrder.contains("clock") {
            normalizedOrder.insert("clock", at: 0)
            didNormalize = true
        }

        var dedupedOrder: [String] = []
        var seenIDs = Set<String>()
        for id in normalizedOrder {
            guard !seenIDs.contains(id) else {
                didNormalize = true
                continue
            }
            seenIDs.insert(id)
            dedupedOrder.append(id)
        }

        var retainedGeneratedClockIDs: [String] = []
        for id in dedupedOrder where isGeneratedClockID(id) {
            retainedGeneratedClockIDs.append(id)
            if retainedGeneratedClockIDs.count == (maxClockModules - 1) {
                break
            }
        }

        let retainedClockIDSet = Set(["clock"] + retainedGeneratedClockIDs)
        let filteredOrder = dedupedOrder.filter { id in
            if id == "clock" {
                return true
            }
            if id.hasPrefix("clock") {
                let keep = retainedClockIDSet.contains(id)
                if !keep {
                    didNormalize = true
                }
                return keep
            }
            return true
        }
        if filteredOrder.count != dedupedOrder.count {
            didNormalize = true
        }
        if filteredOrder.first != "clock" {
            didNormalize = true
        }

        let orderedRetainedClockIDs = ["clock"] + retainedGeneratedClockIDs
        var retainedClockSettings: [String: ClockSettings] = [:]
        for id in orderedRetainedClockIDs {
            if let settings = clockSettings[id] {
                retainedClockSettings[id] = settings
            } else {
                retainedClockSettings[id] = defaultClockSettings["clock"] ?? .default(isEnabled: true)
                didNormalize = true
            }
        }
        if retainedClockSettings["clock"] == nil {
            retainedClockSettings["clock"] = defaultClockSettings["clock"] ?? .default(isEnabled: true)
            didNormalize = true
        }
        clockSettings = retainedClockSettings

        var modulesByID: [String: any MenuModule] = [:]
        for module in defaults {
            modulesByID[module.id] = module
        }

        for id in retainedGeneratedClockIDs where modulesByID[id] == nil {
            let settings = clockSettings[id] ?? .default(isEnabled: true)
            modulesByID[id] = ClockModule(id: id, title: "Clock", isEnabled: settings.isEnabled, settings: settings)
        }

        var reordered: [any MenuModule] = []
        for id in filteredOrder {
            if let module = modulesByID.removeValue(forKey: id) {
                reordered.append(module)
            }
        }

        for module in defaults where modulesByID[module.id] != nil {
            reordered.append(module)
            modulesByID.removeValue(forKey: module.id)
        }
        for generatedID in retainedGeneratedClockIDs where modulesByID[generatedID] != nil {
            if let module = modulesByID.removeValue(forKey: generatedID) {
                reordered.append(module)
            }
        }

        if reordered.first?.id != "clock" {
            if let index = reordered.firstIndex(where: { $0.id == "clock" }) {
                let module = reordered.remove(at: index)
                reordered.insert(module, at: 0)
                didNormalize = true
            }
        }

        for module in reordered {
            if let enabled = state.moduleEnabled[module.id] {
                module.isEnabled = enabled
            }
            if let shows = state.moduleShowsValue[module.id] {
                module.showsValue = shows
            }

            if let cpu = module as? CPUModule, let config = state.cpuConfigByModuleID[module.id] {
                cpu.hoverMode = CPUModule.HoverMode(rawValue: config.mode) ?? .sparkline
                cpu.showsSparklineUser = config.showUser
                cpu.showsSparklineSystem = config.showSystem
            }

            if let memory = module as? MemoryModule, let config = state.memoryConfigByModuleID[module.id] {
                memory.showsUsed = config.showUsed
                memory.showsAvailable = config.showAvailable
                memory.showsSwapUsed = config.showSwapUsed
            }

            if let disk = module as? DiskUsageModule, let config = state.diskConfigByModuleID[module.id] {
                disk.hoverMode = DiskUsageModule.HoverMode(rawValue: config.mode) ?? .capacity
                disk.showsCapacityUsed = config.showUsed
                disk.showsCapacityAvailable = config.showAvailable
                disk.showsCapacityTotal = config.showTotal
                disk.showsVolumeList = config.showVolumeList
            }

            if let network = module as? NetworkModule, let config = state.networkConfigByModuleID[module.id] {
                network.hoverMode = NetworkModule.HoverMode(rawValue: config.mode) ?? .throughput
                network.speedUnitMode = NetworkModule.SpeedUnitMode(rawValue: config.speedUnitMode) ?? .auto
                network.fixedSpeedUnit = NetworkModule.FixedSpeedUnit(rawValue: config.fixedSpeedUnit) ?? .mbps
            }

            if let clock = module as? ClockModule, let settings = clockSettings[module.id] {
                clock.applySettings(settings)
            }
        }

        if filteredOrder != state.moduleOrder {
            didNormalize = true
        }
        if clockSettings.keys.count != state.clockSettingsByModuleID.keys.count {
            didNormalize = true
        }

        return (reordered, clockSettings, didNormalize)
    }
}
