import SwiftUI
import MacCareHelperProtocol

struct HomeFanControls: View {
    let fans: TrayFans?
    @State private var lastApplied: FanPreset?
    @State private var applying = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if fans?.supportsControl == true {
                HStack(spacing: Space.s) {
                    ForEach(FanPreset.allCases, id: \.self) { preset in
                        let isSelected = selected == preset
                        Button { apply(preset) } label: {
                            Text(preset.title)
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(isSelected ? Theme.fg : Theme.muted)
                                .lineLimit(1)
                                .frame(minWidth: 0, maxWidth: 56, minHeight: 24)
                                .background(isSelected ? Theme.accent.opacity(0.28) : Theme.fg.opacity(0.09), in: Capsule())
                                .overlay {
                                    if isSelected {
                                        Capsule().strokeBorder(Theme.accentInk.opacity(0.55))
                                    }
                                }
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                        .accessibilityLabel("Ventilation " + preset.title)
                        .help(hint(for: preset))
                    }
                }
                .disabled(applying)
            }
            Text(fans?.controlText ?? "Lecture indisponible").font(AppFont.caption).foregroundStyle(Theme.muted)
        }
        .alert("Réglage des ventilateurs", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }

    private var selected: FanPreset? {
        guard let fans else { return nil }
        if fans.automatic { return .automatic }
        if fans.atMaximum { return .maximum }
        if lastApplied == .cool && fans.fans.allSatisfy({ $0.manual == true }) { return .cool }
        return nil
    }

    private func hint(for preset: FanPreset) -> String {
        switch preset {
        case .automatic: return "Rendre à macOS les ventilateurs pilotés par MacCare."
        case .cool: return "Ventiler à au moins 65 % pendant cinq minutes."
        case .maximum: return "Ventiler à la vitesse maximale pendant cinq minutes."
        }
    }

    private func apply(_ preset: FanPreset) {
        guard !applying else { return }
        guard HelperClient.status == .enabled else {
            if preset == .automatic && fans?.automatic == true { return }
            error = AppBuildIdentity.isDevelopment
                ? "Cette commande nécessite un assistant système MacCare compatible et activé. Cet aperçu DEV utilise la lecture des capteurs."
                : "Activez l’assistant système dans les autorisations de MacCare pour régler les ventilateurs."
            return
        }
        applying = true
        Task { @MainActor in
            defer { applying = false }
            do {
                try await HelperClient.setFanPreset(preset)
                lastApplied = preset
            }
            catch { self.error = error.localizedDescription }
        }
    }
}
