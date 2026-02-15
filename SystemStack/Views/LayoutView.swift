import SwiftUI
import UniformTypeIdentifiers

struct LayoutView: View {
    @EnvironmentObject private var appState: AppState
    @State private var draggingModuleID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Menu Bar Preview")
                .font(.title3)
                .fontWeight(.semibold)

            Text("Drag enabled modules to reorder. Remove disables a module.")
                .foregroundStyle(.secondary)

            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(appState.enabledModules, id: \.id) { module in
                        ModuleCapsuleView(module: module) {
                            appState.removeFromLayout(id: module.id)
                        }
                        .onDrag {
                            draggingModuleID = module.id
                            return NSItemProvider(object: module.id as NSString)
                        }
                        .onDrop(of: [UTType.text], delegate: ModuleReorderDropDelegate(
                            targetID: module.id,
                            appState: appState,
                            draggingModuleID: $draggingModuleID
                        ))
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))

            Spacer()
        }
        .padding(20)
    }
}

private struct ModuleCapsuleView: View {
    let module: any MenuModule
    let onRemove: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: module.symbolName ?? "questionmark.square")
                .foregroundStyle(.secondary)

            if isHovering {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(isHovering ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.tertiary))
        )
        .overlay(
            Capsule()
                .strokeBorder(.quinary, lineWidth: 1)
        )
        .onHover { isHovering = $0 }
    }
}

private struct ModuleReorderDropDelegate: DropDelegate {
    let targetID: String
    let appState: AppState
    @Binding var draggingModuleID: String?

    func dropEntered(info: DropInfo) {
        guard let draggingModuleID else { return }
        appState.moveEnabledModule(draggedID: draggingModuleID, before: targetID)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingModuleID = nil
        return true
    }
}
