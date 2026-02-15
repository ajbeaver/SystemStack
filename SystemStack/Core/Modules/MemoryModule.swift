import Foundation
import Darwin

final class MemoryModule: BaseMenuModule, @unchecked Sendable {
    private var pageSize: vm_size_t?
    private var totalMemoryBytes: UInt64?

    init(isEnabled: Bool = true) {
        super.init(id: "memory", title: "Memory", symbolName: "memorychip", isEnabled: isEnabled)
    }

    override func update() async -> Bool {
        var vmStats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)

        let result = withUnsafeMutablePointer(to: &vmStats) { statsPointer in
            statsPointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { integerPointer in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, integerPointer, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            return setDisplayValueIfChanged("—")
        }

        let resolvedPageSize: vm_size_t
        if let pageSize {
            resolvedPageSize = pageSize
        } else {
            var newPageSize: vm_size_t = 0
            guard host_page_size(mach_host_self(), &newPageSize) == KERN_SUCCESS else {
                return setDisplayValueIfChanged("—")
            }
            pageSize = newPageSize
            resolvedPageSize = newPageSize
        }

        let usedPages = UInt64(vmStats.active_count)
            + UInt64(vmStats.wire_count)
            + UInt64(vmStats.compressor_page_count)

        let cachedPages = UInt64(vmStats.inactive_count) + UInt64(vmStats.speculative_count)
        let freePages = UInt64(vmStats.free_count)

        let usedBytes = usedPages * UInt64(resolvedPageSize)
        let cachedBytes = cachedPages * UInt64(resolvedPageSize)
        let freeBytes = freePages * UInt64(resolvedPageSize)

        let totalBytes: UInt64
        if let totalMemoryBytes {
            totalBytes = totalMemoryBytes
        } else {
            guard let resolvedTotal = readTotalMemoryBytes() else {
                return setDisplayValueIfChanged("—")
            }
            totalMemoryBytes = resolvedTotal
            totalBytes = resolvedTotal
        }

        guard totalBytes > 0 else {
            return setDisplayValueIfChanged("—")
        }

        let percentUsed = min(max(Double(usedBytes) / Double(totalBytes), 0.0), 1.0)

        let displayPercent = Int((percentUsed * 100.0).rounded())
        let didChange = setDisplayValueIfChanged("\(displayPercent)%")

        #if DEBUG
        if didChange {
            let usedGB = Double(usedBytes) / 1_073_741_824.0
            let cachedGB = Double(cachedBytes) / 1_073_741_824.0
            let freeGB = Double(freeBytes) / 1_073_741_824.0
            let totalGB = Double(totalBytes) / 1_073_741_824.0
            let percentText = String(format: "%.1f", percentUsed * 100.0)
            print(
                "MemoryModule usedBytes=\(usedBytes) (\(String(format: "%.2f", usedGB))G), "
                    + "cachedBytes=\(cachedBytes) (\(String(format: "%.2f", cachedGB))G), "
                    + "freeBytes=\(freeBytes) (\(String(format: "%.2f", freeGB))G), "
                    + "totalBytes=\(totalBytes) (\(String(format: "%.2f", totalGB))G), "
                    + "percentUsed=\(percentText)%"
            )
        }
        #endif

        return didChange
    }

    private func readTotalMemoryBytes() -> UInt64? {
        var totalBytes: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        let result = sysctlbyname("hw.memsize", &totalBytes, &size, nil, 0)
        guard result == 0, totalBytes > 0 else { return nil }
        return totalBytes
    }
}
