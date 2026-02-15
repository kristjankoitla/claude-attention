import AppKit

class AnimationController {
    var onFrame: ((NSImage) -> Void)?
    var onComplete: (() -> Void)?

    private var timer: Timer?
    private var step = 0
    private var wasAttention = false

    /// Run a smoothstep transition between idle and attention states, or complete immediately if unchanged.
    func animate(toAttention: Bool) {
        guard toAttention != wasAttention else {
            onComplete?()
            return
        }
        wasAttention = toAttention

        step = 0
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: Constants.animationFrameDuration, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            self.tick(toAttention: toAttention)
        }
    }

    /// Advance one animation frame: emit an interpolated icon or finish.
    private func tick(toAttention: Bool) {
        step += 1

        guard step < Constants.animationSteps else {
            timer?.invalidate()
            timer = nil
            onComplete?()
            return
        }

        let t = CGFloat(step) / CGFloat(Constants.animationSteps)
        let eased = t * t * (3 - 2 * t)
        onFrame?(IconRenderer.makeAnimationFrame(toAttention: toAttention, progress: eased))
    }
}
