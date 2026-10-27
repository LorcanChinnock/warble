import AppKit
import Carbon.HIToolbox
import SwiftUI
import WarbleCore

/// What one notch panel draws. `NotchController` changes `state` inside an animation, and the view morphs to it.
@MainActor
@Observable
final class NotchModel {
    var state = NotchState.hidden
    /// The camera housing, real or virtual, which every state's shape is measured from.
    var notch = CGRect.zero
    /// What's playing, shared by every display's notch.
    let player: PlayerModel
    /// Whether the notch shows what's playing, rather than Idle. While Idle, `player` may still hold the paused track.
    /// Set with `state`.
    var isPlaying = false
    /// Whether the resting notch draws the title between the art and the bars.
    var showsTitle = false
    /// How big the open card is.
    var cardSize = CardSize.standard
    @ObservationIgnored var onClick: () -> Void = {}
    /// Called with true when a menu from the card opens, and false when it closes, so the card stays open under it.
    @ObservationIgnored var onMenu: (Bool) -> Void = { _ in }

    init(player: PlayerModel) {
        self.player = player
    }

    /// Hidden draws at the housing's size, black on black, so the wings slide out from behind it and back in.
    func size(_ state: NotchState) -> CGSize {
        NotchLayout.frame(state, notch: notch, cardSize: cardSize)?.size ?? notch.size
    }
}
