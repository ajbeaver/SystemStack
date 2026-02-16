import Foundation

final class DiskUsageModule: BaseMenuModule, @unchecked Sendable {
    enum HoverMode: String, CaseIterable, Identifiable {
        case capacity = "Capacity"
        case volumes = "Volumes"

        var id: String { rawValue }
    }

    private struct VolumeUsage: Sendable {
        let name: String
        let freeBytes: UInt64
    }

    private struct DiskSnapshot: Sendable {
        let usedBytes: UInt64
        let availableBytes: UInt64
        let totalBytes: UInt64
        let volumes: [VolumeUsage]
    }

    private var lastPollTime: TimeInterval = 0
    private let hoverStateLock = NSLock()
    private var hoverModeValue: HoverMode = .capacity
    private var showsCapacityUsedValue = true
    private var showsCapacityAvailableValue = true
    private var showsCapacityTotalValue = true
    private var showsVolumeListValue = true
    private var hoverTextValue = "Disk —"
    private var lastSnapshot: DiskSnapshot?

    init(isEnabled: Bool = false) {
        super.init(id: "disk", title: "Disk", symbolName: "internaldrive", isEnabled: isEnabled)
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
            let snapshot = lastSnapshot
            hoverStateLock.unlock()
            rebuildHoverText(using: snapshot)
        }
    }

    var showsCapacityUsed: Bool {
        get {
            hoverStateLock.lock()
            defer { hoverStateLock.unlock() }
            return showsCapacityUsedValue
        }
        set {
            hoverStateLock.lock()
            showsCapacityUsedValue = newValue
            let snapshot = lastSnapshot
            hoverStateLock.unlock()
            rebuildHoverText(using: snapshot)
        }
    }

    var showsCapacityAvailable: Bool {
        get {
            hoverStateLock.lock()
            defer { hoverStateLock.unlock() }
            return showsCapacityAvailableValue
        }
        set {
            hoverStateLock.lock()
            showsCapacityAvailableValue = newValue
            let snapshot = lastSnapshot
            hoverStateLock.unlock()
            rebuildHoverText(using: snapshot)
        }
    }

    var showsCapacityTotal: Bool {
        get {
            hoverStateLock.lock()
            defer { hoverStateLock.unlock() }
            return showsCapacityTotalValue
        }
        set {
            hoverStateLock.lock()
            showsCapacityTotalValue = newValue
            let snapshot = lastSnapshot
            hoverStateLock.unlock()
            rebuildHoverText(using: snapshot)
        }
    }

    var showsVolumeList: Bool {
        get {
            hoverStateLock.lock()
            defer { hoverStateLock.unlock() }
            return showsVolumeListValue
        }
        set {
            hoverStateLock.lock()
            showsVolumeListValue = newValue
            let snapshot = lastSnapshot
            hoverStateLock.unlock()
            rebuildHoverText(using: snapshot)
        }
    }

    var hoverText: String {
        hoverStateLock.lock()
        defer { hoverStateLock.unlock() }
        return hoverTextValue
    }

    override func update() async -> Bool {
        let now = Date().timeIntervalSinceReferenceDate
        if now - lastPollTime < 5.0 {
            return false
        }
        lastPollTime = now

        guard let snapshot = readSnapshot() else {
            let displayChanged = setDisplayValueIfChanged("—")
            let hoverChanged = setHoverTextIfChanged("Disk usage unavailable")
            return displayChanged || hoverChanged
        }

        let percent = min(max(Double(snapshot.usedBytes) / Double(snapshot.totalBytes), 0.0), 1.0)
        let displayChanged = setDisplayValueIfChanged("\(Int((percent * 100.0).rounded()))%")

        setLastSnapshot(snapshot)

        let hoverChanged = setHoverTextIfChanged(hoverText(for: snapshot))
        return displayChanged || hoverChanged
    }

    private func readSnapshot() -> DiskSnapshot? {
        do {
            let attributes = try FileManager.default.attributesOfFileSystem(forPath: "/")
            guard let total = (attributes[.systemSize] as? NSNumber)?.uint64Value,
                  let free = (attributes[.systemFreeSize] as? NSNumber)?.uint64Value,
                  total > 0 else {
                return nil
            }

            let used = total >= free ? (total - free) : 0
            let volumes = readVolumes()
            return DiskSnapshot(
                usedBytes: used,
                availableBytes: free,
                totalBytes: total,
                volumes: volumes
            )
        } catch {
            return nil
        }
    }

    private func readVolumes() -> [VolumeUsage] {
        let keys: Set<URLResourceKey> = [
            .volumeNameKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey
        ]

        guard let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: Array(keys),
            options: [.skipHiddenVolumes]
        ) else {
            return []
        }

        let usages = urls.compactMap { url -> VolumeUsage? in
            guard let values = try? url.resourceValues(forKeys: keys),
                  let total = values.volumeTotalCapacity,
                  let available = values.volumeAvailableCapacity,
                  total > 0 else {
                return nil
            }

            let name = values.volumeName ?? url.lastPathComponent
            return VolumeUsage(name: name.isEmpty ? "/" : name, freeBytes: UInt64(max(available, 0)))
        }

        return usages.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func rebuildHoverText(using snapshot: DiskSnapshot?) {
        guard let snapshot else { return }
        _ = setHoverTextIfChanged(hoverText(for: snapshot))
    }

    private func setLastSnapshot(_ snapshot: DiskSnapshot) {
        hoverStateLock.lock()
        lastSnapshot = snapshot
        hoverStateLock.unlock()
    }

    private func hoverText(for snapshot: DiskSnapshot) -> String {
        let mode = hoverMode
        switch mode {
        case .capacity:
            var lines: [String] = []
            if showsCapacityUsed {
                lines.append("Used: \(formatGigabytes(snapshot.usedBytes))")
            }
            if showsCapacityAvailable {
                lines.append("Available: \(formatGigabytes(snapshot.availableBytes))")
            }
            if showsCapacityTotal {
                lines.append("Total: \(formatGigabytes(snapshot.totalBytes))")
            }
            return lines.isEmpty ? "No capacity fields selected." : lines.joined(separator: "\n")
        case .volumes:
            guard showsVolumeList else { return "Volume list hidden." }
            guard !snapshot.volumes.isEmpty else { return "No volumes detected." }
            return snapshot.volumes
                .map { "\($0.name): \(formatStorage($0.freeBytes)) free" }
                .joined(separator: "\n")
        }
    }

    private func formatGigabytes(_ bytes: UInt64) -> String {
        let value = Double(bytes) / 1_073_741_824.0
        return String(format: "%.1f GB", value)
    }

    private func formatStorage(_ bytes: UInt64) -> String {
        let value = Double(bytes)
        let kb = 1_024.0
        let mb = kb * 1_024.0
        let gb = mb * 1_024.0
        let tb = gb * 1_024.0

        if value >= tb {
            return String(format: "%.1f TB", value / tb)
        }
        if value >= gb {
            return String(format: "%.1f GB", value / gb)
        }
        if value >= mb {
            return String(format: "%.0f MB", value / mb)
        }
        return String(format: "%.0f KB", max(value / kb, 0))
    }

    private func setHoverTextIfChanged(_ text: String) -> Bool {
        hoverStateLock.lock()
        defer { hoverStateLock.unlock() }
        guard hoverTextValue != text else { return false }
        hoverTextValue = text
        return true
    }
}
