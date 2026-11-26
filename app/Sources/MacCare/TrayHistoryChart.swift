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
    var fitsVisibleFractions = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let end = endTime ?? points.last?.time ?? 0
        let window = TrayMetricHistory.window(points, duration: duration, end: end)
        let visible = fitsVisibleFractions ? Self.clipLeadingSegment(window, at: end - duration) : window
        let range = fitsVisibleFractions ? Self.fractionRange(visible) : 0...max(1, maximum)
        let plot = TrayHistoryPlot(points: visible, end: end, duration: duration,
                                   maximum: range.upperBound, minimum: range.lowerBound)
        ZStack {
            if filled {
                TrayHistoryPlot(points: visible, end: end, duration: duration, maximum: range.upperBound,
                                minimum: range.lowerBound, filled: true)
                    .fill(LinearGradient(colors: [color.opacity(0.25), color.opacity(0.01)], startPoint: .top, endPoint: .bottom))
            }
            plot
                .stroke(color, style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round))
            if marksLatestPoint, let last = visible.last, last.time >= end - duration {
                GeometryReader { geometry in
                    let bounds = CGRect(origin: .zero, size: geometry.size)
                    let point = plot.position(of: last, in: bounds)
                    Circle().fill(color).frame(width: 4, height: 4)
                        .position(x: min(max(2, point.x), max(2, bounds.width - 2)),
                                  y: min(max(2, point.y), max(2, bounds.height - 2)))
                }
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.8), value: maximum)
        .clipped()
    }

    /// Include the line's intersection with the left edge, but not an older, off-screen peak.
    static func clipLeadingSegment(_ window: [TrayHistoryPoint], at start: TimeInterval) -> [TrayHistoryPoint] {
        guard let first = window.first, first.time < start else { return window }
        guard window.count > 1 else { return [] }
        let next = window[1]
        if next.startsSegment || next.time == start { return Array(window.dropFirst()) }
        let edge = first.value + (next.value - first.value) * (start - first.time) / (next.time - first.time)
        var clipped = window
        clipped[0] = TrayHistoryPoint(time: start, value: edge)
        return clipped
    }

    static func fractionRange(_ visible: [TrayHistoryPoint]) -> ClosedRange<Double> {
        let values = visible.map(\.value)
        guard let low = values.min(), let high = values.max() else { return 0...1 }
        // Five percentage points minimum; whole-percent bounds keep a quiet trace steady.
        let span = min(1, max(0.05, (high - low) * 1.2))
        let lower = max(0, min(1 - span, (low + high - span) / 2))
        let upper = min(1, ceil((lower + span) * 100) / 100)
        return (floor(lower * 100) / 100)...upper
    }
}

struct TrayHistoryPlot: Shape {
    let points: [TrayHistoryPoint]
    let end: TimeInterval
    let duration: TimeInterval
    var maximum: Double
    var minimum: Double = 0
    var filled = false
    var animatableData: Double {
        get { maximum }
        set { maximum = newValue }
    }

    func position(of sample: TrayHistoryPoint, in rect: CGRect) -> CGPoint {
        let fraction = (sample.value - minimum) / (maximum - minimum)
        return CGPoint(x: rect.width * (sample.time - (end - duration)) / duration,
                       y: rect.height * (1 - min(1, max(0, fraction))))
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
                let point = position(of: sample, in: rect)
                if sample.startsSegment, last != nil {
                    finishSegment()
                    last = nil
                    count = 0
                }
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
