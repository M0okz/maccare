import SwiftUI

struct QuickToolsButton: View {
    let app: AppState
    @State private var showingTools = false

    var body: some View {
        Button { showingTools.toggle() } label: {
            HStack(spacing: 8) {
                Label("Accès rapide", systemImage: "square.grid.2x2")
                Image(systemName: "chevron.down").font(.caption).accessibilityHidden(true)
            }
        }
        .buttonStyle(.bordered).controlSize(.large)
        .help("Accès rapide aux outils")
        .popover(isPresented: $showingTools, arrowEdge: .bottom) {
            QuickToolsList(app: app) { showingTools = false }
        }
    }
}

struct QuickToolsList: View {
    let app: AppState
    let close: () -> Void
    @AppStorage(DeveloperTools.key) private var developerTools = DeveloperTools.defaultValue

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Mes outils").font(.headline).accessibilityAddTraits(.isHeader)
                Spacer()
                PopoverCloseButton(action: close)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            ForEach(NavigationSection.tools.destinations.dropFirst()) { module in
                tool(module)
            }
            if developerTools {
                Divider().padding(.vertical, 4)
                ForEach(NavigationSection.cleaning.destinations.filter(\.isDeveloper)) { module in
                    tool(module)
                }
            }
        }
        .padding(8).frame(width: 295)
        .onExitCommand(perform: close)
    }

    private func tool(_ module: Module) -> some View {
        Button {
            close()
            app.openTool(module)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: module.symbol).foregroundStyle(module.color)
                    .frame(width: 22).accessibilityHidden(true)
                Text(module.title)
            }
            .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
            .padding(.horizontal, 8).contentShape(Rectangle())
        }
        .buttonStyle(SidebarRowStyle(selected: app.module == module))
    }
}

struct PopoverCloseButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill").font(.body).foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain).keyboardShortcut(.cancelAction)
        .accessibilityLabel("Fermer").help("Fermer")
    }
}
