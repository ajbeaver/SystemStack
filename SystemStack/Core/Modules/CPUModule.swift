import Foundation
import Darwin

final class CPUModule: BaseMenuModule, @unchecked Sendable {
    enum HoverMode: String, CaseIterable, Identifiable {
        case percentage = "Percentage"
        case userSystem = "User / System split"
        case perCore = "Per-core summary"

        var id: String { rawValue }
    }

    private var previousLoadInfo: host_cpu_load_info_data_t?
    private var previousCoreTicks: [[UInt32]]?

    private let hoverStateLock = NSLock()
    private var hoverModeValue: HoverMode = .percentage
    private var hoverTextValue: String = "CPU —"

    init(isEnabled: Bool = true) {
        super.init(id: "cpu", title: "CPU", symbolName: "cpu", isEnabled: isEnabled)
    }

    var hoverMode: HoverMode {
        get {
            hoverStateLock.lock()
            defer { hoverStateLock.unlock() }
            return hoverModeValue
        }
        set {
            hoverStateLock.lock()
            hoverModeValue = newValue
            hoverStateLock.unlock()
        }
    }

    var hoverText: String {
        hoverStateLock.lock()
        defer { hoverStateLock.unlock() }
        return hoverTextValue
    }

    override func update() async -> Bool {
        guard let currentLoadInfo = readCPULoadInfo() else {
            let displayChanged = setDisplayValueIfChanged("—")
            let hoverChanged = setHoverTextIfChanged("CPU —")
            return displayChanged || hoverChanged
        }

        defer { previousLoadInfo = currentLoadInfo }

        guard let previousLoadInfo else {
            let displayChanged = setDisplayValueIfChanged("—")
            let hoverChanged = setHoverTextIfChanged("CPU —")
            return displayChanged || hoverChanged
        }

        let currentTicks = cpuTicksArray(from: currentLoadInfo)
        let previousTicks = cpuTicksArray(from: previousLoadInfo)

        var totalDelta: UInt64 = 0
        var idleDelta: UInt64 = 0
        for index in 0 ..< min(currentTicks.count, previousTicks.count) {
            let delta = UInt64(currentTicks[index] &- previousTicks[index])
            totalDelta += delta
            if index == Int(CPU_STATE_IDLE) {
                idleDelta = delta
            }
        }

        guard totalDelta > 0 else {
            let displayChanged = setDisplayValueIfChanged("—")
            let hoverChanged = setHoverTextIfChanged("CPU —")
            return displayChanged || hoverChanged
        }

        let userDelta = UInt64(currentTicks[Int(CPU_STATE_USER)] &- previousTicks[Int(CPU_STATE_USER)])
            + UInt64(currentTicks[Int(CPU_STATE_NICE)] &- previousTicks[Int(CPU_STATE_NICE)])
        let systemDelta = UInt64(currentTicks[Int(CPU_STATE_SYSTEM)] &- previousTicks[Int(CPU_STATE_SYSTEM)])

        let usedPercent = (Double(totalDelta - idleDelta) / Double(totalDelta)) * 100.0
        let roundedUsedPercent = Int(usedPercent.rounded())
        let displayChanged = setDisplayValueIfChanged("\(roundedUsedPercent)%")

        let hoverChanged = setHoverTextIfChanged(
            hoverTextForCurrentMode(
                usedPercent: usedPercent,
                userDelta: userDelta,
                systemDelta: systemDelta,
                totalDelta: totalDelta
            )
        )

        return displayChanged || hoverChanged
    }

    private func readCPULoadInfo() -> host_cpu_load_info_data_t? {
        var loadInfo = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)

        let result = withUnsafeMutablePointer(to: &loadInfo) { loadInfoPointer in
            loadInfoPointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { integerPointer in
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, integerPointer, &count)
            }
        }

        return result == KERN_SUCCESS ? loadInfo : nil
    }

    private func cpuTicksArray(from loadInfo: host_cpu_load_info_data_t) -> [UInt32] {
        withUnsafeBytes(of: loadInfo.cpu_ticks) { bytes in
            Array(bytes.bindMemory(to: UInt32.self))
        }
    }

    private func hoverTextForCurrentMode(
        usedPercent: Double,
        userDelta: UInt64,
        systemDelta: UInt64,
        totalDelta: UInt64
    ) -> String {
        let mode = hoverMode
        switch mode {
        case .percentage:
            return "CPU \(Int(usedPercent.rounded()))%"
        case .userSystem:
            let userPercent = totalDelta > 0 ? (Double(userDelta) / Double(totalDelta)) * 100.0 : 0
            let systemPercent = totalDelta > 0 ? (Double(systemDelta) / Double(totalDelta)) * 100.0 : 0
            return "CPU U\(Int(userPercent.rounded())) S\(Int(systemPercent.rounded()))"
        case .perCore:
            guard let cores = readPerCorePercentages() else {
                return "CPU \(Int(usedPercent.rounded()))%"
            }
            let summary = cores
                .prefix(4)
                .enumerated()
                .map { index, value in "C\(index):\(Int(value.rounded()))" }
                .joined(separator: " ")
            return summary.isEmpty ? "CPU \(Int(usedPercent.rounded()))%" : "CPU \(summary)"
        }
    }

    private func readPerCorePercentages() -> [Double]? {
        var processorInfo: processor_info_array_t?
        var processorInfoCount: mach_msg_type_number_t = 0
        var processorCount: natural_t = 0

        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &processorCount,
            &processorInfo,
            &processorInfoCount
        )

        guard result == KERN_SUCCESS, let processorInfo else {
            return nil
        }

        defer {
            let size = vm_size_t(processorInfoCount) * vm_size_t(MemoryLayout<integer_t>.size)
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: processorInfo)), size)
        }

        let stride = Int(CPU_STATE_MAX)
        var currentTicks: [[UInt32]] = []
        currentTicks.reserveCapacity(Int(processorCount))

        for core in 0 ..< Int(processorCount) {
            let base = core * stride
            guard base + stride <= Int(processorInfoCount) else { continue }
            let user = UInt32(processorInfo[base + Int(CPU_STATE_USER)])
            let system = UInt32(processorInfo[base + Int(CPU_STATE_SYSTEM)])
            let idle = UInt32(processorInfo[base + Int(CPU_STATE_IDLE)])
            let nice = UInt32(processorInfo[base + Int(CPU_STATE_NICE)])
            currentTicks.append([user, system, idle, nice])
        }

        defer { previousCoreTicks = currentTicks }

        guard let previousCoreTicks else {
            previousCoreTicks = currentTicks
            return nil
        }

        var percentages: [Double] = []
        for index in 0 ..< min(currentTicks.count, previousCoreTicks.count) {
            let current = currentTicks[index]
            let previous = previousCoreTicks[index]

            let userDelta = UInt64(current[Int(CPU_STATE_USER)] &- previous[Int(CPU_STATE_USER)])
                + UInt64(current[Int(CPU_STATE_NICE)] &- previous[Int(CPU_STATE_NICE)])
            let systemDelta = UInt64(current[Int(CPU_STATE_SYSTEM)] &- previous[Int(CPU_STATE_SYSTEM)])
            let idleDelta = UInt64(current[Int(CPU_STATE_IDLE)] &- previous[Int(CPU_STATE_IDLE)])

            let totalDelta = userDelta + systemDelta + idleDelta
            guard totalDelta > 0 else {
                percentages.append(0)
                continue
            }

            percentages.append((Double(userDelta + systemDelta) / Double(totalDelta)) * 100.0)
        }

        return percentages
    }

    private func setHoverTextIfChanged(_ text: String) -> Bool {
        hoverStateLock.lock()
        defer { hoverStateLock.unlock() }
        guard hoverTextValue != text else { return false }
        hoverTextValue = text
        return true
    }
}
