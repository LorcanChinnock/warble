import SwiftUI
import WarbleCore

/// The Doctor's checks in the open notch: a heading, then each check with what it found and a button for its fix.
struct DoctorCard: View {
    let model: NotchModel

    var body: some View {
        let doctor = model.doctor
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if model.player.playback != nil {
                    Button { model.onShowDoctor(false) } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Native.secondary)
                            .frame(width: 20, height: 20)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Back to what's playing")
                }
                Text(Doctor.headline(doctor.checks))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                if doctor.needsAttention {
                    Button("Not Now", action: doctor.notNow)
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundStyle(Native.secondary)
                        .help("Hide the \"!\" until Warble opens again")
                }
            }
            ForEach(doctor.checks, id: \.kind) { check in
                CheckRow(check: check, perform: doctor.perform)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 12)
    }
}

/// One check: a mark for how it went and its name, then, unless it passed, what it found and a button for the fix.
private struct CheckRow: View {
    let check: Doctor.Check
    let perform: (Doctor.Fix) -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            mark
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 14)
                .accessibilityHidden(true)
            // A check that passed, or couldn't be checked yet, takes one line; what it found is in its tooltip.
            if check.outcome == .pass || check.outcome == .unknown {
                Text(check.title)
                    .font(.system(size: 11))
                    .foregroundStyle(Native.secondary)
                    .lineLimit(1)
                    .help(check.detail)
                Spacer(minLength: 0)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(check.title)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        if let fix = check.fix, let title = check.fixTitle {
                            Button(title) { perform(fix) }
                                .buttonStyle(FixButtonStyle())
                        }
                    }
                    Text(check.detail)
                        .font(.system(size: 11))
                        .foregroundStyle(Native.secondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: "\(check.title): \(check.detail)"))
    }

    @ViewBuilder private var mark: some View {
        switch check.outcome {
        case .pass: Image(systemName: "checkmark").foregroundStyle(Native.secondary)
        case .fail: Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.white)
        case .warn: Image(systemName: "exclamationmark.circle").foregroundStyle(.white)
        case .unknown: Image(systemName: "questionmark.circle").foregroundStyle(Native.secondary)
        }
    }
}

/// A small white capsule, the only filled control on the card, so the fix is the thing to press.
private struct FixButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.black)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(Capsule().fill(.white.opacity(configuration.isPressed ? 0.7 : 1)))
            .contentShape(Capsule())
    }
}
