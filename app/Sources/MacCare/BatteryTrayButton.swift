import SwiftUI

struct BatteryTrayButton: View {
    @ObservedObject var model: BatteryModel
    let open: () -> Void
    var body: some View {
        if let snapshot = model.snapshot, snapshot.present {
            Button(action: open) {
                HStack(spacing: 12) {
                    Image(systemName: model.active ? "checkmark.shield" : "battery.75percent")
                        .foregroundStyle(Theme.ok).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(snapshot.percent.map { "Batterie · \($0) %" } ?? "Batterie")
                            .font(.body.weight(.semibold)).monospacedDigit()
                        Text(model.message).font(.callout).foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").accessibilityHidden(true)
                }.padding(14).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: Radius.card))
            }.buttonStyle(.plain)
        }
    }
}
