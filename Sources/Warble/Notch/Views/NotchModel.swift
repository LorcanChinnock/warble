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
    /// The checks behind the "!", shared by every display's notch.
    let doctor: DoctorModel
    /// Whether the open card shows the Doctor's checks rather than the player.
    var showsDoctor = false
    /// Whether the song playing has lyrics, so the player's card offers them.
    var hasLyrics = false
    /// What dragging the art out of the player's card carries, or `nil` when Settings has it off or there's nothing.
    var artDrag: ArtDrag?
    /// What Expanded holds. `NotchSurface` sets it with `state`, inside the same animation, so a change of card morphs.
    var card = NotchCard.player
    /// Whether the notch shows what's playing, rather than Idle. While Idle, `player` may still hold the paused track.
    /// Set with `state`, like `card`.
    var isPlaying = false
    /// Whether the housing is one Warble draws on a display without a notch, where Idle shows nothing at all rather
    /// than black over the camera.
    var isVirtual = false
    /// Whether its display is set to show a notch always, so Idle draws a blank notch even on a virtual housing.
    var isAlwaysShown = false
    /// The track-change toast, while `state` is `toast`. Set with `state`, like `card`.
    var toast: TrackToast?
    /// The lyric line, while `state` is `lyrics`. Set with `state`, like `card`.
    var lyric: String?
    /// The lines around the one being sung, while the card is `lyrics`. Set with `state`, like `card`.
    var lyrics: LyricsExcerpt?
    @ObservationIgnored var onClick: () -> Void = {}
    /// Called with true when a menu from the card opens, and false when it closes, so the card stays open under it.
    @ObservationIgnored var onMenu: (Bool) -> Void = { _ in }
    /// Called to swap the open card between the player and the checks.
    @ObservationIgnored var onShowDoctor: (Bool) -> Void = { _ in }
    /// Called to swap the open card between the player and the lyrics.
    @ObservationIgnored var onShowLyrics: (Bool) -> Void = { _ in }
    /// Called with true when the art begins to be dragged out of the card, and false when the drag ends.
    @ObservationIgnored var onDragArt: (Bool) -> Void = { _ in }

    init(player: PlayerModel, doctor: DoctorModel) {
        self.player = player
        self.doctor = doctor
    }

    /// Hidden and Idle draw at the housing's size, black on black, so the wings slide out from behind it and back in.
    func size(_ state: NotchState) -> CGSize {
        NotchLayout.frame(state, notch: notch, card: card)?.size ?? notch.size
    }
}
