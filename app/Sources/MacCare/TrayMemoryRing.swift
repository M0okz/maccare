import SwiftUI

/// Les mémoires lissées changent à chaque seconde. Arrondir au pour-cent évite de
/// redessiner l’anneau pour des variations invisibles. Il n’est pas animé : une valeur
/// proche d’un seuil relancerait l’animation à chaque relevé.
enum TrayMemoryRingLayout {
    static func rounded(_ fraction: Double) -> Double { (min(1, max(0, fraction)) * 100).rounded() / 100 }

    static func boundaries(_ values: [Double]) -> [Double] {
        let total = max(values.reduce(0, +), 1)
        var sum = 0.0
        return [0] + values.map { value in
            sum += value
            return rounded(sum / total)
        }
    }
}

struct TrayMemoryRing: View {
    let memory: TrayMetrics.Memory
    private var values: [Double] { [Double(memory.active), Double(memory.wired), Double(memory.compressed), Double(memory.available)] }
    private let colors: [Color] = [.cyan, .blue, Color(red: 0.61, green: 0.35, blue: 1), .white.opacity(0.13)]
    private let titles = ["Active", "Non paginable", "Compressée", "Disponible"]
    private var boundaries: [Double] { TrayMemoryRingLayout.boundaries(values) }

    var body: some View {
        HStack(spacing: 18) {
            ZStack {
                ForEach(values.indices, id: \.self) { index in
                    Circle().trim(from: boundaries[index], to: boundaries[index + 1])
                        .stroke(colors[index], style: StrokeStyle(lineWidth: 20, lineCap: .butt))
                        .rotationEffect(.degrees(-90))
                }
                VStack(spacing: 4) {
                    Text(humanSize(memory.available)).monospacedDigit()
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                    Text("disponibles").font(.caption)
                    Text("sur \(humanSize(memory.total))").font(.caption2).foregroundStyle(.white.opacity(0.72))
                }
            }
            .frame(width: 164, height: 164).padding(10)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Mémoire disponible")
            .accessibilityValue("\(humanSize(memory.available)) sur \(humanSize(memory.total))")
            VStack(alignment: .leading, spacing: 12) {
                ForEach(values.indices, id: \.self) { index in
                    HStack(alignment: .top, spacing: 6) {
                        Circle().fill(colors[index]).frame(width: 7, height: 7).padding(.top, 4).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(titles[index]).font(.caption).foregroundStyle(.white.opacity(0.78))
                            Text(humanSize(UInt64(values[index]))).monospacedDigit()
                                .font(.caption.weight(.semibold))
                        }
                    }.accessibilityElement(children: .combine)
                }
            }
        }
    }
}
