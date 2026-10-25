import SwiftUI

/// The controls Settings is built from, in the notch's look: white on black, grey for anything secondary and no accent
/// colour. What's on is marked by position and fill, never by colour alone.

/// A rounded panel of rows, told apart by hairlines, with an optional note below it.
struct SettingsGroup<Content: View>: View {
    var title: Text?
    var footer: Text?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                title
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Native.secondary)
                    .padding(.horizontal, 14)
                    .accessibilityAddTraits(.isHeader)
            }
            VStack(spacing: 0) {
                Group(subviews: content) { rows in
                    ForEach(rows.indices, id: \.self) { index in
                        if index > 0 {
                            Rectangle().fill(Native.track).frame(height: 1)
                        }
                        rows[index]
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Native.group, in: RoundedRectangle(cornerRadius: Native.groupRadius, style: .continuous))
            if let footer {
                footer
                    .font(.footnote)
                    .foregroundStyle(Native.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
            }
        }
    }
}

/// A group whose rows stay folded away until its title is clicked, closed each time the window opens.
struct SettingsDisclosure<Content: View>: View {
    let title: Text
    @ViewBuilder let content: Content
    @State private var isOpen = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(reduceMotion ? Native.fade : Native.morph) { isOpen.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                        .accessibilityHidden(true)
                    title.font(.footnote.weight(.semibold))
                }
                .foregroundStyle(Native.secondary)
                .padding(.horizontal, 14)
                .frame(minHeight: 28, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.notch)
            .accessibilityValue(isOpen ? Text("Shown") : Text("Hidden"))
            if isOpen {
                SettingsGroup { content }
            }
        }
    }
}

/// A row in a group: a title with an optional second line, and a control on the right. A row whose control speaks for it
/// (`speaksForControl`) hides its text from VoiceOver, because the control carries the title as its label and the second
/// line as its hint.
struct SettingsRow<Trailing: View>: View {
    let title: Text
    var detail: Text?
    var speaksForControl = false
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                title
                    .foregroundStyle(.white)
                if let detail {
                    detail
                        .font(.callout)
                        .foregroundStyle(Native.secondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityHidden(speaksForControl)
            Spacer(minLength: 0)
            trailing
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    }
}

/// A row with a switch.
struct SettingsToggleRow: View {
    let title: Text
    var detail: Text?
    @Binding var isOn: Bool

    var body: some View {
        SettingsRow(title: title, detail: detail, speaksForControl: true) {
            WarbleToggle(isOn: $isOn, label: title, hint: detail)
        }
    }
}

/// A row that picks one of a few values from a menu, showing the current one in grey with a chevron.
struct SettingsMenuRow<Value: Hashable>: View {
    let title: Text
    var detail: Text?
    @Binding var selection: Value
    let options: [WarbleOption<Value>]

    var body: some View {
        SettingsRow(title: title, detail: detail, speaksForControl: true) {
            WarbleMenuPicker(selection: $selection, options: options, label: title, hint: detail)
        }
    }
}

/// A value to choose, and its name.
struct WarbleOption<Value: Hashable> {
    let value: Value
    let title: Text
}

/// A switch that is white when on and grey when off, with the knob on the right when on.
struct WarbleToggle: View {
    @Binding var isOn: Bool
    let label: Text
    var hint: Text?
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule().fill(isOn ? AnyShapeStyle(.white) : AnyShapeStyle(Native.track))
                Circle()
                    .fill(isOn ? Color.black : Color.white)
                    .padding(3)
            }
            .frame(width: 40, height: 24)
            .animation(reduceMotion ? Native.fade : Native.morph, value: isOn)
        }
        .buttonStyle(.notch)
        .opacity(isEnabled ? 1 : 0.4)
        .accessibilityRepresentation {
            Toggle(isOn: $isOn) { label }
                .accessibilityHint(hint ?? Text(verbatim: ""))
        }
    }
}

/// A few short choices side by side, the chosen one a white pill with black text.
struct WarbleSegmented<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [WarbleOption<Value>]
    let label: Text
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                let chosen = option.value == selection
                Button {
                    selection = option.value
                } label: {
                    option.title
                        .font(.callout.weight(chosen ? .semibold : .regular))
                        .foregroundStyle(chosen ? AnyShapeStyle(.black) : AnyShapeStyle(Native.secondary))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .frame(maxWidth: .infinity)
                        .background {
                            if chosen {
                                Capsule().fill(.white).matchedGeometryEffect(id: "pill", in: pill)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.notch)
                .accessibilityAddTraits(chosen ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Native.track, in: Capsule())
        .animation(reduceMotion ? Native.fade : Native.morph, value: selection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }
}

/// The menu behind `SettingsMenuRow`: the current value in grey, with a chevron.
struct WarbleMenuPicker<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [WarbleOption<Value>]
    let label: Text
    var hint: Text?

    private var current: Text? { options.first { $0.value == selection }?.title }

    var body: some View {
        Menu {
            Picker(selection: $selection) {
                ForEach(options.indices, id: \.self) { index in
                    options[index].title.tag(options[index].value)
                }
            } label: {
                label
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: 6) {
                current
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(Native.secondary)
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(label)
        .accessibilityHint(hint ?? Text(verbatim: ""))
    }
}

/// A small pill button, for an action in a row. Space or Return press it while it has the focus ring, as on the notch.
struct WarbleButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button(action: configuration.trigger) { configuration.label }
            .buttonStyle(Pill())
            .pressedByKeyboard(configuration.trigger)
    }

    private struct Pill: ButtonStyle {
        @Environment(\.isEnabled) private var isEnabled

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .font(.callout)
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Native.selection, in: Capsule())
                .opacity(isEnabled ? (configuration.isPressed ? 0.6 : 1) : 0.4)
                .contentShape(Capsule())
        }
    }
}

extension PrimitiveButtonStyle where Self == WarbleButtonStyle {
    static var warble: WarbleButtonStyle { WarbleButtonStyle() }
}
