import XCTest
@testable import SystemStack

final class AppStateClockInvariantsTests: XCTestCase {
    private let persistenceKey = "SystemStack.AppState.v1"

    private struct PersistedCPUConfig: Codable {
        var mode: String
        var showUser: Bool
        var showSystem: Bool
    }

    private struct PersistedMemoryConfig: Codable {
        var showUsed: Bool
        var showAvailable: Bool
        var showSwapUsed: Bool
    }

    private struct PersistedDiskConfig: Codable {
        var mode: String
        var showUsed: Bool
        var showAvailable: Bool
        var showTotal: Bool
        var showVolumeList: Bool
    }

    private struct PersistedNetworkConfig: Codable {
        var mode: String
        var speedUnitMode: String
        var fixedSpeedUnit: String
    }

    private struct PersistedState: Codable {
        var moduleOrder: [String]
        var moduleEnabled: [String: Bool]
        var moduleShowsValue: [String: Bool]
        var clockSettingsByModuleID: [String: ClockSettings]
        var cpuConfigByModuleID: [String: PersistedCPUConfig]
        var memoryConfigByModuleID: [String: PersistedMemoryConfig]
        var diskConfigByModuleID: [String: PersistedDiskConfig]
        var networkConfigByModuleID: [String: PersistedNetworkConfig]
    }

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: persistenceKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: persistenceKey)
        super.tearDown()
    }

    func testDefaultClockAlwaysExistsAfterRestore() throws {
        try persistState(
            moduleOrder: ["cpu", "memory", "network", "disk"],
            clockSettingsByModuleID: [:]
        )

        let appState = AppState()

        XCTAssertEqual(appState.orderedModules.first?.id, "clock")
        XCTAssertTrue(appState.orderedModules.contains(where: { $0.id == "clock" }))
    }

    func testGeneratedClockRemoval() {
        let appState = AppState()

        appState.addClockModule(after: "clock")
        appState.addClockModule(after: "clock.1")

        let generatedBefore = generatedClockIDs(in: appState)
        XCTAssertEqual(generatedBefore.count, 2)

        let removedID = generatedBefore[0]
        let expectedRemaining = generatedBefore[1]

        appState.removeClockModule(id: removedID)

        let generatedAfter = generatedClockIDs(in: appState)
        XCTAssertFalse(appState.orderedModules.contains(where: { $0.id == removedID }))
        XCTAssertTrue(appState.orderedModules.contains(where: { $0.id == "clock" }))
        XCTAssertEqual(generatedAfter, [expectedRemaining])
    }

    func testMaxClockCountEnforced() throws {
        let defaultClock = ClockSettings.default(isEnabled: true)
        let utcClock = ClockSettings(
            isEnabled: true,
            use24Hour: true,
            showSeconds: false,
            showAMPM: false,
            timezoneMode: .utc,
            showTimezoneLabel: true,
            selectedTimezones: []
        )
        let parisClock = ClockSettings(
            isEnabled: true,
            use24Hour: true,
            showSeconds: false,
            showAMPM: false,
            timezoneMode: .custom,
            showTimezoneLabel: true,
            selectedTimezones: ["Europe/Paris"]
        )

        try persistState(
            moduleOrder: ["clock", "clock.1", "clock.1", "clock.2", "clock.3", "cpu", "memory"],
            clockSettingsByModuleID: [
                "clock": defaultClock,
                "clock.1": utcClock,
                "clock.2": parisClock,
                "clock.3": parisClock
            ]
        )

        let appState = AppState()
        let clockIDs = appState.orderedModules.map(\.id).filter { $0.hasPrefix("clock") }

        XCTAssertEqual(clockIDs, ["clock", "clock.1", "clock.2"])
        XCTAssertFalse(appState.orderedModules.contains(where: { $0.id == "clock.3" }))
    }

    func testClockOrderingAfterDeletion() {
        let appState = AppState()

        appState.addClockModule(after: "clock")
        appState.addClockModule(after: "clock.1")

        XCTAssertTrue(appState.orderedModules.map(\.id).starts(with: ["clock", "clock.1", "clock.2"]))

        appState.removeClockModule(id: "clock.2")

        let ids = appState.orderedModules.map(\.id)
        XCTAssertTrue(ids.starts(with: ["clock", "clock.1"]))
        XCTAssertFalse(ids.contains("clock.2"))
    }

    private func generatedClockIDs(in appState: AppState) -> [String] {
        appState.orderedModules
            .map(\.id)
            .filter { $0.hasPrefix("clock.") }
            .sorted()
    }

    private func persistState(
        moduleOrder: [String],
        clockSettingsByModuleID: [String: ClockSettings]
    ) throws {
        let state = PersistedState(
            moduleOrder: moduleOrder,
            moduleEnabled: [:],
            moduleShowsValue: [:],
            clockSettingsByModuleID: clockSettingsByModuleID,
            cpuConfigByModuleID: [:],
            memoryConfigByModuleID: [:],
            diskConfigByModuleID: [:],
            networkConfigByModuleID: [:]
        )

        let data = try JSONEncoder().encode(state)
        UserDefaults.standard.set(data, forKey: persistenceKey)
    }
}
