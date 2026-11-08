import Foundation

enum BubbleHitTest {
    static func path(at point: CGPoint, in bubbles: [PackedBubble]) -> String? {
        bubbles.reversed().first {
            hypot(point.x - $0.center.x, point.y - $0.center.y) <= $0.radius
        }?.id
    }
}
