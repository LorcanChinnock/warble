import SwiftUI
import WarbleCore


/// A capsule track with a round knob. Once focused, the arrow keys step it by 1% of its range, ⇧ by 10%.
/// `onEditingChanged` reports a drag, or an arrow key held down, starting and ending, so a caller can make each one
/// undo step.
struct BrutalSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    let track: LinearGradient
    var checkerboard = false
    var width: CGFloat = 200
    var onEditingChanged: (Bool) -> Void = { _ in }
    @State private var isDragging = false
    /// Whether an arrow key is down, so its repeats join one edit.
    @State private var isStepping = false
    /// The value the arrow key held down set last. Its repeats reach the handler its press began with, whose `value` may
    /// be a copy from before the press, so each repeat steps from this instead.
    @State private var steppedValue: Double?
    @FocusState private var isFocused: Bool

    private var fraction: Double { (min(max(value, range.lowerBound), range.upperBound) - range.lowerBound) / (range.upperBound - range.lowerBound) }

    var body: some View {
        ZStack(alignment: .leading) {
            if checkerboard {
                Canvas { ctx, size in
                    let cell: CGFloat = 6
                    for x in 0...Int(size.width / cell) {
                        for y in 0...Int(size.height / cell) where (x + y) % 2 == 0 {
                            ctx.fill(Path(CGRect(x: CGFloat(x) * cell, y: CGFloat(y) * cell, width: cell, height: cell)), with: .color(.gray.opacity(0.4)))
                        }
                    }
                }
                .background(Color.white)
                .clipShape(Capsule().inset(by: 1))
            }
            Capsule().fill(track)
                .inkBorder(Capsule(), width: 2)
            Circle().fill(isFocused ? Brutal.yellow : Brutal.paper)
                .inkBorder(Circle(), width: 2)
                .frame(width: 16, height: 16)
                .offset(x: fraction * (width - 16))
        }
        .frame(width: width, height: 16)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { drag in
                if !isDragging {
                    isDragging = true
                    onEditingChanged(true)
                }
                let dragged = min(max((drag.location.x - 8) / (width - 16), 0), 1)
                value = range.lowerBound + dragged * (range.upperBound - range.lowerBound)
            }
            .onEnded { _ in
                isDragging = false
                onEditingChanged(false)
            })
        .focusable(interactions: .activate)
        .focused($isFocused)
        .focusEffectDisabled()
        .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow], phases: .all) { press in
            guard press.phase != .up else {
                endStepping()
                return .handled
            }
            if !isStepping {
                isStepping = true
                onEditingChanged(true)
            }
            let up = press.key == .rightArrow || press.key == .upArrow
            let from = press.phase == .repeat ? steppedValue ?? value : value
            let stepped = SliderStep.value(from, up: up, fraction: press.modifiers.contains(.shift) ? 0.1 : 0.01, in: range)
            steppedValue = stepped
            value = stepped
            return .handled
        }
        .onChange(of: isFocused) {
            if !isFocused {
                endStepping()
            }
        }
        // A real slider to assistive tech, stepping by 10% of the range. A caller's label after this applies to it.
        .accessibilityRepresentation {
            Slider(value: $value, in: range, step: (range.upperBound - range.lowerBound) / 10)
                .accessibilityValue(Text("\(Int((fraction * 100).rounded())) percent"))
        }
    }

    /// Ends the edit a held arrow key started. A key let go after focus moved away never reports its release.
    private func endStepping() {
        guard isStepping else {
            return
        }
        isStepping = false
        steppedValue = nil
        onEditingChanged(false)
    }
}
