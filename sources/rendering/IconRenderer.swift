import AppKit

/// Composes sparkle shapes and glyph outlines into menu bar icons.
enum IconRenderer {

    /// Render the idle sparkle icon (thin points, no text).
    static func makeIdleIcon() -> NSImage {
        makeTemplateIcon { rect in
            NSColor.black.setFill()
            SparkleShape.path(in: rect.insetBy(dx: Constants.iconInset, dy: Constants.iconInset)).fill()
        }
    }

    /// Render the attention sparkle with a Roman numeral count cut out of the center.
    static func makeCountIcon(_ count: Int) -> NSImage {
        makeTemplateIcon { rect in
            let inset = rect.insetBy(dx: Constants.iconInset, dy: Constants.iconInset)
            let diamond = SparkleShape.path(in: inset, innerRatio: Constants.attentionInnerRatio)
            let label = countLabel(count)
            let cutout = GlyphPath.outlines(for: label, centeredIn: rect)

            diamond.append(NSBezierPath(cgPath: cutout))
            diamond.windingRule = .evenOdd

            NSColor.black.setFill()
            diamond.fill()
        }
    }

    /// Render a single animation frame interpolating between idle and attention shapes.
    static func makeAnimationFrame(toAttention: Bool, progress: CGFloat) -> NSImage {
        let fromRatio = toAttention ? Constants.idleInnerRatio : Constants.attentionInnerRatio
        let toRatio = toAttention ? Constants.attentionInnerRatio : Constants.idleInnerRatio
        let currentRatio = fromRatio + (toRatio - fromRatio) * progress
        let rotation = progress * .pi

        return makeTemplateIcon { rect in
            NSColor.black.setFill()
            SparkleShape.path(in: rect.insetBy(dx: Constants.iconInset, dy: Constants.iconInset),
                              innerRatio: currentRatio, rotation: rotation).fill()
        }
    }

    /// Return a human-readable status string like "2 sessions need attention" or "All clear".
    static func statusText(for count: Int) -> String {
        if count <= 0 {
            return "All clear"
        }
        return "\(count) session\(count == 1 ? "" : "s") need\(count == 1 ? "s" : "") attention"
    }

    // MARK: - Private

    /// Create an 18x18 template NSImage, handling the boilerplate that every icon shares.
    private static func makeTemplateIcon(_ draw: @escaping (NSRect) -> Void) -> NSImage {
        let image = NSImage(size: Constants.iconSize, flipped: false) { rect in
            draw(rect)
            return true
        }
        image.isTemplate = true
        return image
    }

    /// Build an attributed string for the count label, sized to fit the icon.
    private static func countLabel(_ count: Int) -> NSAttributedString {
        let text = count > 10 ? "X+" : toRoman(count)
        let fontSize: CGFloat
        switch text.count {
        case 1:    fontSize = 10
        case 2:    fontSize = 9
        case 3:    fontSize = 7.5
        default:   fontSize = 6
        }
        let font = NSFont.systemFont(ofSize: fontSize, weight: .heavy)
        return NSAttributedString(string: text, attributes: [.font: font])
    }

    /// Convert an integer to its Roman numeral representation.
    private static func toRoman(_ number: Int) -> String {
        let values = [(1000,"M"),(900,"CM"),(500,"D"),(400,"CD"),
                      (100,"C"),(90,"XC"),(50,"L"),(40,"XL"),
                      (10,"X"),(9,"IX"),(5,"V"),(4,"IV"),(1,"I")]
        var result = ""
        var n = number
        for (value, numeral) in values {
            while n >= value {
                result += numeral
                n -= value
            }
        }
        return result
    }
}
