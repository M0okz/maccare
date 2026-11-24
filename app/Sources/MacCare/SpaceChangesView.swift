import SwiftUI

struct SpaceChangesView: View {
    let comparison: SpaceComparison
    let open: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text("Depuis la dernière analyse").font(AppFont.section).accessibilityAddTraits(.isHeader)
            switch comparison {
            case .unavailable(let reason):
                Text(reason).foregroundStyle(Theme.muted)
            case .baseline:
                Text("Première mesure enregistrée. Actualisez ce dossier après une modification pour voir ce qui a changé.")
                    .foregroundStyle(Theme.muted)
            case .compared(let date, let changes):
                Text("Comparaison avec la mesure du \(date.formatted(date: .abbreviated, time: .standard)).")
                    .font(AppFont.secondary).foregroundStyle(Theme.muted)
                if changes.isEmpty {
                    Text("Aucune variation de taille des dossiers mesurés.")
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(changes) { change in
                                if change.after != nil {
                                    Button { open(change.name) } label: { row(change) }
                                        .buttonStyle(.plainAction)
                                        .accessibilityLabel("\(change.name), \(change.label)")
                                        .accessibilityHint("Ouvre le dossier dans la carte")
                                } else {
                                    row(change).accessibilityElement(children: .combine)
                                }
                                Divider()
                            }
                        }
                    }
                }
            }
        }
        .padding(Space.l).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.surface.opacity(0.65), in: RoundedRectangle(cornerRadius: 18))
    }

    private func row(_ change: SpaceComparison.Change) -> some View {
        HStack(spacing: Space.m) {
            Image(systemName: "folder").foregroundStyle(Theme.muted).accessibilityHidden(true)
            Text(change.name).lineLimit(2).truncationMode(.middle)
            Spacer(minLength: Space.m)
            Text(change.label).font(AppFont.body.weight(.semibold)).monospacedDigit()
            if change.after != nil {
                Image(systemName: "chevron.right").foregroundStyle(Theme.muted).accessibilityHidden(true)
            }
        }
        .frame(minHeight: 44).contentShape(Rectangle())
    }
}
