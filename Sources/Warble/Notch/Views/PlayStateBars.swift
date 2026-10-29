import AppKit
import Carbon.HIToolbox
import SwiftUI
import WarbleCore
import WarbleModel

/// Five thin bars, like iOS's now-playing waveform, that swell and shrink around a centre line while something plays and
/// settle into a row of dots when it pauses. They follow the play state, not the audio. Core Animation runs them in the window server, so the app does no work per frame. They rise one after another
/// as the wings slide out, and drop as the content leaves; once the content is gone, so are their animations. With
/// Reduce Motion they stand still and show at once.
struct PlayStateBars: NSViewRepresentable {
    let isPlaying: Bool
    /// Whether the content around them is in, rather than coming or going.
    let isShown: Bool
    let reduceMotion: Bool
    /// The artwork's colour, or white without one.
    var colour: NSColor = .white

    func makeNSView(context: Context) -> BarsView {
        BarsView()
    }

    func updateNSView(_ view: BarsView, context: Context) {
        view.tint(colour)
        view.show(isPlaying ? (reduceMotion ? .still : .moving) : .settled, shown: isShown, animated: !reduceMotion)
    }

    final class BarsView: NSView {
        enum Look { case settled, still, moving }

        /// Each bar's heights, as fractions of the view's, which it loops through. Different lengths keep the bars from
        /// falling into step.
        private static let heights: [[CGFloat]] = [
            [0.4, 0.85, 0.5, 1, 0.45],
            [0.75, 0.4, 1, 0.55],
            [1, 0.5, 0.9, 0.35, 0.8, 0.6],
            [0.7, 1, 0.4, 0.85],
            [0.35, 0.7, 0.45, 0.95, 0.5],
        ]
        /// A paused bar, a rounded dot.
        private static let settled: CGFloat = 2
        private static let barWidth: CGFloat = 2
        /// The curve each bar rises on, the same as the resting art's (`Native.artIn`).
        private static let rise = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1)
        private let bars = heights.map { _ in CALayer() }
        private var look = Look.settled
        private var shown = false
        /// Whether the bars have been drawn yet. They're drawn hidden first, so they rise once they're shown.
        private var drawn = false
        /// When the bars started to rise, while they may still be rising, so a layout mid-rise carries on from there.
        private var riseBegan: CFTimeInterval?

        init() {
            super.init(frame: .zero)
            wantsLayer = true
            for bar in bars {
                bar.backgroundColor = NSColor.white.cgColor
                bar.cornerRadius = Self.barWidth / 2
                // Grows out from the centre line, up and down together.
                bar.anchorPoint = CGPoint(x: 0.5, y: 0.5)
                layer?.addSublayer(bar)
            }
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            let gap = (bounds.width - CGFloat(bars.count) * Self.barWidth) / CGFloat(bars.count - 1)
            for (index, bar) in bars.enumerated() {
                bar.position = CGPoint(x: CGFloat(index) * (Self.barWidth + gap) + Self.barWidth / 2, y: bounds.midY)
                bar.bounds.size = CGSize(width: Self.barWidth, height: height(of: index))
            }
            CATransaction.commit()
            animate()
        }

        /// Colours the bars, fading from the last colour so a new track doesn't flash.
        func tint(_ colour: NSColor) {
            let cgColour = colour.cgColor
            guard bars.first?.backgroundColor != cgColour else { return }
            CATransaction.begin()
            CATransaction.setAnimationDuration(Native.glowChangeDuration)
            for bar in bars { bar.backgroundColor = cgColour }
            CATransaction.commit()
        }

        /// Shows `look`, with the bars up when `shown` and gone when not. `animated` staggers their rise and eases their
        /// drop; a change of look always eases.
        func show(_ look: Look, shown: Bool, animated: Bool) {
            defer { drawn = true }
            guard look != self.look || shown != self.shown else { return }
            let animated = animated && drawn
            let rises = shown && !self.shown
            let drops = !shown && self.shown
            self.look = look
            self.shown = shown
            riseBegan = rises && animated ? CACurrentMediaTime() : nil
            // Hold each bar where it is before its animations go, so it moves on from there rather than jumping.
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for bar in bars {
                if let height = bar.presentation()?.bounds.height { bar.bounds.size.height = height }
                bar.removeAllAnimations()
            }
            CATransaction.commit()
            CATransaction.begin()
            if rises || (drops && !animated) {
                // A rise is animate()'s; it starts from nothing.
                CATransaction.setDisableActions(true)
            } else if drops {
                CATransaction.setAnimationDuration(NotchMotion.barDrop)
                CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeIn))
            } else {
                CATransaction.setAnimationDuration(0.25)
            }
            for (index, bar) in bars.enumerated() {
                bar.bounds.size.height = height(of: index)
            }
            CATransaction.commit()
            animate()
        }

        private func height(of index: Int) -> CGFloat {
            guard shown else { return 0 }
            return switch look {
            case .settled, .moving: Self.settled
            case .still: Self.heights[index][0] * bounds.height
            }
        }

        /// Adds each bar's rise while it's due or under way, then, while playing, its loop from where the rise ends.
        private func animate() {
            guard shown, bounds.height > 0 else { return }
            let now = CACurrentMediaTime()
            if let riseBegan, riseBegan + NotchMotion.barsRisen(count: bars.count) <= now {
                self.riseBegan = nil
            }
            for (index, bar) in bars.enumerated() {
                let loop = Self.heights[index].map { max($0 * bounds.height, Self.settled) }
                var loopBegins: CFTimeInterval = 0
                if let riseBegan {
                    let begins = riseBegan + NotchMotion.barDelay(index)
                    let rise = CABasicAnimation(keyPath: "bounds.size.height")
                    rise.fromValue = 0
                    rise.toValue = look == .moving ? loop[0] : height(of: index)
                    rise.beginTime = begins
                    rise.duration = NotchMotion.barRise
                    rise.timingFunction = Self.rise
                    // Nothing before its turn, and its top after, until the loop takes over.
                    rise.fillMode = .both
                    rise.isRemovedOnCompletion = false
                    bar.add(rise, forKey: "rise")
                    loopBegins = begins + NotchMotion.barRise
                } else {
                    bar.removeAnimation(forKey: "rise")
                }
                guard look == .moving else { continue }
                let animation = CAKeyframeAnimation(keyPath: "bounds.size.height")
                animation.values = loop + [loop[0]]
                animation.calculationMode = .cubic
                animation.beginTime = loopBegins
                // 20 frames a second, the scrolling title's rate, reads as motion rather than steps, where 8
                // looked choppy. Each frame costs the window server a redraw of the notch: about 1.7% of a core at 8,
                // against about 21% at the display's rate.
                animation.duration = Double(loop.count) * 0.35
                animation.repeatCount = .infinity
                animation.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 20, preferred: 20)
                bar.add(animation, forKey: "height")
            }
        }
    }
}
