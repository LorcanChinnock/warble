import AppKit
import os
import SwiftUI
import WarbleCore

private let log = Logger.warble("notch")

/// One display's notch: its panel over a camera housing, real or virtual, and the `HoverIntent` that opens it.
/// `NotchController` keeps one for each housing and shares what's playing between them.
@MainActor
final class NotchSurface {
    /// The camera housing the panel is drawn over.
    var housing: CGRect
    /// Whether the housing is one Warble draws on a display without a notch.
    var isVirtual: Bool {
        get { model.isVirtual }
        set { model.isVirtual = newValue }
    }
    /// Whether a blank notch stays drawn over the housing while nothing is playing.
    var isAlwaysShown = false {
        didSet {
            model.isAlwaysShown = isAlwaysShown
            shownChanged()
        }
    }
    /// Whether anything is playing, rather than Idle.
    var isPlaying = false {
        didSet { shownChanged() }
    }
    /// Whether a Doctor check failed, which draws the notch with a "!" even when nothing is playing.
    var needsAttention = false {
        didSet { shownChanged() }
    }
    /// What a hover on the housing does while Idle.
    var idleHover = IdleHover.lastPlayed {
        didSet { shownChanged() }
    }
    /// The track-change toast showing, which a resting notch draws below its wings.
    var toast: TrackToast?
    /// Without anything playing, a "!" or a card to open while Idle, the surface draws nothing, or only a blank notch,
    /// and takes no hover or click.
    private var answersPointer: Bool { state != .hidden && !(state == .idle && idleHover == .nothing) }
    private var answeredPointer = false
    /// Called after the surface opens or closes, or the pointer crosses it, so the controller can listen for clicks
    /// elsewhere and Escape only while a notch is open.
    var onChange: () -> Void = {}
    /// Called when the surface is clicked, before it opens.
    var onClick: () -> Void = {}
    /// Builds the menu a right-click opens, when it opens.
    var makeMenu: () -> NSMenu? = { nil }
    /// Called with each key the open notch's controls didn't use while it has the keyboard; true when it did something.
    var onKey: (NSEvent) -> Bool = { _ in false }

    var state: NotchState {
        NotchState(hover.state, isPlaying: isPlaying, needsAttention: needsAttention, idleHover: idleHover, isAlwaysShown: isAlwaysShown, showsToast: toast != nil)
    }
    /// What Expanded holds, which the panel morphs to on the next `update`.
    var card: NotchCard {
        NotchCard(isPlaying: isPlaying && model.player.playback != nil, needsAttention: needsAttention, showsDoctor: model.showsDoctor)
    }
    private(set) var pointerInside = false
    /// The app in front when the shortcut opened the notch, which gets the keyboard back when it closes.
    private var keyboardFrom: NSRunningApplication?
    /// Warble's own window that had the keyboard, such as Settings, when the shortcut opened the notch.
    private var keyWindowBefore: NSWindow?
    /// Whether a menu from this notch is open, which takes Escape for itself.
    private(set) var isShowingMenu = false

    private let model: NotchModel
    private let panel: NotchPanel
    private var hover = HoverIntent()
    private var deadlineTimer: Timer?
    /// The state and frame last shown, and the frame the panel has, which stays the larger one until a morph ends.
    private var shown: (state: NotchState, frame: CGRect)?
    private var panelFrame: CGRect?
    /// Bumped by every change, so a morph that ends after another has begun doesn't shrink the panel under it.
    private var morphs = 0

    init(housing: CGRect, player: PlayerModel, doctor: DoctorModel, onScroll: @escaping (NSEvent) -> Void) {
        self.housing = housing
        model = NotchModel(player: player, doctor: doctor)
        panel = NotchPanel(model: model)
        panel.onPointer = { [weak self] inside in self?.pointer(inside: inside) }
        panel.onScroll = onScroll
        panel.onMenu = { [weak self] event in self?.showMenu(for: event) }
        model.onClick = { [weak self] in
            self?.onClick()
            self?.handle(.click)
        }
        model.onMenu = { [weak self] open in self?.menu(open: open) }
        model.onShowDoctor = { [weak self] show in self?.showDoctor(show) }
        panel.onKey = { [weak self] event in self?.onKey(event) ?? false }
    }

    /// Opens the notch with the keyboard in it, so VoiceOver and Keyboard navigation start there, or closes it. It
    /// stays open wherever the pointer goes, until the shortcut again, Esc or a click elsewhere. Warble comes to the
    /// front meanwhile, since VoiceOver and Tab only follow the app in front, and has no menu bar of its own to show.
    func toggleKeyboard() {
        let opening = state != .expanded
        handle(.keyboard)
        guard opening, state == .expanded else { return }
        if NSApp.isActive {
            keyWindowBefore = NSApp.keyWindow
        } else {
            keyboardFrom = NSWorkspace.shared.frontmostApplication
        }
        panel.takesKeyboard = true
        NSApp.activate()
        panel.makeKey()
        // The SwiftUI view, one level inside the content view, so Tab moves through its buttons.
        panel.makeFirstResponder(panel.contentView?.subviews.first)
    }

    /// Gives the keyboard back once the notch closes, unless a click has already moved it on: to the app that had it,
    /// or, when Warble was already in front, to its window that had it, or else to whichever app is next.
    private func releaseKeyboard() {
        guard panel.takesKeyboard else { return }
        panel.takesKeyboard = false
        if NSApp.isActive, panel.isKeyWindow {
            if let keyboardFrom {
                keyboardFrom.activate()
            } else if let keyWindowBefore, keyWindowBefore.isVisible {
                keyWindowBefore.makeKey()
            } else {
                NSApp.deactivate()
            }
        }
        keyboardFrom = nil
        keyWindowBefore = nil
    }

    private func shownChanged() {
        defer { answeredPointer = answersPointer }
        guard !answersPointer, answeredPointer else { return }
        // Start over, so a pointer still on the notch when it's drawn again is reported as entering again.
        hover = HoverIntent()
        pointerInside = false
        scheduleDeadline()
    }

    /// Swaps the open card between the player and the Doctor's checks. From the resting "!", the click that follows
    /// opens the notch on the checks. The controller hears of the change, since only the player's card follows the volume.
    private func showDoctor(_ show: Bool) {
        model.showsDoctor = show
        if state == .expanded {
            update()
            onChange()
        }
    }

    func handle(_ event: HoverEvent) {
        // A blank notch that doesn't open keeps no hover, so playback starting under the pointer doesn't open it.
        guard answersPointer else { return }
        hover.handle(event, at: .now)
        scheduleDeadline()
        update()
        onChange()
    }

    /// Takes the panel down at once, for a housing that's gone.
    func remove() {
        deadlineTimer?.invalidate()
        deadlineTimer = nil
        morphs += 1
        shown = nil
        hide()
    }

    /// Keeps the card open while a menu from it is up. AppKit may not report the pointer leaving or coming back while a
    /// menu tracks it, so once the menu closes the panel checks where it is.
    private func menu(open: Bool) {
        isShowingMenu = open
        handle(open ? .menuOpened : .menuClosed)
        // A notch that doesn't answer the pointer has nothing to handle, but the controller still lets go of Escape.
        onChange()
        if !open {
            panel.recheckPointer()
        }
    }

    /// Opens the right-click menu at the pointer, in any state, without opening or closing this notch. Any other notch
    /// that's open closes, as for a click.
    private func showMenu(for event: NSEvent) {
        guard let menu = makeMenu(), let view = panel.contentView else { return }
        onClick()
        self.menu(open: true)
        NSMenu.popUpContextMenu(menu, with: event, for: view)
        self.menu(open: false)
    }

    private func pointer(inside: Bool) {
        guard answersPointer, inside != pointerInside else { return }
        pointerInside = inside
        handle(inside ? .pointerEntered : .pointerLeft)
    }

    /// One timer at most, for `HoverIntent`'s next deadline, and none while nothing is due.
    private func scheduleDeadline() {
        deadlineTimer?.invalidate()
        deadlineTimer = nil
        guard let deadline = hover.deadline else { return }
        let timer = Timer(fire: deadline, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.hover.advance(to: max(.now, deadline))
                self.scheduleDeadline()
                self.update()
                self.onChange()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        deadlineTimer = timer
    }

    func update(animated: Bool = true) {
        let state = state
        let notch = housing
        // The checks show until the notch closes; the next open shows the player again.
        if state != .expanded, model.showsDoctor {
            model.showsDoctor = false
        }
        if state != .expanded {
            releaseKeyboard()
        }
        let card = card
        let isPlaying = isPlaying
        let toast = state == .toast ? toast : nil
        guard let frame = NotchLayout.frame(state, notch: notch, card: card) else {
            guard shown != nil else { return }
            shown = nil
            morphs += 1
            let morph = morphs
            log.notice("Notch hidden over \(NSStringFromRect(notch), privacy: .public)")
            // The wings slide back behind the housing before the panel goes.
            guard animated, panelFrame != nil else {
                hide()
                return
            }
            withAnimation(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? Native.fade : Native.morph, completionCriteria: .removed) {
                model.state = .hidden
                model.isPlaying = isPlaying
            } completion: { [weak self] in
                guard let self, morph == self.morphs else { return }
                self.hide()
            }
            return
        }
        guard shown?.state != state || shown?.frame != frame || model.card != card || model.isPlaying != isPlaying || model.toast != toast else { return }
        let previous = shown
        shown = (state, frame)
        morphs += 1
        let morph = morphs
        if animated, previous == nil {
            // Draw Hidden, the housing's own size, over the housing first, so the wings slide out from behind it. A hide
            // still sliding in keeps its larger panel until the shape has caught up.
            model.notch = notch
            model.state = .hidden
            show(in: panelFrame.map { $0.union(frame) } ?? frame)
            panel.displayIfNeeded()
        }
        model.notch = notch
        if animated, let panelFrame {
            // Grow the panel before the shape does, so nothing is clipped, and shrink it once the shape has. The card and
            // what's playing change in the same animation as the state, so resuming from the idle card, or playback
            // stopping under the full card, morphs from one card to the other and cross-fades their content.
            let union = panelFrame.union(frame)
            if union != panelFrame {
                show(in: union)
            }
            let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            withAnimation(reduceMotion ? Native.fade : Native.morph, completionCriteria: .removed) {
                model.state = state
                model.card = card
                model.isPlaying = isPlaying
                model.toast = toast
            } completion: { [weak self] in
                guard let self, morph == self.morphs, self.panelFrame != frame else { return }
                self.show(in: frame)
            }
        } else {
            model.state = state
            model.card = card
            model.isPlaying = isPlaying
            model.toast = toast
            show(in: frame)
        }
        panel.track(NotchLayout.hoverArea(state, notch: notch, card: card) ?? .zero)
        log.notice("Notch \(state.rawValue, privacy: .public) at \(NSStringFromRect(frame), privacy: .public) over \(NSStringFromRect(notch), privacy: .public)")
    }

    private func hide() {
        releaseKeyboard()
        panel.orderOut(nil)
        panelFrame = nil
        model.state = .hidden
    }

    private func show(in frame: CGRect) {
        panelFrame = frame
        panel.show(in: frame)
    }
}
