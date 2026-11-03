import SwiftUI

struct TrayMemoryRing: View {
    let memory: TrayMetrics.Memory
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var values: [Double] { [Double(memory.active), Double(memory.wired), Double(memory.compressed), Double(memory.available)] }
    private let colors: [Color] = [.cyan, .blue, Color(red: 0.61, green: 0.35, blue: 1), .white.opacity(0.13)]
    private let titles = ["Active", "Non paginable", "Compressée", "Disponible"]

    var body: some View {
        HStack(spacing: 18) {
            ZStack {
                ForEach(values.indices, id: \.self) { index in
                    Circle().trim(from: start(index), to: start(index + 1))
                        .stroke(colors[index], style: StrokeStyle(lineWidth: 20, lineCap: .butt))
                        .rotationEffect(.degrees(-90))
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.85), value: values)
                }
                VStack(spacing: 4) {
                    TrayRollingValue(text: humanSize(memory.available), value: Double(memory.available))
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
                            TrayRollingValue(text: humanSize(UInt64(values[index])), value: values[index])
                                .font(.caption.weight(.semibold))
                        }
                    }.accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func start(_ index: Int) -> Double {
        values.prefix(index).reduce(0, +) / max(values.reduce(0, +), 1)
    }
}
