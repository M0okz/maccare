import SwiftUI

/// Petit repère visuel, avec une cible native plus large que le symbole.
struct ApplicationCardInfoButton: View {
    let information: ApplicationCardInformation
    var arrowEdge: Edge = .bottom
    let onDetails: () -> Void
    @State private var presented = false

    var body: some View {
        Button { presented.toggle() } label: {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 14, weight: .regular))
                .frame(width: 28, height: 28).contentShape(Rectangle())
                .accessibilityHidden(true)
        }
        .buttonStyle(.plain).foregroundStyle(Theme.muted)
        .accessibilityLabel("À propos : \(information.title)")
        .accessibilityHint("Afficher une explication de cette catégorie")
        .help("À propos : \(information.title)")
        .popover(isPresented: $presented, arrowEdge: arrowEdge) {
            VStack(alignment: .leading, spacing: 14) {
                Text(information.title).font(AppFont.emphasis).accessibilityAddTraits(.isHeader)
                Text(information.summary).foregroundStyle(Theme.muted)
                if !information.criteria.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(information.criteria, id: \.self) { criterion in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "circle.fill").font(.system(size: 5))
                                    .foregroundStyle(Theme.accentInk).padding(.top, 7).accessibilityHidden(true)
                                Text(criterion).fixedSize(horizontal: false, vertical: true)
                            }.accessibilityElement(children: .combine)
                        }
                    }
                }
                Text(information.footnote).foregroundStyle(Theme.muted)
                Divider()
                Button {
                    presented = false
                    onDetails()
                } label: { Label("En savoir plus…", systemImage: "arrow.right.circle.fill") }
                    .buttonStyle(.plain).font(AppFont.secondary.weight(.semibold)).foregroundStyle(Theme.accentInk)
                    .padding(.vertical, 4)
                    .accessibilityLabel("En savoir plus : \(information.title)")
            }
            .font(AppFont.secondary).foregroundStyle(Theme.fg)
            .padding(20).frame(width: 350)
            .fixedSize(horizontal: false, vertical: true)
            .background(.regularMaterial)
            .onExitCommand { presented = false }
        }
    }
}
