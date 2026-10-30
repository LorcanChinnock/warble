import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// What `NotchSurface` does to its panel to draw a notch's state: which frames the panel takes and when, and whether the
/// shape animates. The panel only grows before a morph and shrinks after it, so the shape is never clipped and the
/// panel never covers more than it has to.
public enum PanelPlan: Equatable, Sendable {
    /// What's drawn already matches, so nothing changes.
    case keep
    /// The state draws nothing. With `animated`, the wings slide back behind the housing before the panel goes.
    case hide(animated: Bool)
    case morph(Morph)

    public struct Morph: Equatable, Sendable {
        /// The frame to put the panel in with the shape drawn Hidden over the housing, so the wings slide out from behind
        /// it. `nil` when the shape already shows.
        public var opening: CGRect?
        /// The frame to grow the panel to before the shape morphs, so nothing is clipped. `nil` when it already fits.
        public var grow: CGRect?
        /// Whether the shape animates to the state. If not, the panel takes the target frame at once.
        public var animated: Bool
        /// The frame to shrink the panel to once the shape has finished, unless another change began first. `nil` when
        /// the panel already has it.
        public var settle: CGRect?
    }

    /// - Parameters:
    ///   - target: the frame the state calls for, or `nil` for a state that draws nothing.
    ///   - shown: the state and frame last drawn, or `nil` when nothing is.
    ///   - panelFrame: the frame the panel has, which stays the larger one until a morph ends.
    ///   - wasPlaying: whether the model last drew playback.
    public static func make(
        state: NotchState, target: CGRect?, isPlaying: Bool, animated: Bool,
        shown: (state: NotchState, frame: CGRect)?, panelFrame: CGRect?, wasPlaying: Bool
    ) -> PanelPlan {
        guard let target else {
            guard shown != nil else { return .keep }
            return .hide(animated: animated && panelFrame != nil)
        }
        guard shown?.state != state || shown?.frame != target || wasPlaying != isPlaying else { return .keep }
        let opening = animated && shown == nil ? panelFrame.map { $0.union(target) } ?? target : nil
        let current = opening ?? panelFrame
        guard animated, let current else {
            return .morph(Morph(opening: opening, grow: nil, animated: false, settle: nil))
        }
        let union = current.union(target)
        let grown = union != current ? union : nil
        return .morph(Morph(
            opening: opening, grow: grown, animated: true, settle: (grown ?? current) != target ? target : nil
        ))
    }
}
