import Foundation
import Darwin

final class CPUModule: BaseMenuModule, @unchecked Sendable {
    private var previousLoadInfo: host_cpu_load_info_data_t?

    init(isEnabled: Bool = true) {
        super.init(id: "cpu", title: "CPU", symbolName: "cpu", isEnabled: isEnabled)
    }

    override func update() async -> Bool {
        guard let currentLoadInfo = readCPULoadInfo() else {
            return setDisplayValueIfChanged("—")
        }

        defer { previousLoadInfo = currentLoadInfo }

        guard let previousLoadInfo else {
            return setDisplayValueIfChanged("—")
        }

        var totalDelta: UInt64 = 0
        var idleDelta: UInt64 = 0

        withUnsafeBytes(of: currentLoadInfo.cpu_ticks) { currentBytes in
            withUnsafeBytes(of: previousLoadInfo.cpu_ticks) { previousBytes in
                let currentTicks = currentBytes.bindMemory(to: UInt32.self)
                let previousTicks = previousBytes.bindMemory(to: UInt32.self)

                let limit = min(currentTicks.count, previousTicks.count)
                for index in 0 ..< limit {
                    let delta = UInt64(currentTicks[index] &- previousTicks[index])
                    totalDelta += delta
                    if index == Int(CPU_STATE_IDLE) {
                        idleDelta = delta
                    }
                }
            }
        }

        guard totalDelta > 0 else {
            return setDisplayValueIfChanged("—")
        }

        let usedPercent = (Double(totalDelta - idleDelta) / Double(totalDelta)) * 100.0
        return setDisplayValueIfChanged("\(Int(usedPercent.rounded()))%")
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
}
