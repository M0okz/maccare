import SwiftUI

/// Axe temporel fixe, calé sur le dernier relevé. La courbe se redessine seulement quand
/// un relevé arrive : un défilement image par image occuperait le CPU en continu.
struct TrayHistoryChart: View {
    let points: [TrayHistoryPoint]
    var duration: TimeInterval = TrayCPUHistory.duration
    var color: Color = .cyan
    var maximum: Double = 1
    var filled = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let end = points.last?.time ?? 0
        ZStack {
            if filled {
                TrayHistoryPlot(points: points, end: end, duration: duration, maximum: maximum, filled: true)
                    .fill(LinearGradient(colors: [color.opacity(0.25), color.opacity(0.01)], startPoint: .top, endPoint: .bottom))
            }
            TrayHistoryPlot(points: points, end: end, duration: duration, maximum: maximum)
                .stroke(color, style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round))
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.8), value: maximum)
        .clipped()
    }
}

private struct TrayHistoryPlot: Shape {
    let points: [TrayHistoryPoint]
    let end: TimeInterval
    let duration: TimeInterval
    var maximum: Double
    var filled = false
    var animatableData: Double {
        get { maximum }
        set { maximum = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let plotted = points.map {
            CGPoint(x: rect.width * ($0.time - (end - duration)) / duration,
                    y: rect.height * (1 - min(1, max(0, $0.value / max(1, maximum)))))
        }
        return Path { path in
            guard let first = plotted.first, let last = plotted.last else { return }
            if filled { path.move(to: .init(x: first.x, y: rect.height)); path.addLine(to: first) }
            else { path.move(to: first) }
            for point in plotted.dropFirst() { path.addLine(to: point) }
            if plotted.count == 1 && !filled {
                path.addEllipse(in: CGRect(x: first.x - 2, y: first.y - 2, width: 4, height: 4))
            }
            if filled { path.addLine(to: .init(x: last.x, y: rect.height)); path.closeSubpath() }
        }
    }
}
