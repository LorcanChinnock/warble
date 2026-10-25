import SwiftUI
import WarbleCore

/// A row for each activity, ranked: the sender's icon, the app's name over the title and detail, the clock, the sender's
/// buttons and a close button. The player's card and the lyrics card draw them below their controls, and the activity card
/// is nothing else. The text follows Settings › General › Text size, and the rows keep their height.
struct ActivityRows: View {
    let model: NotchModel

    var body: some View {
        VStack(spacing: 0) {
            ForEach(model.activities) { activity in
                ActivityRow(activity: activity, model: model)
            }
        }
        .padding(.horizontal, 16)
    }
}

/// The card while nothing plays: the rows, centred in the idle card's height.
struct ActivityCard: View {
    let model: NotchModel

    var body: some View {
        ActivityRows(model: model)
            .frame(maxHeight: .infinity)
            .padding(.bottom, 10)
    }
}

private struct ActivityRow: View {
    let activity: Activity
    let model: NotchModel

    var body: some View {
        HStack(spacing: 10) {
            ActivityIconView(owner: activity.owner, icon: activity.icon, size: 36)
            VStack(alignment: .leading, spacing: 1) {
                activity.owner.displayName
                    .font(.scaled(11))
                    .foregroundStyle(Native.secondary)
                Text(verbatim: activity.title)
                    .font(.scaled(14, weight: .semibold))
                    .foregroundStyle(.white)
                if let detail = activity.detail {
                    Text(verbatim: detail)
                        .font(.scaled(12))
                        .foregroundStyle(Native.secondary)
                }
            }
            .lineLimit(1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(activity.owner.spoken(activity.title))
            .accessibilityValue(Text(verbatim: activity.detail ?? ""))
            Spacer(minLength: 0)
            ActivityValueText(activity: activity)
                .font(.scaled(13, weight: .medium, monospacedDigits: true))
                .foregroundStyle(.white)
                .lineLimit(1)
            ForEach(activity.buttons, id: \.id) { button in
                ActivityButtonView(button: button) { model.onActivityButton(activity.key, button.id) }
            }
            Button { model.onActivityDismiss(activity.key) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Native.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.notch)
            .accessibilityLabel("Close")
            .help("Close")
        }
        .frame(height: NotchLayout.activityRowDrop - 4)
        .padding(.bottom, 4)
    }
}

private struct ActivityButtonView: View {
    let button: ActivityButton
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let symbol = button.symbol, ActivityIconView.draws(symbol) {
                    Image(systemName: symbol)
                        .font(.system(size: 10, weight: .semibold))
                }
                Text(verbatim: button.label)
                    .font(.scaled(12, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(Capsule().fill(Native.selection))
            .contentShape(Capsule())
        }
        .buttonStyle(.notch)
        .fixedSize()
        .accessibilityLabel(Text(verbatim: button.label))
    }
}
