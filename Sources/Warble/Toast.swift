import AppKit
import Carbon.HIToolbox
import SwiftUI
import WarbleCore

/// A short message near the bottom of the screen under the pointer. `AppEnvironment` makes the one Warble shows.
@MainActor
final class Toast {
    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?
    private var duration: Duration?
    private var undoable: PendingAction?
    private var shown: ToastText?
    private var actionTitle: String?
    private let hotkeys: HotkeyCenter
    private let settings: SettingsStore
    fileprivate static let font = ScaledFont.scaled(13, weight: .semibold)

    init(hotkeys: HotkeyCenter, settings: SettingsStore) {
        self.hotkeys = hotkeys
        self.settings = settings
    }

    /// Shows `message` for something that didn't happen or went wrong, long enough to read.
    func error(_ message: LocalizedStringResource) {
        error(String(localized: message))
    }

    /// An error whose text is already localized, such as an error's `localizedDescription`.
    @_disfavoredOverload
    func error<S: StringProtocol>(_ message: S) {
        show(String(message), duration: .seconds(5))
    }

    /// Shows `message`; `duration` nil keeps it visible until the next call. The pointer holds it, and a click dismisses it.
    /// With `undoable`, the toast offers Undo, which ⌘Z also presses from any app while the toast shows, and the action
    /// commits once the toast goes away any other way.
    /// With `cancel`, it offers Cancel for the work it describes. With `reveal`, it offers Show, which selects that file in Finder.
    func show(_ message: LocalizedStringResource, duration: Duration? = .seconds(1.5), undoable: PendingAction? = nil, cancel: (() -> Void)? = nil, reveal: URL? = nil) {
        show(String(localized: message), duration: duration, undoable: undoable, cancel: cancel, reveal: reveal)
    }

    /// A toast whose text is already localized.
    @_disfavoredOverload
    func show<S: StringProtocol>(_ message: S, duration: Duration? = .seconds(1.5), undoable: PendingAction? = nil, cancel: (() -> Void)? = nil, reveal: URL? = nil) {
        let message = String(message)
        settle()
        self.undoable = undoable
        let panel = panel ?? makePanel()
        if let undoable {
            // The panel never becomes key, so ⌘Z can't reach it through the responder chain.
            hotkeys.registerTemporary(KeyCombo(keyCode: UInt32(kVK_ANSI_Z), modifiers: KeyCombo.command)) { [weak self] in
                undoable.undo()
                self?.hide()
            }
        }
        let action: ToastView.Action? = if let undoable {
            ToastView.Action(title: String(localized: "Undo")) { [weak self] in undoable.undo(); self?.hide() }
        } else if let cancel {
            ToastView.Action(title: String(localized: "Cancel"), perform: cancel)
        } else if let reveal {
            ToastView.Action(title: String(localized: "Show")) { [weak self] in NSWorkspace.shared.activateFileViewerSelecting([reveal]); self?.hide() }
        } else {
            nil
        }
        actionTitle = action?.title
        let size = size(of: message, actionTitle: actionTitle)
        let text = ToastText(message: message)
        shown = text
        panel.contentView = NSView(hosting: ToastView(text: text, action: action, hold: { [weak self] in self?.hold($0) }, dismiss: { [weak self] in self?.hide() }), settings: settings)
        let screen = NSScreen.underPointer ?? NSScreen.main ?? NSScreen.screens[0]
        let origin = NSPoint(x: screen.frame.midX - size.width / 2, y: screen.visibleFrame.minY + 80)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.orderFrontRegardless()
        NSAccessibility.post(element: panel, notification: .announcementRequested, userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.high.rawValue])
        self.duration = duration
        scheduleHide()
    }

    /// Shows `message` until the next call, changing the toast's text in place without announcing it, so a percentage
    /// can tick up without VoiceOver reading every step. Does nothing when `message` is already showing.
    func progress(_ message: LocalizedStringResource) {
        progress(String(localized: message))
    }

    /// Progress whose text is already localized.
    @_disfavoredOverload
    func progress<S: StringProtocol>(_ message: S) {
        let message = String(message)
        guard let panel, let shown, undoable == nil else {
            show(message, duration: nil)
            return
        }
        guard shown.message != message else {
            return
        }
        shown.message = message
        duration = nil
        hideTask?.cancel()
        let size = size(of: message, actionTitle: actionTitle)
        panel.setFrame(NSRect(x: panel.frame.midX - size.width / 2, y: panel.frame.minY, width: size.width, height: size.height), display: true)
        if !panel.isVisible {
            panel.orderFrontRegardless()
        }
    }

    private func size(of message: String, actionTitle: String?) -> NSSize {
        let textSize = Preferences().textSize
        var textWidth = (message as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: Self.font.points(textSize), weight: .semibold)]).width.rounded(.up)
        if let actionTitle {
            textWidth += (actionTitle as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: textSize.points(12), weight: .bold)]).width.rounded(.up) + 36
        }
        return NSSize(width: textWidth + 32, height: 38)
    }

    private func hold(_ holding: Bool) {
        if holding {
            hideTask?.cancel()
        } else {
            scheduleHide()
        }
    }

    private func scheduleHide() {
        hideTask?.cancel()
        guard let duration, panel != nil else {
            return
        }
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            if !Task.isCancelled {
                self?.hide()
            }
        }
    }

    private func hide() {
        panel?.orderOut(nil)
        settle()
    }

    private func settle() {
        let pending = undoable
        undoable = nil
        if pending != nil {
            hotkeys.unregisterTemporary()
        }
        pending?.commit()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.panel = panel
        return panel
    }
}

@MainActor
@Observable
private final class ToastText {
    var message: String

    init(message: String) {
        self.message = message
    }
}

private struct ToastView: View {
    struct Action {
        let title: String
        let perform: () -> Void
    }

    let text: ToastText
    let action: Action?
    let hold: (Bool) -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(text.message)
                .font(Toast.font)
                .foregroundStyle(.primary)
                .lineLimit(1)
            if let action {
                Button(action.title, action: action.perform)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial, in: Capsule())
        .contentShape(Capsule())
        .onHover(perform: hold)
        .onTapGesture(perform: dismiss)
    }
}
