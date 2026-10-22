import AppKit
import Carbon.HIToolbox
import SwiftUI
import WarbleCore

/// The playing output's symbol, which opens a menu of the outputs with the playing one ticked. AirPlay receivers aren't
/// listed: they aren't Core Audio devices, and the system's route picker, the only public way to them, moves only
/// Warble's own audio.
struct OutputButton: View {
    let model: NotchModel

    var body: some View {
        let playing = model.player.outputs.first { $0.id == model.player.currentOutput }
        ZStack {
            OutputMenu(model: model)
            Image(systemName: playing?.symbol ?? "hifispeaker")
                .font(.system(size: 12))
                .foregroundStyle(Native.secondary)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

private struct OutputMenu: NSViewRepresentable {
    let model: NotchModel

    func makeNSView(context: Context) -> OutputMenuView {
        OutputMenuView()
    }

    func updateNSView(_ view: OutputMenuView, context: Context) {
        view.outputs = model.player.outputs
        view.current = model.player.currentOutput
        view.select = model.player.selectOutput
        view.onMenu = model.onMenu
    }

    final class OutputMenuView: NSView {
        var outputs: [AudioOutput] = [] {
            didSet { setAccessibilityValue(playing?.name) }
        }
        var current: UInt32? {
            didSet { setAccessibilityValue(playing?.name) }
        }
        var select: (UInt32) -> Void = { _ in }
        var onMenu: (Bool) -> Void = { _ in }

        init() {
            super.init(frame: .zero)
            setAccessibilityElement(true)
            setAccessibilityRole(.popUpButton)
            setAccessibilityLabel(String(localized: "Output"))
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
                // The last control on the card, which AppKit's key view loop can't leave for the SwiftUI controls, so
                // Tab and ⇧Tab hand focus back to them.
                window?.makeFirstResponder(content)
            } else {
                super.keyDown(with: event)
            }
        }

        private var playing: AudioOutput? {
            outputs.first { $0.id == current }
        }

        private func showMenu() {
            let menu = NSMenu()
            for output in outputs {
                let item = NSMenuItem(title: output.name, action: #selector(choose(_:)), keyEquivalent: "")
                item.target = self
                item.tag = Int(output.id)
                item.image = NSImage(systemSymbolName: output.symbol, accessibilityDescription: nil)
                item.state = output.id == current ? .on : .off
                menu.addItem(item)
            }
            onMenu(true)
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: bounds.minY - 4), in: self)
            onMenu(false)
        }

        @objc private func choose(_ item: NSMenuItem) {
            select(UInt32(item.tag))
        }
    }
}
