import SwiftUI

/// The controls Settings is built from, in the website's look (`Warm`): cards on a cream page, a serif heading, and
/// yellow for anything that is on or chosen. What's on is also marked by position, weight and an edge
/// (`Warm.accentEdge`), never by colour alone.

/// A rounded card of rows, told apart by hairlines. A `title` opens the card with a serif heading on an icon tile in
/// one of the website's three accents (`tint`), as its cards are, so every card reads the same way.
struct SettingsGroup<Content: View>: View {
    var title: Text?
    /// The SF Symbol on the heading's tile.
    var symbol: String?
    /// The tile's colour: `Warm.yellow`, `Warm.pink` or `Warm.sky`.
    var tint: Color = Warm.yellow
    var footer: Text?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(spacing: 0) {
                if let title {
                    HStack(spacing: 12) {
                        if let symbol {
                            Image(systemName: symbol)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(Warm.onAccent)
                                .frame(width: 40, height: 40)
                                .background(tint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .accessibilityHidden(true)
                        }
                        title
                            .font(.system(size: 22, weight: .bold, design: .serif))
                            .foregroundStyle(Warm.ink)
                            .accessibilityAddTraits(.isHeader)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 6)
                }
                Group(subviews: content) { rows in
                    ForEach(rows.indices, id: \.self) { index in
                        if index > 0 {
                            Rectangle().fill(Warm.hairline).frame(height: 1).padding(.horizontal, 20)
                        }
                        rows[index]
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Warm.surface, in: RoundedRectangle(cornerRadius: Warm.cardRadius, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: Warm.cardRadius, style: .continuous).strokeBorder(Warm.hairline, lineWidth: 1) }
            if let footer {
                footer
                    .font(.footnote)
                    .foregroundStyle(Warm.secondary)
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
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Warm.ink)
                if let detail {
                    detail
                        .font(.callout)
                        .foregroundStyle(Warm.secondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityHidden(speaksForControl)
            Spacer(minLength: 0)
            trailing
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
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

/// A row with a choice of a few options, one line below its title and note: the chosen one is a yellow button that
/// stands off the track, in bold, and none is marked by colour alone. A press sinks the chosen one and darkens another,
/// so every option answers the pointer. VoiceOver reads it as one picker with the title as its label and the note as
/// its hint.
struct SettingsChoiceRow<Value: Hashable>: View {
    let title: Text
    var detail: Text?
    @Binding var selection: Value
    let options: [(value: Value, label: Text)]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                title
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Warm.ink)
                if let detail {
                    detail
                        .font(.callout)
                        .foregroundStyle(Warm.secondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityHidden(true)
            HStack(spacing: 4) {
                ForEach(options.indices, id: \.self) { index in
                    let option = options[index]
                    Button {
                        selection = option.value
                    } label: {
                        option.label
                    }
                    .buttonStyle(ChoiceOptionStyle(isChosen: selection == option.value))
                }
            }
            .padding(.horizontal, 4)
            .padding(.top, 4)
            .padding(.bottom, 4 + Warm.lipDepth - 1)
            .background(Warm.track, in: Capsule())
            .accessibilityRepresentation {
                Picker(selection: $selection) {
                    ForEach(options.indices, id: \.self) { index in
                        options[index].label.tag(options[index].value)
                    }
                } label: { title }
                    .pickerStyle(.segmented)
                    .accessibilityHint(detail ?? Text(verbatim: ""))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One option in a `SettingsChoiceRow`. The chosen one is a yellow pill on a lip that sinks while pressed; another
/// darkens while pressed. Space or Return press it while it has the focus ring, as on the notch.
private struct ChoiceOptionStyle: PrimitiveButtonStyle {
    let isChosen: Bool

    func makeBody(configuration: Configuration) -> some View {
        Button(action: configuration.trigger) { configuration.label }
            .buttonStyle(Option(isChosen: isChosen))
            .pressedByKeyboard(configuration.trigger)
    }

    private struct Option: ButtonStyle {
        let isChosen: Bool

        func makeBody(configuration: Configuration) -> some View {
            let lip = Warm.lipDepth - 1
            let drop = configuration.isPressed && isChosen ? lip : 0
            configuration.label
                .font(.callout.weight(isChosen ? .bold : .medium))
                .foregroundStyle(isChosen ? AnyShapeStyle(Warm.onAccent) : AnyShapeStyle(Warm.secondary))
                .frame(maxWidth: .infinity, minHeight: 32)
                .offset(y: drop)
                .background {
                    if isChosen {
                        ZStack {
                            Capsule().fill(Warm.yellowDeep).offset(y: lip)
                            Capsule().fill(Warm.yellow)
                                .overlay { Capsule().strokeBorder(Warm.accentEdge, lineWidth: 1) }
                                .offset(y: drop)
                        }
                    } else if configuration.isPressed {
                        Capsule().fill(Warm.off)
                    }
                }
                .contentShape(Capsule())
        }
    }
}

/// A switch that is yellow when on and grey when off, with the knob on the right when on.
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
                if isOn {
                    Capsule().fill(Warm.yellowDeep).offset(y: 2)
                    Capsule().fill(Warm.yellow)
                        .overlay { Capsule().strokeBorder(Warm.accentEdge, lineWidth: 1) }
                } else {
                    Capsule().fill(Warm.off)
                        .overlay { Capsule().strokeBorder(Warm.hairline, lineWidth: 1) }
                }
                Circle()
                    .fill(isOn ? AnyShapeStyle(Warm.onAccent) : AnyShapeStyle(Warm.ink))
                    .padding(3)
            }
            .frame(width: 46, height: 28)
            .padding(.bottom, 2)
            .animation(reduceMotion ? Native.fade : .snappy(duration: 0.25), value: isOn)
        }
        .buttonStyle(.notch)
        .opacity(isEnabled ? 1 : 0.4)
        .accessibilityRepresentation {
            Toggle(isOn: $isOn) { label }
                .accessibilityHint(hint ?? Text(verbatim: ""))
        }
    }
}

/// The website's chunky pill button, for an action in Settings: yellow, or quiet (the card's colour) for the less
/// important one. It stands off the surface on a lip that it sinks into when pressed. Space or Return press it while it
/// has the focus ring, as on the notch.
struct WarbleButtonStyle: PrimitiveButtonStyle {
    var isQuiet = false

    func makeBody(configuration: Configuration) -> some View {
        Button(action: configuration.trigger) { configuration.label }
            .buttonStyle(Pill(isQuiet: isQuiet))
            .pressedByKeyboard(configuration.trigger)
    }

    private struct Pill: ButtonStyle {
        let isQuiet: Bool
        @Environment(\.isEnabled) private var isEnabled

        func makeBody(configuration: Configuration) -> some View {
            let drop = configuration.isPressed ? Warm.lipDepth : 0
            configuration.label
                .font(.callout.weight(.semibold))
                .foregroundStyle(isQuiet ? AnyShapeStyle(Warm.ink) : AnyShapeStyle(Warm.onAccent))
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .offset(y: drop)
                .background {
                    ZStack {
                        Capsule().fill(isQuiet ? AnyShapeStyle(Warm.lip) : AnyShapeStyle(Warm.yellowDeep))
                            .offset(y: Warm.lipDepth)
                        Capsule().fill(isQuiet ? AnyShapeStyle(Warm.surface) : AnyShapeStyle(Warm.yellow))
                            .overlay { Capsule().strokeBorder(isQuiet ? AnyShapeStyle(Warm.hairline) : AnyShapeStyle(Warm.accentEdge), lineWidth: 1) }
                            .offset(y: drop)
                    }
                }
                .padding(.bottom, Warm.lipDepth)
                .opacity(isEnabled ? 1 : 0.4)
                .contentShape(Capsule())
        }
    }
}

extension PrimitiveButtonStyle where Self == WarbleButtonStyle {
    static var warble: WarbleButtonStyle { WarbleButtonStyle() }
    static var warbleQuiet: WarbleButtonStyle { WarbleButtonStyle(isQuiet: true) }
}
