import SwiftUI

struct SectionNavigationView: View {
    @Binding var module: Module?
    @AppStorage(DeveloperTools.key) private var developerTools = DeveloperTools.defaultValue

    private var section: NavigationSection { (module ?? .dashboard).section }
    private var destinations: [Module] { section.destinations(developerTools: developerTools) }

    var body: some View {
        if section != .applications && section != .cleaning && section != .files && section != .tools && destinations.count > 1 {
            Picker(section.title, selection: Binding(
                get: { module ?? section.defaultDestination },
                set: { module = $0 }
            )) {
                ForEach(destinations) { destination in
                    Text(destination.tabTitle).tag(destination)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.large)
            .font(AppFont.body)
            .labelsHidden()
            .accessibilityLabel("Vues de la rubrique \(section.title)")
            .padding(.horizontal, Space.xl)
            .padding(.top, Space.l)
            .onChange(of: developerTools) { enabled in
                if !enabled, module?.isDeveloper == true { module = section.defaultDestination }
            }
        }
    }
}
