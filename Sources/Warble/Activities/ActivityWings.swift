import SwiftUI
import WarbleCore

/// The resting notch with an activity: the sender's icon in the left wing, with the activity's own symbol as a badge on it,
/// and its clock or badge in the right, each centred in a square as tall as the housing. VoiceOver reads the icon as the
/// app and the title, and the clock in the right wing as its own value.
struct ActivityWings: View {
    let activity: Activity
    let notch: CGRect

    var body: some View {
        let wing = NotchLayout.wing(notch: notch)
        let art = wing - 2 * NotchLayout.inset(notch: notch)
        HStack(spacing: 0) {
            ActivityIconView(owner: activity.owner, icon: activity.icon, size: art)
                .frame(width: wing)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(activity.owner.spoken(activity.title))
                .accessibilityAddTraits(.isStaticText)
            Spacer(minLength: 0)
            ActivityValueText(activity: activity)
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 2)
                .frame(width: wing)
        }
        .frame(height: notch.height)
    }
}
