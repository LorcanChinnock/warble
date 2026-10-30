import AppKit
import SwiftUI
import WarbleCore

/// `Glow`'s two pools, each wandering a few points on its own slow loop while a song plays, and settling back into the
/// corners when it pauses. Core Animation runs them in the window server, so the app does no work per frame; the card
/// is only in the view while open, so nothing runs while it's closed.
struct DriftGlow: NSViewRepresentable {
    let colours: ArtworkColours
    let isPlaying: Bool

    func makeNSView(context: Context) -> DriftView {
        DriftView()
    }

    func updateNSView(_ view: DriftView, context: Context) {
        view.tint(colours)
        view.drift(isPlaying)
    }

    final class DriftView: NSView {
        /// How far each pool wanders and scales, as fractions of the card, and the length of each loop's one way. The
        /// durations differ per axis and per pool so the pools never fall into step.
        private struct Wander {
            let dx: CGFloat
            let dy: CGFloat
            let scale: CGFloat
            let durations: (x: Double, y: Double, scale: Double)
        }

        private static let leading = Wander(dx: 0.22, dy: 0.08, scale: 1.1, durations: (14, 10, 12))
        private static let trailing = Wander(dx: -0.22, dy: 0.08, scale: 1.1, durations: (17, 12, 15))
        private static let settle = 1.0

        private let leadingPool = CAGradientLayer()
        private let trailingPool = CAGradientLayer()
        private var drifting = false
        private var drawn = false
        private var laidOut = CGSize.zero

        init() {
            super.init(frame: .zero)
            wantsLayer = true
            layer?.masksToBounds = true
            for pool in [leadingPool, trailingPool] {
                pool.type = .radial
                layer?.addSublayer(pool)
            }
            // Each pool is twice the card's size about its corner, so its own edge is never in view as it wanders, and
            // fades out at the reach (`glowReach` of the card) well inside it.
            for pool in [leadingPool, trailingPool] {
                pool.startPoint = CGPoint(x: 0.5, y: 0.5)
                pool.endPoint = CGPoint(x: 0.5 + Native.glowReach / 2, y: 0.5 + Native.glowReach / 2)
            }
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func layout() {
            super.layout()
            // A layout pass at the same size would restart the loops, which jumps the pools.
            guard bounds.size != laidOut else { return }
            laidOut = bounds.size
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            // The layer's origin is the bottom left, so each pool is centred on a bottom corner.
            for (pool, corner) in [(leadingPool, CGFloat(0)), (trailingPool, 1)] {
                pool.bounds = CGRect(x: 0, y: 0, width: bounds.width * 2, height: bounds.height * 2)
                pool.position = CGPoint(x: corner * bounds.width, y: 0)
            }
            CATransaction.commit()
            if drifting { addDrift() }
        }

        /// Colours the pools, fading from the last colours so a new track doesn't flash.
        func tint(_ colours: ArtworkColours) {
            CATransaction.begin()
            if drawn {
                CATransaction.setAnimationDuration(Native.glowChangeDuration)
            } else {
                CATransaction.setDisableActions(true)
            }
            leadingPool.colors = Self.fade(colours.first)
            trailingPool.colors = Self.fade(colours.second)
            CATransaction.commit()
            drawn = true
        }

        /// Starts the drift while a song plays; on a pause, eases the pools back to their corners.
        func drift(_ playing: Bool) {
            guard playing != drifting else { return }
            drifting = playing
            if playing {
                addDrift()
            } else {
                for pool in [leadingPool, trailingPool] { settle(pool) }
            }
        }

        private static func fade(_ colour: ArtworkColours.RGB) -> [CGColor] {
            let base = NSColor(srgbRed: colour.red, green: colour.green, blue: colour.blue, alpha: Native.glowOpacity)
            return [base.cgColor, base.withAlphaComponent(0).cgColor]
        }

        private func addDrift() {
            guard bounds.width > 0 else { return }
            for (pool, wander) in [(leadingPool, Self.leading), (trailingPool, Self.trailing)] {
                pool.add(Self.loop("position.x", from: 0, to: wander.dx * bounds.width, duration: wander.durations.x, additive: true), forKey: "x")
                pool.add(Self.loop("position.y", from: 0, to: wander.dy * bounds.height, duration: wander.durations.y, additive: true), forKey: "y")
                pool.add(Self.breathe(to: wander.scale, duration: wander.durations.scale), forKey: "scale")
            }
        }

        /// A there-and-back loop that eases at each end, so the motion never kinks. 20 frames a second, the bars' rate:
        /// each frame costs the window server a redraw of the notch, and the pools move too slowly to need more.
        private static func loop(_ keyPath: String, from: CGFloat, to: CGFloat, duration: Double, additive: Bool) -> CABasicAnimation {
            let animation = CABasicAnimation(keyPath: keyPath)
            animation.fromValue = from
            animation.toValue = to
            animation.duration = duration
            animation.autoreverses = true
            animation.repeatCount = .infinity
            animation.isAdditive = additive
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animation.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 20, preferred: 20)
            return animation
        }

        /// A scale loop that starts and ends at the resting scale of 1, swelling to `to` and shrinking to its mirror, so
        /// starting it never jumps the pool. It's additive, like the position loops, so it rides on a settle still under
        /// way instead of overriding it. `duration` is each way, as in `loop`.
        private static func breathe(to: CGFloat, duration: Double) -> CAKeyframeAnimation {
            let animation = CAKeyframeAnimation(keyPath: "transform.scale")
            animation.values = [0, to - 1, 0, 1 - to, 0]
            animation.isAdditive = true
            animation.calculationMode = .cubic
            animation.duration = duration * 4
            animation.repeatCount = .infinity
            animation.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 20, preferred: 20)
            return animation
        }

        /// Removes the drift and eases from where the pool is to its corner, rather than snapping.
        private func settle(_ pool: CAGradientLayer) {
            let position = pool.presentation()?.position ?? pool.position
            let scale = pool.presentation()?.value(forKeyPath: "transform.scale") as? CGFloat ?? 1
            // Only the drift's own, so a colour fade under way carries on.
            for key in ["x", "y", "scale"] { pool.removeAnimation(forKey: key) }
            for (keyPath, from, to) in [("position.x", position.x, pool.position.x), ("position.y", position.y, pool.position.y), ("transform.scale", scale, 1)] {
                let animation = CABasicAnimation(keyPath: keyPath)
                animation.fromValue = from
                animation.toValue = to
                animation.duration = Self.settle
                animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                pool.add(animation, forKey: "settle." + keyPath)
            }
        }
    }
}
