import SwiftUI

struct MacHealthDetails: View {
    let assessment: MacHealthScore.Assessment
    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 12) {
            Text("Comprendre la santé du Mac").font(.headline).accessibilityAddTraits(.isHeader)
            if let percent = assessment.percent, let grade = assessment.grade {
                Text("\(percent) % · \(grade.rawValue)").font(.title2.weight(.semibold)).monospacedDigit()
            }
            ForEach(assessment.components) { component in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(component.title).font(.callout.weight(.medium))
                        Spacer()
                        Text("\(component.earned.formatted(.number.precision(.fractionLength(0...1)))) / \(Int(component.weight))")
                            .font(.caption).monospacedDigit()
                    }
                    Text(component.detail).font(.caption).foregroundStyle(TrayAppearance.secondary)
                }
            }
            ForEach(assessment.notes, id: \.self) { note in
                Text(note).font(.caption).foregroundStyle(TrayAppearance.secondary)
            }
            Text("Mauvais : moins de 50 % · Bien : 50 à 84 % · Excellent : 85 à 100 %")
                .font(.caption2).foregroundStyle(TrayAppearance.secondary)
            Text("Indice estimé de l’état actuel, pas un diagnostic matériel. La charge CPU instantanée et le temps depuis le démarrage ne font pas baisser la note.")
                .font(.caption2).foregroundStyle(TrayAppearance.secondary)
        }
        .padding(16)
        }
        .frame(width: 320, height: 430, alignment: .topLeading)
        .foregroundStyle(.white).background(Color(hex: "#21103D")).preferredColorScheme(.dark)
    }
}
