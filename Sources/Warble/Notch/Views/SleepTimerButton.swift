import AppKit
import Carbon.HIToolbox
import SwiftUI
import WarbleCore

/// A moon, which opens a menu of sleep timers: 15 minutes, 30 minutes, 1 hour, End of track and, while one runs, Turn
/// off. While a timer runs it shows the time left, drawn from the deadline like the scrubber's position, so nothing
/// counts down in the store. It draws the store's timer and dispatches `.setSleepTimer`, and decides nothing.
struct SleepTimerButton: View {
    let model: NotchModel

    var body: some View {
        let timer = model.sleepTimer
        ZStack {
            SleepTimerMenu(model: model)
            HStack(spacing: 4) {
                Image(systemName: "moon.zzz")
                    .font(.system(size: 12))
                    .foregroundStyle(timer == nil ? AnyShapeStyle(Native.secondary) : AnyShapeStyle(.white))
                if let timer {
                    if timer.choice == .endOfTrack {
                        Text("End")
                            .font(.system(size: 11))
                            .foregroundStyle(.white)
                    } else {
                        TimelineView(.animation(minimumInterval: 1)) { context in
                            Text(verbatim: PlaybackState.positionLabel(timer.deadline.timeIntervalSince(context.date).rounded(.up)))
                                .font(.system(size: 11).monospacedDigit())
                                .foregroundStyle(.white)
                        }
                    }
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .frame(minWidth: 34, minHeight: 24)
        .fixedSize()
        .opacity(timer == nil && !model.canSetSleepTimer ? 0.4 : 1)
    }
}

private struct SleepTimerMenu: NSViewRepresentable {
    let model: NotchModel

    func makeNSView(context: Context) -> SleepTimerMenuView {
        SleepTimerMenuView()
    }

    func updateNSView(_ view: SleepTimerMenuView, context: Context) {
        view.timer = model.sleepTimer
        view.canStart = model.canSetSleepTimer
        view.select = model.onSetSleepTimer
        view.onMenu = model.onMenu
    }

    final class SleepTimerMenuView: NSView {
        var timer: SleepTimer? {
            didSet { setAccessibilityValue(value) }
        }
        var canStart = false
        var select: (SleepTimer.Choice?) -> Void = { _ in }
        var onMenu: (Bool) -> Void = { _ in }

        init() {
            super.init(frame: .zero)
            setAccessibilityElement(true)
            setAccessibilityRole(.popUpButton)
            setAccessibilityLabel(String(localized: "Sleep timer"))
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func mouseDown(with event: NSEvent) {
            showMenu()
        }

        override func accessibilityPerformPress() -> Bool {
            showMenu()
            return true
        }

        // With Keyboard navigation on, Tab reaches it like the buttons around it, and Space or Return opens the menu.
        override var acceptsFirstResponder: Bool { true }
        override var canBecomeKeyView: Bool { NSApp.isFullKeyboardAccessEnabled }
        override var focusRingMaskBounds: NSRect { bounds }
        override func drawFocusRingMask() { NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill() }

        override func keyDown(with event: NSEvent) {
            if [kVK_Space, kVK_Return].contains(Int(event.keyCode)) {
                showMenu()
            } else if event.keyCode == kVK_Tab, let content = window?.contentView?.subviews.first {
                // AppKit's key view loop can't leave this control for the SwiftUI ones, so Tab and ⇧Tab hand focus back.
                window?.makeFirstResponder(content)
            } else {
                super.keyDown(with: event)
            }
        }

        /// What VoiceOver reads after the name: the time left, or that it's off.
        private var value: String {
            guard let timer else { return String(localized: "Off") }
            if timer.choice == .endOfTrack {
                return String(localized: "End of track")
            }
            let minutes = max(Int((timer.deadline.timeIntervalSinceNow / 60).rounded(.up)), 1)
            return String(localized: "\(minutes) min left")
        }

        private func showMenu() {
            let menu = NSMenu()
            menu.autoenablesItems = false
            for choice in SleepTimer.Choice.allCases {
                let item = NSMenuItem(title: Self.title(choice), action: #selector(choose(_:)), keyEquivalent: "")
                item.target = self
                item.tag = SleepTimer.Choice.allCases.firstIndex(of: choice) ?? 0
                item.state = timer?.choice == choice ? .on : .off
                item.isEnabled = canStart
                menu.addItem(item)
            }
            if timer != nil {
                menu.addItem(.separator())
                let off = NSMenuItem(title: String(localized: "Turn off"), action: #selector(turnOff), keyEquivalent: "")
                off.target = self
                menu.addItem(off)
            }
            onMenu(true)
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: bounds.minY - 4), in: self)
            onMenu(false)
        }

        private static func title(_ choice: SleepTimer.Choice) -> String {
            switch choice {
            case .fifteenMinutes: String(localized: "15 minutes")
            case .thirtyMinutes: String(localized: "30 minutes")
            case .oneHour: String(localized: "1 hour")
            case .endOfTrack: String(localized: "End of track")
            }
        }

        @objc private func choose(_ item: NSMenuItem) {
            select(SleepTimer.Choice.allCases[item.tag])
        }

        @objc private func turnOff() {
            select(nil)
        }
    }
}
