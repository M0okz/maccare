import SwiftUI

struct MaintenanceView: View {
    @ObservedObject var model: MaintenanceModel
    @State private var confirming: MaintenanceTask?
    @State private var selectedKey = "lsregister"
    private var selected: MaintenanceTask? { model.tasks.first { $0.key == selectedKey } ?? model.tasks.first }
    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("Réparer l’affichage").font(AppFont.emphasis).accessibilityAddTraits(.isHeader)
                        Text("Choisissez le problème rencontré et examinez la réparation proposée.").font(AppFont.secondary).foregroundStyle(Theme.muted)
                        ScrollView {
                            VStack(spacing: 7) {
                                ForEach(model.tasks) { task in
                                    Button { selectedKey = task.key } label: {
                                        HStack(spacing: 12) {
                                            ModuleIcon(symbol: symbol(task), color: ModuleColor.maint, size: 32).accessibilityHidden(true)
                                            Text(task.title).font(AppFont.body.weight(.medium)).multilineTextAlignment(.leading)
                                            Spacer(minLength: 0)
                                        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                                            .background(selected?.id == task.id ? Theme.accent.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 10))
                                            .contentShape(RoundedRectangle(cornerRadius: 10))
                                    }.buttonStyle(.plain).disabled(model.running != nil).accessibilityAddTraits(selected?.id == task.id ? .isSelected : [])
                                }
                            }
                        }
                    }.padding(20).frame(width: max(240, min(310, geometry.size.width * 0.28)))
                    Divider()
                    ScrollView {
                        if let task = selected {
                            VStack(alignment: .leading, spacing: 22) {
                                ModuleIcon(symbol: symbol(task), color: ModuleColor.maint, size: 56).accessibilityHidden(true)
                                Text(task.title).font(AppFont.metric).accessibilityAddTraits(.isHeader)
                                Text(task.note).font(AppFont.emphasis)
                                Text("Effet de la réparation").font(AppFont.body.weight(.semibold))
                                Text(task.effect).font(AppFont.body).foregroundStyle(Theme.muted)
                                Text("Cette réparation concerne votre compte utilisateur. Aucun mot de passe administrateur n’est demandé.")
                                    .font(AppFont.secondary).foregroundStyle(Theme.muted)
                                if let result = model.results[task.key] {
                                    Label(result.message, systemImage: result.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                        .foregroundStyle(result.ok ? Theme.ok : Theme.warn)
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(28)
                        }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            Divider()
            ToolManagerFooter {
                VStack(alignment: .leading, spacing: 5) {
                    Text(selected?.title ?? "Choisissez une réparation").font(AppFont.body.weight(.semibold))
                    Text("Une confirmation précède chaque réparation.").font(AppFont.secondary).foregroundStyle(Theme.muted)
                }
            } actions: {
                if model.running != nil { ProgressView("Réparation…") }
                Button("Réparer…") { confirming = selected }.buttonStyle(.borderedProminent).disabled(model.running != nil || selected == nil)
            }
        }
        .sheet(item: $confirming) { task in
            VStack(alignment: .leading, spacing: 20) {
                Text(task.title).font(.system(size: 28, weight: .semibold)).accessibilityAddTraits(.isHeader)
                Text(task.note).font(AppFont.body).foregroundStyle(Theme.muted)
                Text(task.effect).font(AppFont.body).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    Button("Annuler") { confirming = nil }.keyboardShortcut(.cancelAction)
                    Button("Lancer la réparation") {
                        confirming = nil
                        model.run(task)
                    }.buttonStyle(.borderedProminent).disabled(model.running != nil)
                }
            }.padding(28).frame(width: 500).modifier(ToolConfirmationStyle())
        }
    }

    private func symbol(_ task: MaintenanceTask) -> String {
        switch task.key {
        case "lsregister": return "app.badge"
        case "quicklook": return "doc.viewfinder"
        default: return "textformat"
        }
    }
}
