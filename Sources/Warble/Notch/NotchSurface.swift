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
    /// Whether anything is playing, rather than Idle.
    var isPlaying = false {
        didSet {
            model.isPlaying = isPlaying
            shownChanged()
        }
    }
    /// Whether a Doctor check failed, which draws the notch with a "!" even when nothing is playing.
    var needsAttention = false {
        didSet { shownChanged() }
    }
    /// What a hover on the housing does while Idle.
    var idleHover = IdleHover.lastPlayed {
        didSet { shownChanged() }
    }
    /// Without anything playing, a "!" or a card to open while Idle, the surface draws nothing.
    private var isShown: Bool { state != .hidden }
    private var wasShown = false
    /// Called after the surface opens or closes, or the pointer crosses it, so the controller can listen for clicks
    /// elsewhere and Escape only while a notch is open.
    var onChange: () -> Void = {}
    /// Called when the surface is clicked, before it opens.
    var onClick: () -> Void = {}

    var state: NotchState {
        NotchState(hover.state, isPlaying: isPlaying, needsAttention: needsAttention, idleHover: idleHover)
    }
    var card: NotchCard { model.card }
    private(set) var pointerInside = false

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
        model.onClick = { [weak self] in
            self?.onClick()
            self?.handle(.click)
        }
        model.onMenu = { [weak self] open in self?.menu(open: open) }
        model.onShowDoctor = { [weak self] show in self?.showDoctor(show) }
    }

    private func shownChanged() {
        defer { wasShown = isShown }
        guard !isShown, wasShown else { return }
        // Start over, so a pointer still on the notch when it's drawn again is reported as entering again.
        hover = HoverIntent()
        pointerInside = false
        scheduleDeadline()
    }

    /// Swaps the open card between the player and the Doctor's checks. From the resting "!", the click that follows
    /// opens the notch on the checks.
    private func showDoctor(_ show: Bool) {
        model.showsDoctor = show
        if state == .expanded {
            update()
        }
    }

    func handle(_ event: HoverEvent) {
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
        handle(open ? .menuOpened : .menuClosed)
        if !open {
            panel.recheckPointer()
        }
    }

    private func pointer(inside: Bool) {
        guard inside != pointerInside else { return }
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
        guard let frame = NotchLayout.frame(state, notch: notch, card: model.card) else {
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
            } completion: { [weak self] in
                guard let self, morph == self.morphs else { return }
                self.hide()
            }
            return
        }
        guard shown?.state != state || shown?.frame != frame else { return }
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
        if animated, let panelFrame, (previous?.frame ?? .zero) != frame {
            // Grow the panel before the shape does, so nothing is clipped, and shrink it once the shape has.
            let union = panelFrame.union(frame)
            if union != panelFrame {
                show(in: union)
            }
            let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            withAnimation(reduceMotion ? Native.fade : Native.morph, completionCriteria: .removed) {
                model.state = state
            } completion: { [weak self] in
                guard let self, morph == self.morphs, self.panelFrame != frame else { return }
                self.show(in: frame)
            }
        } else {
            model.state = state
            show(in: frame)
        }
        panel.track(NotchLayout.hoverArea(state, notch: notch, card: model.card) ?? .zero)
        log.notice("Notch \(state.rawValue, privacy: .public) at \(NSStringFromRect(frame), privacy: .public) over \(NSStringFromRect(notch), privacy: .public)")
    }

    private func hide() {
        panel.orderOut(nil)
        panelFrame = nil
        model.state = .hidden
    }

    private func show(in frame: CGRect) {
        panelFrame = frame
        panel.show(in: frame)
    }
}
