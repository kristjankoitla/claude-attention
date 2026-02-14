import AppKit

enum Constants {
    static let iconSize = NSSize(width: 18, height: 18)
    static let iconInset: CGFloat = 1
    static let idleInnerRatio: CGFloat = 0.35
    static let attentionInnerRatio: CGFloat = 0.65
    static let animationSteps = 40
    static let animationFrameDuration: TimeInterval = 1.0 / 60.0
    static let cleanupInterval: TimeInterval = 10.0
    static let staleThreshold: TimeInterval = 900 // 15 minutes
}

enum IconRenderer {

    static func makeIdleIcon() -> NSImage {
        let image = NSImage(size: Constants.iconSize, flipped: false) { rect in
            NSColor.black.setFill()
            sparklePath(in: rect.insetBy(dx: Constants.iconInset, dy: Constants.iconInset)).fill()
            return true
        }
        image.isTemplate = true
        return image
    }

    static func makeCountIcon(_ count: Int) -> NSImage {
        let image = NSImage(size: Constants.iconSize, flipped: false) { rect in
            let diamond = sparklePath(
                in: rect.insetBy(dx: Constants.iconInset, dy: Constants.iconInset),
                innerRatio: Constants.attentionInnerRatio)

            let str = count > 10 ? "X+" : toRoman(count)
            let fontSize: CGFloat
            switch str.count {
            case 1:    fontSize = 10
            case 2:    fontSize = 9
            case 3:    fontSize = 7.5
            default:   fontSize = 6
            }
            let font = NSFont.systemFont(ofSize: fontSize, weight: .heavy)
            let attrs: [NSAttributedString.Key: Any] = [.font: font]
            let attrStr = NSAttributedString(string: str, attributes: attrs)
            let textSize = attrStr.size()
            let textOrigin = NSPoint(
                x: (rect.width - textSize.width) / 2,
                y: (rect.height - font.capHeight) / 2
            )

            let textPath = CGMutablePath()
            let line = CTLineCreateWithAttributedString(attrStr)
            guard let runs = CTLineGetGlyphRuns(line) as? [CTRun] else { return true }
            for run in runs {
                guard let fontRef = (CTRunGetAttributes(run) as Dictionary)[kCTFontAttributeName] else { continue }
                let runFont = fontRef as! CTFont
                let glyphCount = CTRunGetGlyphCount(run)
                for i in 0..<glyphCount {
                    var glyph = CGGlyph()
                    var position = CGPoint()
                    CTRunGetGlyphs(run, CFRangeMake(i, 1), &glyph)
                    CTRunGetPositions(run, CFRangeMake(i, 1), &position)
                    if let glyphPath = CTFontCreatePathForGlyph(runFont, glyph, nil) {
                        let transform = CGAffineTransform(translationX: textOrigin.x + position.x,
                                                          y: textOrigin.y + position.y)
                        textPath.addPath(glyphPath, transform: transform)
                    }
                }
            }

            let compositePath = NSBezierPath(cgPath: textPath)
            diamond.append(compositePath)
            diamond.windingRule = .evenOdd

            NSColor.black.setFill()
            diamond.fill()

            return true
        }
        image.isTemplate = true
        return image
    }

    static func makeAnimationFrame(toAttention: Bool, progress: CGFloat) -> NSImage {
        let fromRatio = toAttention ? Constants.idleInnerRatio : Constants.attentionInnerRatio
        let toRatio = toAttention ? Constants.attentionInnerRatio : Constants.idleInnerRatio
        let currentRatio = fromRatio + (toRatio - fromRatio) * progress
        let rotation = progress * .pi

        let image = NSImage(size: Constants.iconSize, flipped: false) { rect in
            NSColor.black.setFill()
            sparklePath(in: rect.insetBy(dx: Constants.iconInset, dy: Constants.iconInset),
                        innerRatio: currentRatio, rotation: rotation).fill()
            return true
        }
        image.isTemplate = true
        return image
    }

    static func sparklePath(in rect: NSRect, innerRatio: CGFloat = Constants.idleInnerRatio, rotation: CGFloat = 0) -> NSBezierPath {
        let cx = rect.midX
        let cy = rect.midY
        let outerR = min(rect.width, rect.height) / 2
        let innerR = outerR * innerRatio

        let path = NSBezierPath()
        for i in 0..<8 {
            let angle = CGFloat(i) * .pi / 4.0 - .pi / 2.0 + rotation
            let r = (i % 2 == 0) ? outerR : innerR
            let point = NSPoint(x: cx + r * cos(angle), y: cy + r * sin(angle))
            if i == 0 {
                path.move(to: point)
            } else {
                path.line(to: point)
            }
        }
        path.close()
        return path
    }

    static func statusText(for count: Int) -> String {
        if count <= 0 {
            return "All clear"
        }
        return "\(count) session\(count == 1 ? "" : "s") need\(count == 1 ? "s" : "") attention"
    }

    static func toRoman(_ number: Int) -> String {
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
