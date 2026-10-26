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
