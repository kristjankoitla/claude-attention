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
