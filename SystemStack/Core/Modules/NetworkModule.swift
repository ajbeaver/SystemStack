import Foundation
import Darwin
import SystemConfiguration

private struct NetworkCounters {
    let inputBytes: UInt64
    let outputBytes: UInt64
}

final class NetworkModule: BaseMenuModule, @unchecked Sendable {
    enum HoverMode: String, CaseIterable, Identifiable {
        case throughput = "Throughput"
        case interface = "Interface"

        var id: String { rawValue }
    }

    enum SpeedUnitMode: String, CaseIterable, Identifiable {
        case auto = "Auto"
        case fixed = "Fixed"

        var id: String { rawValue }
    }

    enum FixedSpeedUnit: String, CaseIterable, Identifiable {
        case kbps = "KB/s"
        case mbps = "MB/s"

        var id: String { rawValue }
    }

    private struct InterfaceInfo {
        let name: String
        let ipAddress: String
        let subnetMask: String
        let gateway: String
        let linkSpeed: String
    }

    private var interfaceName: String?
    private var previousSample: (counters: NetworkCounters, timestamp: TimeInterval)?
    private let hoverStateLock = NSLock()
    private var hoverModeValue: HoverMode = .throughput
    private var speedUnitModeValue: SpeedUnitMode = .auto
    private var fixedSpeedUnitValue: FixedSpeedUnit = .mbps
    private var hoverTextValue = "Network unavailable"
    private var downloadHistory: [Double] = []
    private var uploadHistory: [Double] = []

    init(isEnabled: Bool = false) {
        super.init(id: "network", title: "Network", symbolName: "arrow.up.arrow.down", isEnabled: isEnabled)
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

    var speedUnitMode: SpeedUnitMode {
        get {
            hoverStateLock.lock()
            defer { hoverStateLock.unlock() }
            return speedUnitModeValue
        }
        set {
            hoverStateLock.lock()
            speedUnitModeValue = newValue
            hoverStateLock.unlock()
        }
    }

    var fixedSpeedUnit: FixedSpeedUnit {
        get {
            hoverStateLock.lock()
            defer { hoverStateLock.unlock() }
            return fixedSpeedUnitValue
        }
        set {
            hoverStateLock.lock()
            fixedSpeedUnitValue = newValue
            hoverStateLock.unlock()
        }
    }

    override func update() async -> Bool {
        let now = Date().timeIntervalSinceReferenceDate

        if interfaceName == nil {
            interfaceName = resolvePrimaryInterfaceName()
            previousSample = nil
        }

        guard let interfaceName,
              let counters = readCounters(for: interfaceName) else {
            self.interfaceName = resolvePrimaryInterfaceName()
            guard let refreshedInterface = self.interfaceName,
                  let refreshedCounters = readCounters(for: refreshedInterface) else {
                previousSample = nil
                let displayChanged = setDisplayValueIfChanged("—")
                let hoverChanged = setHoverTextIfChanged("Network unavailable")
                return displayChanged || hoverChanged
            }

            defer { previousSample = (refreshedCounters, now) }
            guard let previousSample else {
                let displayChanged = setDisplayValueIfChanged("—")
                let hoverChanged = setHoverTextIfChanged("Collecting network data...")
                return displayChanged || hoverChanged
            }

            let deltaTime = max(now - previousSample.timestamp, 0.001)
            let deltaInput = refreshedCounters.inputBytes >= previousSample.counters.inputBytes
                ? refreshedCounters.inputBytes - previousSample.counters.inputBytes
                : 0
            let deltaOutput = refreshedCounters.outputBytes >= previousSample.counters.outputBytes
                ? refreshedCounters.outputBytes - previousSample.counters.outputBytes
                : 0

            let downloadRate = Double(deltaInput) / deltaTime
            let uploadRate = Double(deltaOutput) / deltaTime
            appendThroughputSample(downloadBytesPerSecond: downloadRate, uploadBytesPerSecond: uploadRate)
            let unitSelection = currentUnitSelection()
            let displayChanged = setDisplayValueIfChanged(
                formatTransferText(
                    uploadBytesPerSecond: uploadRate,
                    downloadBytesPerSecond: downloadRate,
                    unitSelection: unitSelection
                )
            )
            let info = readInterfaceInfo(for: refreshedInterface)
            let hoverChanged = setHoverTextIfChanged(
                hoverText(
                    info: info
                )
            )
            return displayChanged || hoverChanged
        }

        defer { previousSample = (counters, now) }

        guard let previousSample else {
            previousSample = nil
            let displayChanged = setDisplayValueIfChanged("—")
            let hoverChanged = setHoverTextIfChanged("Collecting network data...")
            return displayChanged || hoverChanged
        }

        let deltaTime = max(now - previousSample.timestamp, 0.001)
        let deltaInput = counters.inputBytes >= previousSample.counters.inputBytes
            ? counters.inputBytes - previousSample.counters.inputBytes
            : 0
        let deltaOutput = counters.outputBytes >= previousSample.counters.outputBytes
            ? counters.outputBytes - previousSample.counters.outputBytes
            : 0

        let downloadRate = Double(deltaInput) / deltaTime
        let uploadRate = Double(deltaOutput) / deltaTime
        appendThroughputSample(downloadBytesPerSecond: downloadRate, uploadBytesPerSecond: uploadRate)
        let unitSelection = currentUnitSelection()
        let displayChanged = setDisplayValueIfChanged(
            formatTransferText(
                uploadBytesPerSecond: uploadRate,
                downloadBytesPerSecond: downloadRate,
                unitSelection: unitSelection
            )
        )
        let info = readInterfaceInfo(for: interfaceName)
        let hoverChanged = setHoverTextIfChanged(
            hoverText(
                info: info
            )
        )
        return displayChanged || hoverChanged
    }

    private func resolvePrimaryInterfaceName() -> String? {
        if let globalPrimary = globalPrimaryInterfaceName() {
            return globalPrimary
        }

        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let firstAddress = pointer else {
            return nil
        }

        defer { freeifaddrs(pointer) }

        var activeNames: [String] = []
        var seen = Set<String>()

        var currentAddress: UnsafeMutablePointer<ifaddrs>? = firstAddress
        while let address = currentAddress?.pointee {
            defer { currentAddress = address.ifa_next }

            let flags = Int32(address.ifa_flags)
            let requiredFlags = IFF_UP | IFF_RUNNING
            guard (flags & requiredFlags) == requiredFlags,
                  (flags & IFF_LOOPBACK) == 0,
                  let interfaceAddress = address.ifa_addr,
                  interfaceAddress.pointee.sa_family == UInt8(AF_LINK) else {
                continue
            }

            let name = String(cString: address.ifa_name)
            if !seen.contains(name) {
                seen.insert(name)
                activeNames.append(name)
            }
        }

        let preferred = ["en0", "en1", "pdp_ip0", "bridge0"]
        if let match = preferred.first(where: { seen.contains($0) }) {
            return match
        }

        return activeNames.first
    }

    private func readCounters(for interfaceName: String) -> NetworkCounters? {
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let firstAddress = pointer else {
            return nil
        }

        defer { freeifaddrs(pointer) }

        var currentAddress: UnsafeMutablePointer<ifaddrs>? = firstAddress
        while let address = currentAddress?.pointee {
            defer { currentAddress = address.ifa_next }

            guard let interfaceAddress = address.ifa_addr,
                  interfaceAddress.pointee.sa_family == UInt8(AF_LINK),
                  let data = address.ifa_data else {
                continue
            }

            let name = String(cString: address.ifa_name)
            guard name == interfaceName else { continue }

            let ifData = data.assumingMemoryBound(to: if_data.self).pointee
            return NetworkCounters(
                inputBytes: UInt64(ifData.ifi_ibytes),
                outputBytes: UInt64(ifData.ifi_obytes)
            )
        }

        return nil
    }

    private func globalPrimaryInterfaceName() -> String? {
        guard let store = SCDynamicStoreCreate(nil, "SystemStack" as CFString, nil, nil),
              let global = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any] else {
            return nil
        }
        return global["PrimaryInterface"] as? String
    }

    private func readInterfaceInfo(for interfaceName: String) -> InterfaceInfo {
        let ipAndMask = readIPv4AddressAndMask(for: interfaceName)
        return InterfaceInfo(
            name: interfaceName,
            ipAddress: ipAndMask.ip ?? "Unavailable",
            subnetMask: ipAndMask.mask ?? "Unavailable",
            gateway: readGateway(for: interfaceName) ?? "Unavailable",
            linkSpeed: readLinkSpeed(for: interfaceName) ?? "Unavailable"
        )
    }

    private func readIPv4AddressAndMask(for interfaceName: String) -> (ip: String?, mask: String?) {
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let firstAddress = pointer else {
            return (nil, nil)
        }

        defer { freeifaddrs(pointer) }

        var currentAddress: UnsafeMutablePointer<ifaddrs>? = firstAddress
        while let address = currentAddress?.pointee {
            defer { currentAddress = address.ifa_next }

            let name = String(cString: address.ifa_name)
            guard name == interfaceName,
                  let interfaceAddress = address.ifa_addr,
                  interfaceAddress.pointee.sa_family == UInt8(AF_INET) else {
                continue
            }

            let ip = ipv4String(from: interfaceAddress)
            let mask = address.ifa_netmask.flatMap { ipv4String(from: $0) }
            return (ip, mask)
        }

        return (nil, nil)
    }

    private func ipv4String(from sockaddrPointer: UnsafePointer<sockaddr>) -> String? {
        guard sockaddrPointer.pointee.sa_family == UInt8(AF_INET) else { return nil }
        var addr = sockaddr_in()
        memcpy(&addr, sockaddrPointer, MemoryLayout<sockaddr_in>.size)

        return withUnsafePointer(to: &addr.sin_addr) { sinAddrPointer in
            var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            guard inet_ntop(AF_INET, sinAddrPointer, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil else {
                return nil
            }
            return String(cString: buffer)
        }
    }

    private func readGateway(for interfaceName: String) -> String? {
        guard let store = SCDynamicStoreCreate(nil, "SystemStack" as CFString, nil, nil) else {
            return nil
        }

        let globalKey = "State:/Network/Global/IPv4" as CFString
        if let global = SCDynamicStoreCopyValue(store, globalKey) as? [String: Any],
           let primary = global["PrimaryInterface"] as? String,
           primary == interfaceName,
           let router = global["Router"] as? String {
            return router
        }

        let interfaceKey = "State:/Network/Interface/\(interfaceName)/IPv4" as CFString
        if let details = SCDynamicStoreCopyValue(store, interfaceKey) as? [String: Any],
           let router = details["Router"] as? String {
            return router
        }

        return nil
    }

    private func readLinkSpeed(for interfaceName: String) -> String? {
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let firstAddress = pointer else {
            return nil
        }

        defer { freeifaddrs(pointer) }

        var currentAddress: UnsafeMutablePointer<ifaddrs>? = firstAddress
        while let address = currentAddress?.pointee {
            defer { currentAddress = address.ifa_next }

            guard let interfaceAddress = address.ifa_addr,
                  interfaceAddress.pointee.sa_family == UInt8(AF_LINK),
                  let data = address.ifa_data else {
                continue
            }

            let name = String(cString: address.ifa_name)
            guard name == interfaceName else { continue }

            let ifData = data.assumingMemoryBound(to: if_data.self).pointee
            let bitsPerSecond = UInt64(ifData.ifi_baudrate)
            guard bitsPerSecond > 0 else { return nil }
            return formatBitsPerSecond(bitsPerSecond)
        }

        return nil
    }

    private func formatBitsPerSecond(_ bitsPerSecond: UInt64) -> String {
        let value = Double(bitsPerSecond)
        let kbps = 1_000.0
        let mbps = kbps * 1_000.0
        let gbps = mbps * 1_000.0

        if value >= gbps {
            return String(format: "%.1f Gbps", value / gbps)
        }
        if value >= mbps {
            return String(format: "%.0f Mbps", value / mbps)
        }
        if value >= kbps {
            return String(format: "%.0f Kbps", value / kbps)
        }
        return "\(bitsPerSecond) bps"
    }

    private func hoverText(info: InterfaceInfo) -> String {
        switch hoverMode {
        case .throughput:
            return """
            ↓ \(makeSparkline(from: downloadHistory))
            ↑ \(makeSparkline(from: uploadHistory))
            Interface: \(info.name)
            """
        case .interface:
            return """
            Interface: \(info.name)
            IP: \(info.ipAddress)
            Subnet: \(info.subnetMask)
            Gateway: \(info.gateway)
            Link Speed: \(info.linkSpeed)
            """
        }
    }

    private func appendThroughputSample(downloadBytesPerSecond: Double, uploadBytesPerSecond: Double) {
        hoverStateLock.lock()
        downloadHistory.append(max(downloadBytesPerSecond, 0))
        uploadHistory.append(max(uploadBytesPerSecond, 0))
        if downloadHistory.count > 24 {
            downloadHistory.removeFirst(downloadHistory.count - 24)
        }
        if uploadHistory.count > 24 {
            uploadHistory.removeFirst(uploadHistory.count - 24)
        }
        hoverStateLock.unlock()
    }

    private func makeSparkline(from samples: [Double]) -> String {
        let symbols = Array("▁▂▃▄▅▆▇█")
        let width = ModuleVisuals.networkSparklineWidth
        guard !samples.isEmpty else { return String(repeating: "─", count: width) }

        let visible = Array(samples.suffix(width))
        let minSample = visible.min() ?? 0
        let maxSample = visible.max() ?? 0
        let span = max(maxSample - minSample, max(maxSample, 16_384.0))

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

    private func formatBytesPerSecond(
        _ bytesPerSecond: Double,
        unitSelection: (mode: SpeedUnitMode, fixed: FixedSpeedUnit)
    ) -> String {
        let value = max(bytesPerSecond, 0.0)
        let kb = 1_024.0
        let mb = kb * 1_024.0
        let gb = mb * 1_024.0

        switch unitSelection.mode {
        case .auto:
            if value >= gb {
                return String(format: "%.2f GB/s", value / gb)
            }
            if value >= mb {
                return String(format: "%.1f MB/s", value / mb)
            }
            if value >= kb {
                return String(format: "%.0f KB/s", value / kb)
            }
            return String(format: "%.0f B/s", value)
        case .fixed:
            switch unitSelection.fixed {
            case .kbps:
                return String(format: "%.0f KB/s", value / kb)
            case .mbps:
                return String(format: "%.2f MB/s", value / mb)
            }
        }
    }

    private func setHoverTextIfChanged(_ text: String) -> Bool {
        hoverStateLock.lock()
        defer { hoverStateLock.unlock() }
        guard hoverTextValue != text else { return false }
        hoverTextValue = text
        return true
    }

    private func formatTransferText(
        uploadBytesPerSecond: Double,
        downloadBytesPerSecond: Double,
        unitSelection: (mode: SpeedUnitMode, fixed: FixedSpeedUnit)
    ) -> String {
        let up = max(uploadBytesPerSecond, 0.0)
        let down = max(downloadBytesPerSecond, 0.0)
        let kb = 1_024.0
        let mb = kb * 1_024.0
        let gb = mb * 1_024.0

        switch unitSelection.mode {
        case .auto:
            if up >= gb || down >= gb {
                return String(format: "%.2f/%.2fG", up / gb, down / gb)
            }
            if up >= mb || down >= mb {
                return String(format: "%.1f/%.1fM", up / mb, down / mb)
            }
            return String(format: "%.0f/%.0fK", up / kb, down / kb)
        case .fixed:
            switch unitSelection.fixed {
            case .kbps:
                return String(format: "%.0f/%.0fK", up / kb, down / kb)
            case .mbps:
                return String(format: "%.2f/%.2fM", up / mb, down / mb)
            }
        }
    }

    private func currentUnitSelection() -> (mode: SpeedUnitMode, fixed: FixedSpeedUnit) {
        hoverStateLock.lock()
        defer { hoverStateLock.unlock() }
        return (speedUnitModeValue, fixedSpeedUnitValue)
    }
}
