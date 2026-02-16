import Foundation
import Darwin

final class MemoryModule: BaseMenuModule, @unchecked Sendable {
    enum HoverMode: String, CaseIterable, Identifiable {
        case usedAvailable = "Used / Available"
        case swap = "Swap"
        case sparkline = "Sparkline"

        var id: String { rawValue }
    }

    private var pageSize: vm_size_t?
    private var totalMemoryBytes: UInt64?
    private let hoverStateLock = NSLock()
    private var hoverModeValue: HoverMode = .usedAvailable
    private var hoverTextValue: String = "Memory —"
    private var usageHistory: [Double] = []
    
    private struct SwapUsageData {
        var total: UInt64 = 0
        var available: UInt64 = 0
        var used: UInt64 = 0
        var pageSize: UInt32 = 0
        var encrypted: UInt32 = 0
    }

    init(isEnabled: Bool = true) {
        super.init(id: "memory", title: "Memory", symbolName: "memorychip", isEnabled: isEnabled)
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
        var vmStats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)

        let result = withUnsafeMutablePointer(to: &vmStats) { statsPointer in
            statsPointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { integerPointer in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, integerPointer, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            let displayChanged = setDisplayValueIfChanged("—")
            let hoverChanged = setHoverTextIfChanged("Memory usage unavailable")
            return displayChanged || hoverChanged
        }

        let resolvedPageSize: vm_size_t
        if let pageSize {
            resolvedPageSize = pageSize
        } else {
            var newPageSize: vm_size_t = 0
            guard host_page_size(mach_host_self(), &newPageSize) == KERN_SUCCESS else {
                let displayChanged = setDisplayValueIfChanged("—")
                let hoverChanged = setHoverTextIfChanged("Memory usage unavailable")
                return displayChanged || hoverChanged
            }
            pageSize = newPageSize
            resolvedPageSize = newPageSize
        }

        let usedPages = UInt64(vmStats.active_count)
            + UInt64(vmStats.wire_count)
            + UInt64(vmStats.compressor_page_count)

        let usedBytes = usedPages * UInt64(resolvedPageSize)

        let totalBytes: UInt64
        if let totalMemoryBytes {
            totalBytes = totalMemoryBytes
        } else {
            guard let resolvedTotal = readTotalMemoryBytes() else {
                let displayChanged = setDisplayValueIfChanged("—")
                let hoverChanged = setHoverTextIfChanged("Memory usage unavailable")
                return displayChanged || hoverChanged
            }
            totalMemoryBytes = resolvedTotal
            totalBytes = resolvedTotal
        }

        guard totalBytes > 0 else {
            let displayChanged = setDisplayValueIfChanged("—")
            let hoverChanged = setHoverTextIfChanged("Memory usage unavailable")
            return displayChanged || hoverChanged
        }

        let availableBytes = totalBytes > usedBytes ? totalBytes - usedBytes : 0
        let percentUsed = min(max(Double(usedBytes) / Double(totalBytes), 0.0), 1.0) * 100.0
        appendUsageSample(percentUsed)
        let swapUsedBytes = readSwapUsedBytes()

        let displayPercent = Int(percentUsed.rounded())
        let displayChanged = setDisplayValueIfChanged("\(displayPercent)%")
        let hoverChanged = setHoverTextIfChanged(
            hoverTextForCurrentMode(
                percentUsed: percentUsed,
                usedBytes: usedBytes,
                availableBytes: availableBytes,
                swapUsedBytes: swapUsedBytes
            )
        )

        #if DEBUG
        if displayChanged {
            let usedGB = Double(usedBytes) / 1_073_741_824.0
            let availableGB = Double(availableBytes) / 1_073_741_824.0
            let totalGB = Double(totalBytes) / 1_073_741_824.0
            let percentText = String(format: "%.1f", percentUsed)
            print(
                "MemoryModule usedBytes=\(usedBytes) (\(String(format: "%.2f", usedGB))G), "
                    + "availableBytes=\(availableBytes) (\(String(format: "%.2f", availableGB))G), "
                    + "totalBytes=\(totalBytes) (\(String(format: "%.2f", totalGB))G), "
                    + "percentUsed=\(percentText)%"
            )
        }
        #endif

        return displayChanged || hoverChanged
    }

    private func readTotalMemoryBytes() -> UInt64? {
        var totalBytes: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        let result = sysctlbyname("hw.memsize", &totalBytes, &size, nil, 0)
        guard result == 0, totalBytes > 0 else { return nil }
        return totalBytes
    }

    private func readSwapUsedBytes() -> UInt64? {
        var usage = SwapUsageData()
        var size = MemoryLayout<SwapUsageData>.stride
        let result = withUnsafeMutablePointer(to: &usage) { usagePointer in
            sysctlbyname("vm.swapusage", usagePointer, &size, nil, 0)
        }
        guard result == 0 else { return nil }
        return usage.used
    }

    private func hoverTextForCurrentMode(
        percentUsed: Double,
        usedBytes: UInt64,
        availableBytes: UInt64,
        swapUsedBytes: UInt64?
    ) -> String {
        switch hoverMode {
        case .usedAvailable:
            return """
            Used: \(formatGigabytes(usedBytes))
            Available: \(formatGigabytes(availableBytes))
            """
        case .swap:
            return """
            Swap Used: \(formatSwap(swapUsedBytes))
            """
        case .sparkline:
            return """
            \(makeSparkline())
            Used: \(formatGigabytes(usedBytes))
            """
        }
    }

    private func appendUsageSample(_ value: Double) {
        hoverStateLock.lock()
        usageHistory.append(value)
        if usageHistory.count > 24 {
            usageHistory.removeFirst(usageHistory.count - 24)
        }
        hoverStateLock.unlock()
    }

    private func makeSparkline() -> String {
        let symbols = Array("▁▂▃▄▅▆▇█")

        hoverStateLock.lock()
        let samples = usageHistory
        hoverStateLock.unlock()

        guard !samples.isEmpty else {
            return "────────"
        }

        return samples.map { sample in
            let clamped = max(0.0, min(100.0, sample))
            let normalized = clamped / 100.0
            let index = Int((normalized * Double(symbols.count - 1)).rounded())
            return String(symbols[index])
        }.joined()
    }

    private func formatGigabytes(_ bytes: UInt64) -> String {
        let value = Double(bytes) / 1_073_741_824.0
        return String(format: "%.1f GB", value)
    }

    private func formatSwap(_ bytes: UInt64?) -> String {
        guard let bytes else { return "Unavailable" }
        let gigabytes = Double(bytes) / 1_073_741_824.0
        if gigabytes >= 1.0 {
            return String(format: "%.1f GB", gigabytes)
        }
        let megabytes = Double(bytes) / 1_048_576.0
        return String(format: "%.0f MB", megabytes)
    }

    private func setHoverTextIfChanged(_ text: String) -> Bool {
        hoverStateLock.lock()
        defer { hoverStateLock.unlock() }
        guard hoverTextValue != text else { return false }
        hoverTextValue = text
        return true
    }
}
