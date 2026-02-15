import Foundation

final class DiskUsageModule: BaseMenuModule, @unchecked Sendable {
    private var lastPollTime: TimeInterval = 0

    init(isEnabled: Bool = false) {
        super.init(id: "disk", title: "Disk", symbolName: "internaldrive", isEnabled: isEnabled)
    }

    override func update() async -> Bool {
        let now = Date().timeIntervalSinceReferenceDate
        if now - lastPollTime < 5.0 {
            return false
        }
        lastPollTime = now

        do {
            let attributes = try FileManager.default.attributesOfFileSystem(forPath: "/")
            guard let total = (attributes[.systemSize] as? NSNumber)?.uint64Value,
                  let free = (attributes[.systemFreeSize] as? NSNumber)?.uint64Value,
                  total > 0 else {
                return setDisplayValueIfChanged("—")
            }

            let used = total >= free ? (total - free) : 0
            let percent = min(max(Double(used) / Double(total), 0.0), 1.0)
            return setDisplayValueIfChanged("\(Int((percent * 100.0).rounded()))%")
        } catch {
            return setDisplayValueIfChanged("—")
        }
    }
}
