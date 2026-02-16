import AppKit
import Foundation

enum ModuleVisuals {
    static let networkSparklineWidth = 20
    static let standardSparklineWidth = networkSparklineWidth + 1
}

protocol MenuModule: AnyObject, Sendable {
    var id: String { get }
    var symbolName: String? { get }
    var isEnabled: Bool { get set }
    var showsValue: Bool { get set }
    var displayValue: String { get }
    func update() async -> Bool
}

protocol TitledMenuModule: MenuModule {
    var title: String { get }
}

class BaseMenuModule: TitledMenuModule, @unchecked Sendable {
    let id: String
    let title: String
    let symbolName: String?

    @MainActor var statusItem: NSStatusItem?

    private let stateLock = NSLock()
    private var enabled: Bool
    private var shouldShowValue: Bool
    private var value: String

    init(
        id: String,
        title: String,
        symbolName: String?,
        isEnabled: Bool = false,
        showsValue: Bool = true,
        defaultDisplayValue: String = "—"
    ) {
        self.id = id
        self.title = title
        self.symbolName = symbolName
        self.enabled = isEnabled
        self.shouldShowValue = showsValue
        self.value = defaultDisplayValue
    }

    var isEnabled: Bool {
        get {
            stateLock.lock()
            defer { stateLock.unlock() }
            return enabled
        }
        set {
            stateLock.lock()
            enabled = newValue
            stateLock.unlock()
        }
    }

    var displayValue: String {
        stateLock.lock()
        defer { stateLock.unlock() }
        return value
    }

    var showsValue: Bool {
        get {
            stateLock.lock()
            defer { stateLock.unlock() }
            return shouldShowValue
        }
        set {
            stateLock.lock()
            shouldShowValue = newValue
            stateLock.unlock()
        }
    }

    func update() async -> Bool {
        setDisplayValueIfChanged("—")
    }

    @discardableResult
    func setDisplayValueIfChanged(_ newValue: String) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }

        guard value != newValue else { return false }
        value = newValue
        return true
    }
}
