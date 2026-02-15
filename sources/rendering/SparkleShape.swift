import AppKit

/// Pure geometry for the 4-point sparkle/star shape.
enum SparkleShape {

    /// Build an 8-vertex star path with alternating outer/inner radii, optionally rotated.
    static func path(in rect: NSRect, innerRatio: CGFloat = Constants.idleInnerRatio, rotation: CGFloat = 0) -> NSBezierPath {
        let cx = rect.midX
        let cy = rect.midY
        let outerR = min(rect.width, rect.height) / 2
        let innerR = outerR * innerRatio

        let bezier = NSBezierPath()
        for i in 0..<8 {
            let angle = CGFloat(i) * .pi / 4.0 - .pi / 2.0 + rotation
            let r = (i % 2 == 0) ? outerR : innerR
            let point = NSPoint(x: cx + r * cos(angle), y: cy + r * sin(angle))
            if i == 0 {
                bezier.move(to: point)
            } else {
                bezier.line(to: point)
            }
        }
        bezier.close()
        return bezier
    }
}
