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
    /// Called with each key the open notch's controls didn't use while it has the keyboard; true when it did something.
    var onKey: (NSEvent) -> Bool = { _ in false }

    /// The app in front when the shortcut opened the notch, which gets the keyboard back when it closes.
    private var keyboardFrom: NSRunningApplication?
    /// Warble's own window that had the keyboard, such as Settings, when the shortcut opened the notch.
    private var keyWindowBefore: NSWindow?

    private let model: NotchModel
    private let panel: NotchPanel
    private let dispatch: (AppAction) -> Void
    /// The state and frame last shown, and the frame the panel has, which stays the larger one until a morph ends.
    private var shown: (state: NotchState, frame: CGRect)?
    private var panelFrame: CGRect?
    /// Bumped by every change, so a morph that ends after another has begun doesn't shrink the panel under it.
    private var morphs = 0

    init(
        display: String, housing: CGRect, player: PlayerModel, doctor: DoctorModel, settings: SettingsStore,
        spectrum: SpectrumFeed,
        dispatch: @escaping (AppAction) -> Void, onScroll: @escaping (NSEvent) -> Void
    ) {
        self.display = display
        self.housing = housing
        self.dispatch = dispatch
        model = NotchModel(player: player, doctor: doctor, spectrum: spectrum)
        panel = NotchPanel(model: model, settings: settings)
        panel.onPointer = { inside in dispatch(.pointer(display: display, inside: inside)) }
        panel.onScroll = onScroll
        panel.onDisplaced = { [weak self] in self?.replace() }
        panel.onMenu = { [weak self] event in self?.showMenu(for: event) }
        model.onClick = { dispatch(.hover(display: display, .click)) }
        model.onMenu = { [weak self] open in self?.menu(open: open) }
        model.onShowDoctor = { show in dispatch(.showDoctor(display: display, show)) }
        model.onShowLyrics = { show in dispatch(.showLyrics(display: display, show)) }
        model.onSetSleepTimer = { choice in dispatch(.setSleepTimer(choice)) }
        model.onActivityButton = { key, button in dispatch(.activityButton(key, button: button)) }
        model.onActivityDismiss = { key in dispatch(.activityDismissed(key)) }
        model.onDragArt = { [weak self] dragging in self?.dragArt(dragging) }
        panel.onKey = { [weak self] event in self?.onKey(event) ?? false }
    }

    /// Draws what the store decided for this notch: takes the value, then morphs to it, growing the panel before the morph
    /// and shrinking it after. The one call per change, so nothing is set outside the animation or twice.
    func render(_ app: AppState, animated: Bool) {
        if let value = NotchRender(app, display: display) {
            last = value
            model.isVirtual = value.isVirtual
            model.showsTitle = value.showsTitle
            model.isAlwaysShown = value.isAlwaysShown
            model.showsDoctor = value.showsDoctor
            model.showsWaveform = value.showsWaveform
            model.hasLyrics = value.hasLyrics
            model.skipsBySeconds = value.skipsBySeconds
            model.artDrag = value.artDrag
            model.showsSleepTimer = value.showsSleepTimer
            model.sleepTimer = value.sleepTimer
            model.canSetSleepTimer = value.canSetSleepTimer
            panel.ignoresMouseEvents = value.ignoresMouseEvents
            // Set only on a change, since this runs on every dispatch, hovers included.
            if panel.sharingType != value.sharingType {
                panel.sharingType = value.sharingType
            }
        }
        if let last {
            draw(last, animated: animated)
        }
    }

    /// Opens the notch with the keyboard in it, so VoiceOver and Keyboard navigation start there, or closes it. It
    /// stays open wherever the pointer goes, until the shortcut again, Esc or a click elsewhere. Warble comes to the
    /// front meanwhile, since VoiceOver and Tab only follow the app in front, and has no menu bar of its own to show.
    /// `handback` is where the keyboard goes when it closes, taken over from another notch that had it.
    func toggleKeyboard(handback: KeyboardHandback? = nil) {
        let opening = state != .expanded
        // The store answers at once, so `state` is already the new one.
        dispatch(.hover(display: display, .keyboard))
        guard opening, state == .expanded else {
            handback?.giveBack()
            return
        }
        if let handback {
            keyboardFrom = handback.app
            keyWindowBefore = handback.window
        } else if NSApp.isActive {
            // Never another notch, which can't take the keyboard once it's closed.
            keyWindowBefore = NSApp.keyWindow.flatMap { $0 is NotchPanel ? nil : $0 }
        } else {
            keyboardFrom = NSWorkspace.shared.frontmostApplication
        }
        panel.takesKeyboard = true
        NSApp.activate()
        panel.makeKey()
        // The SwiftUI view, one level inside the content view, so Tab moves through its buttons.
        panel.makeFirstResponder(panel.contentView?.subviews.first)
    }

    /// Where the keyboard goes when this notch closes, if it has the keyboard, for another notch to take over instead.
    /// This one then closes without handing it back, so the hand-back doesn't race the other notch taking it.
    func takeKeyboardHandback() -> KeyboardHandback? {
        guard panel.takesKeyboard else { return nil }
        panel.takesKeyboard = false
        defer {
            keyboardFrom = nil
            keyWindowBefore = nil
        }
        return KeyboardHandback(app: keyboardFrom, window: keyWindowBefore)
    }

    /// Gives the keyboard back once the notch closes, unless a click has already moved it on: to the app that had it,
    /// or, when Warble was already in front, to its window that had it, or else to whichever app is next.
    private func releaseKeyboard() {
        guard panel.takesKeyboard else { return }
        panel.takesKeyboard = false
        if panel.isKeyWindow {
            KeyboardHandback(app: keyboardFrom, window: keyWindowBefore).giveBack()
        }
        keyboardFrom = nil
        keyWindowBefore = nil
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

    /// Keeps the card open while the art is dragged out of it. The drag ends wherever it drops, and AppKit may not have
    /// reported the pointer leaving meanwhile, so once it ends the panel checks where the pointer is.
    private func dragArt(_ dragging: Bool) {
        if !dragging {
            panel.recheckPointer()
        }
        dispatch(.hover(display: display, .dragging(dragging)))
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
        if state != .expanded {
            releaseKeyboard()
        }
        let card = value.card
        let isPlaying = value.isPlaying
        let toast = value.shownToast
        let lyric = value.shownLyric
        let lyrics = value.shownLyrics
        let activities = value.activities
        guard let frame = NotchLayout.frame(state, notch: notch, card: card, activityRows: activities.count) else {
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
        guard shown?.state != state || shown?.frame != frame || model.card != card || model.isPlaying != isPlaying || model.toast != toast
            || model.lyric != lyric || model.lyrics != lyrics || model.activities != activities
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
                model.toast = toast
                model.lyric = lyric
                model.lyrics = lyrics
                model.activities = activities
            } completion: { [weak self] in
                guard let self, morph == self.morphs, self.panelFrame != frame else { return }
                self.show(in: frame)
            }
        } else {
            model.state = state
            model.card = card
            model.isPlaying = isPlaying
            model.toast = toast
            model.lyric = lyric
            model.lyrics = lyrics
            model.activities = activities
            show(in: frame)
        }
        panel.track(NotchLayout.hoverArea(state, notch: notch, card: card, activityRows: activities.count) ?? .zero)
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

/// Where the keyboard goes when a notch opened from the shortcut closes: the app that had it, or Warble's own window.
@MainActor
struct KeyboardHandback {
    let app: NSRunningApplication?
    let window: NSWindow?

    /// Brings back the app or window, or with neither lets the next app take over, while Warble is still in front.
    func giveBack() {
        guard NSApp.isActive else { return }
        if let app {
            app.activate()
        } else if let window, window.isVisible {
            window.makeKey()
        } else {
            NSApp.deactivate()
        }
    }
}
