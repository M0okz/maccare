import SwiftUI

struct ActivityView: View {
    @ObservedObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            HStack {
                Text("Activité récente").font(AppFont.section.bold())
                Spacer()
                Button("Fermer") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Text("Comptes rendus de cette session et dernière analyse enregistrée. Les opérations restent soumises à votre validation.")
                .font(AppFont.body).foregroundStyle(Theme.muted)
            if app.activity.isEmpty {
                Text("Les analyses et opérations terminées apparaîtront ici.")
                    .foregroundStyle(Theme.muted).padding(.vertical, Space.xl)
            } else {
                ScrollView {
                    VStack(spacing: Space.s) {
                        ForEach(app.activity) { entry in
                            Button {
                                app.module = entry.module
                                dismiss()
                            } label: {
                                HStack(alignment: .top, spacing: Space.m) {
                                    Image(systemName: entry.module.symbol).accessibilityHidden(true)
                                        .foregroundStyle(Theme.accentInk)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(entry.title).font(AppFont.emphasis)
                                        Text(entry.detail).font(AppFont.body).foregroundStyle(Theme.muted)
                                    }
                                    Spacer()
                                    Text(entry.date, style: .time).font(AppFont.caption).foregroundStyle(Theme.muted)
                                    Image(systemName: "chevron.right").accessibilityHidden(true)
                                }
                                .padding(Space.m).frame(maxWidth: .infinity, alignment: .leading).card()
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(Space.xl)
        .frame(minWidth: 560, idealWidth: 640, minHeight: 260, idealHeight: 440)
        .preferredColorScheme(.dark)
    }
}
