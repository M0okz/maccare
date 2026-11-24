import SwiftUI

/// Axe temporel fixe, calé sur le dernier relevé. La courbe se redessine seulement quand
/// un relevé arrive : un défilement image par image occuperait le CPU en continu.
struct TrayHistoryChart: View {
    let points: [TrayHistoryPoint]
    var duration: TimeInterval = TrayCPUHistory.duration
    var color: Color = .cyan
    var maximum: Double = 1
    var filled = false
    var marksLatestPoint = false
    var endTime: TimeInterval?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let end = endTime ?? points.last?.time ?? 0
        let visible = TrayMetricHistory.window(points, duration: duration, end: end)
        ZStack {
            if filled {
                TrayHistoryPlot(points: visible, end: end, duration: duration, maximum: maximum, filled: true)
                    .fill(LinearGradient(colors: [color.opacity(0.25), color.opacity(0.01)], startPoint: .top, endPoint: .bottom))
            }
            TrayHistoryPlot(points: visible, end: end, duration: duration, maximum: maximum)
                .stroke(color, style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round))
            if marksLatestPoint, let last = visible.last, last.time >= end - duration {
                GeometryReader { geometry in
                    let bounds = CGRect(origin: .zero, size: geometry.size)
                    let point = TrayHistoryPlot.position(of: last, in: bounds, end: end, duration: duration, maximum: maximum)
                    Circle().fill(color).frame(width: 4, height: 4)
                        .position(x: min(max(2, point.x), max(2, bounds.width - 2)),
                                  y: min(max(2, point.y), max(2, bounds.height - 2)))
                }
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.8), value: maximum)
        .clipped()
    }
}

struct TrayHistoryPlot: Shape {
    let points: [TrayHistoryPoint]
    let end: TimeInterval
    let duration: TimeInterval
    var maximum: Double
    var filled = false
    var animatableData: Double {
        get { maximum }
        set { maximum = newValue }
    }

    static func position(of sample: TrayHistoryPoint, in rect: CGRect, end: TimeInterval,
                         duration: TimeInterval, maximum: Double) -> CGPoint {
        CGPoint(x: rect.width * (sample.time - (end - duration)) / duration,
                y: rect.height * (1 - min(1, max(0, sample.value / max(1, maximum)))))
    }

    func path(in rect: CGRect) -> Path {
        return Path { path in
            var last: CGPoint?
            var count = 0
            func finishSegment() {
                guard let last else { return }
                if filled {
                    path.addLine(to: .init(x: last.x, y: rect.height))
                    path.closeSubpath()
                } else if count == 1 {
                    path.addEllipse(in: CGRect(x: last.x - 2, y: last.y - 2, width: 4, height: 4))
                }
            }
            for sample in points {
                let point = Self.position(of: sample, in: rect, end: end, duration: duration, maximum: maximum)
                if last == nil {
                    if filled { path.move(to: .init(x: point.x, y: rect.height)); path.addLine(to: point) }
                    else { path.move(to: point) }
                } else { path.addLine(to: point) }
                last = point
                count += 1
            }
            finishSegment()
        }
    }
}
