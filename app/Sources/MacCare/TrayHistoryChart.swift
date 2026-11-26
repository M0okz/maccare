import SwiftUI

/// Les miniatures rapprochent les périodes mesurées. Le détail conserve son axe daté.
struct TrayHistoryChart: View {
    let points: [TrayHistoryPoint]
    var duration: TimeInterval = TrayCPUHistory.duration
    var color: Color = .cyan
    var maximum: Double = 1
    var filled = false
    var marksLatestPoint = false
    var endTime: TimeInterval?
    var fitsVisibleFractions = false
    enum TimeAxis { case observedTime, elapsedTime }
    var timeAxis: TimeAxis = .observedTime

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    struct Viewport {
        let points: [TrayHistoryPoint]
        let end: TimeInterval
        let duration: TimeInterval
        var fractions: [Double]? = nil

        // Use elapsed time inside each run. Interruptions share at most 12% of
        // the preview and have their own marker instead of a connecting stroke.
        static func compactFractions(_ points: [TrayHistoryPoint]) -> [Double]? {
            let pairs = zip(points, points.dropFirst())
            let breaks = points.dropFirst().lazy.filter(\.startsSegment).count
            guard breaks > 0 else { return nil }
            let observed = pairs.reduce(0.0) { sum, pair in
                sum + (pair.1.startsSegment ? 0 : pair.1.time - pair.0.time)
            }
            guard observed > 0 else {
                return points.indices.map { Double($0) / Double(points.count - 1) }
            }
            let gapWidth = min(0.01, 0.12 / Double(breaks))
            let scale = (1 - Double(breaks) * gapWidth) / observed
            var positions = [0.0]
            var x = 0.0
            for (before, after) in pairs {
                x += after.startsSegment ? gapWidth : (after.time - before.time) * scale
                positions.append(x)
            }
            return positions
        }
    }

    var viewport: Viewport {
        let end = endTime ?? points.last?.time ?? 0
        let window = TrayMetricHistory.window(points, duration: duration, end: end)
        switch timeAxis {
        case .elapsedTime:
            return Viewport(points: window, end: end, duration: duration)
        case .observedTime:
            guard let last = window.last, end - last.time <= TrayHistoryPoint.maximumGap else {
                return Viewport(points: [], end: end, duration: duration)
            }
            let visible = Self.clipLeadingSegment(window, at: end - duration)
            let span = last.time - (visible.first?.time ?? last.time)
            return Viewport(points: visible, end: last.time,
                            duration: span > 0 ? span : TrayMetricHistory.bucketDuration,
                            fractions: Viewport.compactFractions(visible))
        }
    }

    var body: some View {
        let viewport = viewport
        let end = viewport.end
        let duration = viewport.duration
        let visible = viewport.points
        let range = fitsVisibleFractions ? Self.fractionRange(visible) : 0...max(1, maximum)
        let plot = TrayHistoryPlot(points: visible, end: end, duration: duration,
                                   maximum: range.upperBound, minimum: range.lowerBound, fractions: viewport.fractions)
        ZStack {
            if visible.isEmpty, timeAxis == .observedTime {
                ViewThatFits(in: .horizontal) {
                    Text("Aucun relevé récent").font(.caption2).fixedSize()
                    Image(systemName: "ellipsis")
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if filled {
                TrayHistoryPlot(points: visible, end: end, duration: duration, maximum: range.upperBound,
                                minimum: range.lowerBound, filled: true, fractions: viewport.fractions)
                    .fill(LinearGradient(colors: [color.opacity(0.25), color.opacity(0.01)], startPoint: .top, endPoint: .bottom))
            }
            if let fractions = viewport.fractions {
                Canvas { context, size in
                    var markers = Path()
                    for i in visible.indices.dropFirst() where visible[i].startsSegment {
                        let x = (fractions[i - 1] + fractions[i]) / 2 * size.width
                        markers.move(to: CGPoint(x: x, y: 0))
                        markers.addLine(to: CGPoint(x: x, y: size.height))
                    }
                    context.stroke(markers, with: .color(.secondary.opacity(0.7)), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                }.accessibilityHidden(true)
            }
            plot
                .stroke(color, style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round))
            if marksLatestPoint, let last = visible.last, last.time >= end - duration {
                GeometryReader { geometry in
                    let bounds = CGRect(origin: .zero, size: geometry.size)
                    let point = plot.position(at: visible.count - 1, in: bounds)
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
    var fractions: [Double]? = nil
    var animatableData: Double {
        get { maximum }
        set { maximum = newValue }
    }

    func position(at index: Int, in rect: CGRect) -> CGPoint {
        let sample = points[index]
        let x = fractions?[index] ?? ((sample.time - (end - duration)) / duration)
        let fraction = (sample.value - minimum) / (maximum - minimum)
        return CGPoint(x: rect.width * x,
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
            for (i, sample) in points.enumerated() {
                let point = position(at: i, in: rect)
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
