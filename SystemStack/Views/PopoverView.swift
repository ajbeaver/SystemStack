import SwiftUI

struct PopoverView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SystemStack")
                .font(.headline)

            Text("Status Preview")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(appState.plainStatusPreviewText())
                .font(.system(.body, design: .monospaced))

            HStack {
                Button("Quit") {
                    NSApp.terminate(nil)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
