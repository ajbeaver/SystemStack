import SwiftUI

struct ConfigurationView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        NavigationSplitView {
            List(AppState.SidebarSection.allCases, selection: $appState.selectedSection) { section in
                Label(section.rawValue, systemImage: section.symbolName)
                    .tag(section)
            }
            .listStyle(.sidebar)
        } detail: {
            Group {
                switch appState.selectedSection ?? .modules {
                case .modules:
                    ModulesView()
                case .layout:
                    LayoutView()
                case .appearance:
                    AppearanceView()
                case .general:
                    GeneralView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationSplitViewStyle(.balanced)
    }
}
