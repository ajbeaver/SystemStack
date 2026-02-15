import Foundation

protocol MenuModule {
    var id: String { get }
    var title: String { get }
    var symbolName: String? { get }
    var isEnabled: Bool { get set }
    func statusValueText() -> String
}

class BaseStubModule: MenuModule {
    let id: String
    let title: String
    let symbolName: String?
    var isEnabled: Bool

    init(id: String, title: String, symbolName: String?, isEnabled: Bool = false) {
        self.id = id
        self.title = title
        self.symbolName = symbolName
        self.isEnabled = isEnabled
    }

    func statusValueText() -> String {
        "--"
    }
}
