import SwiftUI

struct TrayStorageGrid: View {
    static let rows = 6
    static let columns = 12
    let free: UInt64
    let total: UInt64

    static func occupiedCells(free: UInt64, total: UInt64) -> Int? {
        guard total > 0 else { return nil }
        let fraction = Double(total - min(free, total)) / Double(total)
        return min(rows * columns, max(0, Int((fraction * Double(rows * columns)).rounded())))
    }

    var body: some View {
        let count = Self.occupiedCells(free: free, total: total)
        VStack(spacing: 2) {
            ForEach(0..<Self.rows, id: \.self) { row in
                HStack(spacing: 2) {
                    ForEach(0..<Self.columns, id: \.self) { column in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(row * Self.columns + column < (count ?? 0) ? TrayAppearance.accent : .white.opacity(0.12))
                            .frame(width: 4, height: 4)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Occupation du stockage interne")
        .accessibilityValue(count.map { "Environ \($0) carrés occupés sur \(Self.rows * Self.columns)" } ?? "Indisponible")
        .help(total > 0 ? "\(Int((Double(total - min(free, total)) / Double(total) * 100).rounded())) % utilisés · estimation sur 72 carrés" : "Occupation indisponible")
    }
}
