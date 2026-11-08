import SwiftUI

/// Une bulle placée : un enfant du dossier, son centre et son rayon (rayon ∝ √taille).
struct PackedBubble: Identifiable {
    let child: SpaceChild
    let center: CGPoint
    let radius: CGFloat
    var id: String { child.id }
}

/// Empilement glouton : la plus grosse bulle au centre, les suivantes placées le long d'une
/// spirale au premier emplacement libre. Déterministe, sans simulation physique.
enum BubblePacker {
    static func pack(_ children: [SpaceChild], in size: CGSize, maxCount: Int = 16) -> [PackedBubble] {
        guard maxCount > 0, size.width >= 44, size.height >= 44, !children.isEmpty else { return [] }
        let items = Array(children.filter { $0.size_bytes > 0 }.sorted {
            $0.size_bytes == $1.size_bytes ? $0.path < $1.path : $0.size_bytes > $1.size_bytes
        }.prefix(maxCount))
        let maxBytes = Double(items.map { $0.size_bytes }.max() ?? 1)
        guard maxBytes > 0 else { return [] }

        let big = max(22, min(size.width, size.height) * 0.27)
        let small: CGFloat = 22
        func radius(_ b: UInt64) -> CGFloat {
            let f = CGFloat((Double(b) / maxBytes).squareRoot())   // 0…1
            return small + f * (big - small)
        }

        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        var placed: [(CGPoint, CGFloat)] = []
        var result: [PackedBubble] = []

        for item in items {
            let r = radius(item.size_bytes)
            guard let p = spot(r: r, placed: placed, center: center, size: size) else { continue }
            placed.append((p, r))
            result.append(PackedBubble(child: item, center: p, radius: r))
        }
        return result
    }

    private static func spot(r: CGFloat, placed: [(CGPoint, CGFloat)], center: CGPoint, size: CGSize) -> CGPoint? {
        if placed.isEmpty { return center }
        let gap: CGFloat = 7
        let pad: CGFloat = 10
        var t: CGFloat = 0
        while t < 14000 {
            let a = t * 0.3
            let d = 4.2 * t.squareRoot()
            let p = CGPoint(x: center.x + cos(a) * d, y: center.y + sin(a) * d)
            if p.x - r >= pad, p.x + r <= size.width - pad, p.y - r >= pad, p.y + r <= size.height - pad {
                var ok = true
                for (c, rr) in placed {
                    let dx = p.x - c.x, dy = p.y - c.y
                    if (dx * dx + dy * dy).squareRoot() < r + rr + gap { ok = false; break }
                }
                if ok { return p }
            }
            t += 1
        }
        // Les éléments sans place restent dans la liste, au lieu de créer des bulles superposées.
        return nil
    }
}

/// Carte des principaux éléments ; le survol est partagé avec la liste de l’explorateur.
struct SpaceBubblesView: View {
    @ObservedObject var model: SpaceModel
    var onMapHighlight: (String?) -> Void = { _ in }
    var onRequestRemoval: (SpaceChild) -> Void = { _ in }
    @State private var hoveredPath: String?

    private let palette: [Color] = [
        Color(hex: "#9D6CFF"), Color(hex: "#C45CE0"), Color(hex: "#6A5FE0"),
        Color(hex: "#4F46E5"), Color(hex: "#2F7BF6"), Color(hex: "#0EA5C4"),
    ]

    var body: some View {
        GeometryReader { geo in
            let bubbles = BubblePacker.pack(model.children, in: geo.size)
            ZStack {
                ForEach(Array(bubbles.enumerated()), id: \.element.id) { idx, b in
                    bubble(b, color: palette[idx % palette.count])
                }
                if bubbles.isEmpty {
                    Text("Aucune taille représentable dans la carte. Consultez la liste.")
                        .font(AppFont.body).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location): updateHover(BubbleHitTest.path(at: location, in: bubbles))
                case .ended: updateHover(nil)
                }
            }
            .onChange(of: geo.size) { _ in updateHover(nil) }
        }
        .onDisappear { updateHover(nil) }
    }

    private func updateHover(_ path: String?) {
        guard hoveredPath != path else { return }
        hoveredPath = path
        model.highlight(path, from: .map)
        onMapHighlight(path)
    }

    private func bubble(_ b: PackedBubble, color: Color) -> some View {
        let highlighted = (model.highlightedPath ?? model.selectedPath) == b.id
        let r = b.radius
        return Button {
            model.select(b.child)
        } label: {
            ZStack {
                Circle().fill(RadialGradient(colors: [color.shade(0.30), color.shade(-0.22)],
                                            center: UnitPoint(x: 0.4, y: 0.34), startRadius: 1, endRadius: r * 1.25))
                Circle().strokeBorder(highlighted ? Color.white : Color.white.opacity(0.2), lineWidth: highlighted ? 2 : 1)
                VStack(spacing: 3) {
                    Image(systemName: b.child.is_dir ? "folder.fill" : "doc.fill")
                        .font(.system(size: min(r * 0.55, 64), weight: .semibold)).accessibilityHidden(true)
                    if r >= 38 {
                        Text(b.child.name).font(.system(size: max(13, min(r * 0.22, 15)), weight: .semibold))
                            .lineLimit(1).frame(maxWidth: r * 1.7)
                        Text(b.child.sizeLabel).font(AppFont.caption).monospacedDigit().lineLimit(1)
                    }
                }.foregroundStyle(.white).padding(5)
            }
            .frame(width: r * 2, height: r * 2)
            .contentShape(Circle())
            .shadow(color: color.opacity(highlighted ? 0.65 : 0.3), radius: r * 0.2)
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .simultaneousGesture(TapGesture(count: 2).onEnded {
            if b.child.is_dir { model.open(b.child) }
        })
        .accessibilityLabel("\(b.child.name), \(b.child.sizeLabel)")
        .accessibilityValue(model.highlightedPath == b.id ? "Survolé" : model.selectedPath == b.id ? "Sélectionné" : "")
        .accessibilityHint(b.child.is_dir ? "Ouvre ce dossier" : "Affiche les informations du fichier")
        .accessibilityAction {
            if b.child.is_dir { model.open(b.child) } else { model.select(b.child) }
        }
        .contextMenu {
            Button("Afficher dans le Finder") { model.revealInFinder(b.child) }
            if model.canRemove(b.child) { Button(model.directDeleteLabel, role: .destructive) { onRequestRemoval(b.child) } }
        }
        .position(b.center)
    }
}
