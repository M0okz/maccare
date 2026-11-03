import SwiftUI

struct HomeStorageCard: View {
    let free: UInt64
    let total: UInt64
    let action: () -> Void
    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var used: UInt64 { total - min(free, total) }
    private var fraction: Double { Double(used) / Double(max(total, 1)) }
    private var percentage: Int { Int(fraction * 100) }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Label("Disque de démarrage", systemImage: "internaldrive").font(.headline)
                    Spacer(minLength: 4)
                    Image(systemName: "arrow.up.right").font(AppFont.secondary).foregroundStyle(Theme.muted).accessibilityHidden(true)
                }
                HStack(spacing: 18) {
                    ZStack {
                        Circle().stroke(.white.opacity(0.09), lineWidth: 9)
                        Circle().trim(from: 0, to: fraction)
                            .stroke(ModuleColor.space.gradient, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .brightness(hovered ? 0.18 : 0)
                            .shadow(color: ModuleColor.space.opacity(hovered ? 0.7 : 0), radius: 10)
                            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: hovered)
                        Text("\(percentage) %").font(.title3.weight(.semibold)).monospacedDigit()
                    }.frame(width: 82, height: 82)
                        .accessibilityElement(children: .ignore)
                        .accessibilityAddTraits(.isImage)
                        .accessibilityLabel("Stockage utilisé").accessibilityValue("\(percentage) %")
                    VStack(alignment: .leading, spacing: 5) {
                        Text(humanSize(free)).font(.title2.weight(.semibold)).monospacedDigit()
                        Text("libres sur \(humanSize(total))").font(AppFont.secondary).foregroundStyle(Theme.muted)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                Text("\(humanSize(used)) utilisés").font(AppFont.secondary).foregroundStyle(Theme.muted)
            }
            .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .contentShape(RoundedRectangle(cornerRadius: 22))
        }
        .buttonStyle(HomeStorageCardStyle())
        .onHover { hovered = $0 }
        .foregroundStyle(Theme.fg)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Disque de démarrage")
        .accessibilityValue("\(percentage) % utilisés, \(humanSize(free)) libres sur \(humanSize(total))")
        .accessibilityHint("Ouvrir Espace disque")
    }
}

struct HomeStorageCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HomeStorageCardSurface(label: configuration.label, pressed: configuration.isPressed)
    }
}

private struct HomeStorageCardSurface<Label: View>: View {
    let label: Label
    let pressed: Bool
    @Environment(\.isEnabled) private var enabled
    @Environment(\.isFocused) private var focused

    var body: some View {
        label
            .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(
                .white.opacity(enabled && focused ? 0.8 : 0.1),
                lineWidth: enabled && focused ? 2 : 1))
            .opacity(!enabled ? 0.45 : (pressed ? 0.8 : 1))
    }
}
