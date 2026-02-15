import AppKit

/// CoreText utility that converts text into a CGPath of glyph outlines.
enum GlyphPath {

    /// Convert an attributed string to glyph outlines, centered within the given rect.
    static func outlines(for text: NSAttributedString, centeredIn rect: NSRect) -> CGPath {
        let font = text.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        let origin = NSPoint(
            x: (rect.width - text.size().width) / 2,
            y: (rect.height - (font?.capHeight ?? 0)) / 2
        )

        let path = CGMutablePath()
        let line = CTLineCreateWithAttributedString(text)
        for run in (CTLineGetGlyphRuns(line) as? [CTRun]) ?? [] {
            // CTFont is a CoreFoundation type — this cast always succeeds
            let runFont = (CTRunGetAttributes(run) as Dictionary)[kCTFontAttributeName] as! CTFont
            for i in 0..<CTRunGetGlyphCount(run) {
                var glyph = CGGlyph()
                var position = CGPoint()
                CTRunGetGlyphs(run, CFRangeMake(i, 1), &glyph)
                CTRunGetPositions(run, CFRangeMake(i, 1), &position)
                if let glyphPath = CTFontCreatePathForGlyph(runFont, glyph, nil) {
                    let transform = CGAffineTransform(
                        translationX: origin.x + position.x, y: origin.y + position.y)
                    path.addPath(glyphPath, transform: transform)
                }
            }
        }
        return path
    }
}
