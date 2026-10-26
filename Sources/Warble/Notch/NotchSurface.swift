import AppKit
import os
import SwiftUI
import WarbleCore

private let log = Logger.warble("notch")

/// One display's notch: its panel over a camera housing, real or virtual. It draws the state `Store` decides for it and
/// sends what the pointer and the user do back as actions. `NotchController` keeps one for each housing.
@MainActor
final class NotchSurface {
    /// The `NotchHousing.display` this notch is for.
    let display: String
    /// The camera housing the panel is drawn over.
    var housing: CGRect
    /// Whether the housing is one Warble draws on a display without a notch.
    var isVirtual: Bool { model.isVirtual }
    /// What the store last decided for this notch, which `render` draws.
    private var last: NotchRender?
    var state: NotchState { last?.state ?? .hidden }
    /// Builds the menu a right-click opens, when it opens.
    var makeMenu: () -> NSMenu? = { nil }

    private let model: NotchModel
    private let panel: NotchPanel
    private let dispatch: (AppAction) -> Void
    /// The state and frame last shown, and the frame the panel has, which stays the larger one until a morph ends.
    private var shown: (state: NotchState, frame: CGRect)?
    private var panelFrame: CGRect?
    /// Bumped by every change, so a morph that ends after another has begun doesn't shrink the panel under it.
    private var morphs = 0

    init(
        display: String, housing: CGRect, player: PlayerModel, settings: SettingsStore,
        dispatch: @escaping (AppAction) -> Void, onScroll: @escaping (NSEvent) -> Void
    ) {
        self.display = display
        self.housing = housing
        self.dispatch = dispatch
        model = NotchModel(player: player)
        panel = NotchPanel(model: model, settings: settings)
        panel.onPointer = { inside in dispatch(.pointer(display: display, inside: inside)) }
        panel.onScroll = onScroll
        panel.onDisplaced = { [weak self] in self?.replace() }
        panel.onMenu = { [weak self] event in self?.showMenu(for: event) }
        model.onClick = { dispatch(.hover(display: display, .click)) }
        model.onMenu = { [weak self] open in self?.menu(open: open) }
    }

    /// Draws what the store decided for this notch: takes the value, then morphs to it, growing the panel before the morph
    /// and shrinking it after. The one call per change, so nothing is set outside the animation or twice.
    func render(_ app: AppState, animated: Bool) {
        if let value = NotchRender(app, display: display) {
            last = value
            model.isVirtual = value.isVirtual
            panel.ignoresMouseEvents = value.ignoresMouseEvents
        }
        if let last {
            draw(last, animated: animated)
        }
    }

    /// Takes the panel down at once, for a housing that's gone.
    func remove() {
        morphs += 1
        shown = nil
        hide()
    }

    /// Keeps the card open while a menu from it is up. AppKit may not report the pointer leaving or coming back while a
    /// menu tracks it, so once the menu closes the panel checks where it is.
    private func menu(open: Bool) {
        dispatch(.menu(display: display, open: open))
        if !open {
            panel.recheckPointer()
        }
    }

    /// Opens the right-click menu at the pointer, in any state, without opening or closing this notch. Any other notch
    /// that's open closes, as for a click.
    private func showMenu(for event: NSEvent) {
        guard let menu = makeMenu(), let view = panel.contentView else { return }
        dispatch(.dismiss(except: display))
        self.menu(open: true)
        NSMenu.popUpContextMenu(menu, with: event, for: view)
        self.menu(open: false)
    }

    /// Times opening the notch, from the input to the first frame of the morph.
    func measureExpand(cause: String, since start: TimeInterval?) {
        Perf.untilNextFrame("Expand", on: panel.screen, cause: cause, since: start)
    }

    private func draw(_ value: NotchRender, animated: Bool) {
        let state = value.state
        let notch = housing
        let card = value.card
        let isPlaying = value.isPlaying
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
        guard shown?.state != state || shown?.frame != frame || model.card != card || model.isPlaying != isPlaying
        else { return }
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
            } completion: { [weak self] in
                guard let self, morph == self.morphs, self.panelFrame != frame else { return }
                self.show(in: frame)
            }
        } else {
            model.state = state
            model.card = card
            model.isPlaying = isPlaying
            show(in: frame)
        }
        panel.track(NotchLayout.hoverArea(state, notch: notch, card: card) ?? .zero)
        log.notice("Notch \(state.rawValue, privacy: .public) at \(NSStringFromRect(frame), privacy: .public) over \(NSStringFromRect(notch), privacy: .public)")
    }

    /// Puts the panel back where the layout has it if something else moved it. `draw` skips a layout whose frame hasn't
    /// changed, so without this a panel the window server moved stays where it was left.
    func replace() {
        guard let panelFrame, panel.frame != NotchLayout.window(for: panelFrame) else { return }
        log.notice("Notch panel moved to \(NSStringFromRect(self.panel.frame), privacy: .public), put back over \(NSStringFromRect(self.housing), privacy: .public)")
        show(in: panelFrame)
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
