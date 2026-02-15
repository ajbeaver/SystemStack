import Foundation
import Darwin

private struct NetworkCounters {
    let inputBytes: UInt64
    let outputBytes: UInt64
}

final class NetworkModule: BaseMenuModule, @unchecked Sendable {
    private var interfaceName: String?
    private var previousSample: (counters: NetworkCounters, timestamp: TimeInterval)?

    init(isEnabled: Bool = false) {
        super.init(id: "network", title: "Network", symbolName: "arrow.up.arrow.down", isEnabled: isEnabled)
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
                return setDisplayValueIfChanged("—")
            }

            defer { previousSample = (refreshedCounters, now) }
            guard let previousSample else {
                return setDisplayValueIfChanged("—")
            }

            let deltaTime = max(now - previousSample.timestamp, 0.001)
            let deltaInput = refreshedCounters.inputBytes >= previousSample.counters.inputBytes
                ? refreshedCounters.inputBytes - previousSample.counters.inputBytes
                : 0
            let deltaOutput = refreshedCounters.outputBytes >= previousSample.counters.outputBytes
                ? refreshedCounters.outputBytes - previousSample.counters.outputBytes
                : 0

            return setDisplayValueIfChanged(formatTransferText(uploadBytesPerSecond: Double(deltaOutput) / deltaTime, downloadBytesPerSecond: Double(deltaInput) / deltaTime))
        }

        defer { previousSample = (counters, now) }

        guard let previousSample else {
            previousSample = nil
            return setDisplayValueIfChanged("—")
        }

        let deltaTime = max(now - previousSample.timestamp, 0.001)
        let deltaInput = counters.inputBytes >= previousSample.counters.inputBytes
            ? counters.inputBytes - previousSample.counters.inputBytes
            : 0
        let deltaOutput = counters.outputBytes >= previousSample.counters.outputBytes
            ? counters.outputBytes - previousSample.counters.outputBytes
            : 0

        return setDisplayValueIfChanged(formatTransferText(uploadBytesPerSecond: Double(deltaOutput) / deltaTime, downloadBytesPerSecond: Double(deltaInput) / deltaTime))
    }

    private func resolvePrimaryInterfaceName() -> String? {
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

    private func formatTransferText(uploadBytesPerSecond: Double, downloadBytesPerSecond: Double) -> String {
        let uploadKB = max(uploadBytesPerSecond / 1024.0, 0.0)
        let downloadKB = max(downloadBytesPerSecond / 1024.0, 0.0)

        if uploadKB >= 1024.0 || downloadKB >= 1024.0 {
            return String(format: "%.1f/%.1f", uploadKB / 1024.0, downloadKB / 1024.0)
        }

        return String(format: "%.1f/%.1f", uploadKB, downloadKB)
    }
}
