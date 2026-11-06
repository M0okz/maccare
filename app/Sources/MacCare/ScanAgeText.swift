import SwiftUI

/// Temps écoulé depuis la dernière analyse, actualisé chaque minute. Un texte de style
/// `.relative` compte les secondes : il relancerait la mise en page de l’accueil chaque
/// seconde, même fenêtre masquée.
struct ScanAgeText: View {
    let date: Date

    var body: some View {
        TimelineView(.periodic(from: date, by: 60)) { context in
            Text(Self.label(since: date, now: context.date))
        }
    }

    static func label(since date: Date, now: Date) -> String {
        let elapsed = now.timeIntervalSince(date)
        guard elapsed >= 60 else { return "moins d’une minute" }
        return formatter.string(from: elapsed) ?? ""
    }

    private static let formatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.maximumUnitCount = 2
        formatter.unitsStyle = .short
        return formatter
    }()
}
