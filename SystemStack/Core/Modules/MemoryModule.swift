import Foundation
import Darwin

final class MemoryModule: BaseMenuModule, @unchecked Sendable {
    private var pageSize: vm_size_t?
    private var totalMemoryBytes: UInt64?
    private let hoverStateLock = NSLock()
    private var showsUsedValue = true
    private var showsAvailableValue = true
    private var showsSwapUsedValue = true
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

    var showsUsed: Bool {
        get {
            hoverStateLock.lock()
            defer { hoverStateLock.unlock() }
            return showsUsedValue
        }
        set {
            hoverStateLock.lock()
            showsUsedValue = newValue
            hoverStateLock.unlock()
        }
    }

    var showsAvailable: Bool {
        get {
            hoverStateLock.lock()
            defer { hoverStateLock.unlock() }
            return showsAvailableValue
        }
        set {
            hoverStateLock.lock()
            showsAvailableValue = newValue
            hoverStateLock.unlock()
        }
    }

    var showsSwapUsed: Bool {
        get {
            hoverStateLock.lock()
            defer { hoverStateLock.unlock() }
            return showsSwapUsedValue
        }
        set {
            hoverStateLock.lock()
            showsSwapUsedValue = newValue
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
            hoverText(
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

    private func hoverText(
        usedBytes: UInt64,
        availableBytes: UInt64,
        swapUsedBytes: UInt64?
    ) -> String {
        var lines = [makeSparkline()]
        if showsUsed {
            lines.append("Used: \(formatGigabytes(usedBytes))")
        }
        if showsAvailable {
            lines.append("Available: \(formatGigabytes(availableBytes))")
        }
        if showsSwapUsed {
            lines.append("Swap Used: \(formatSwap(swapUsedBytes))")
        }
        return lines.joined(separator: "\n")
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
        let width = ModuleVisuals.standardSparklineWidth

        hoverStateLock.lock()
        let samples = usageHistory
        hoverStateLock.unlock()

        guard !samples.isEmpty else {
            return String(repeating: "─", count: width)
        }

        let visible = Array(samples.suffix(width))
        let minSample = visible.min() ?? 0
        let maxSample = visible.max() ?? 100
        let span = max(maxSample - minSample, 8.0)

        let spark = visible.map { sample in
            let normalized = max(0.0, min(1.0, (sample - minSample) / span))
            let index = Int((normalized * Double(symbols.count - 1)).rounded())
            return String(symbols[index])
        }.joined()

        if spark.count < width {
            return String(repeating: "─", count: width - spark.count) + spark
        }
        return spark
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
