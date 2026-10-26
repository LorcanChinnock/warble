import AppKit
import SwiftUI
import WarbleCore

/// A chip for each app playing while more than one is, with the followed app's filled. It draws `AppState.chips` and
/// dispatches a click as a choice of app, and decides nothing else.
struct SourceChips: View {
    let chips: [SourceChip]
    let follow: (SourceChip) -> Void

    var body: some View {
        if !chips.isEmpty {
            HStack(spacing: 6) {
                ForEach(chips, id: \SourceChip.bundleIdentifier) { chip in
                    let name = Self.name(of: chip.bundleIdentifier)
                    Button { follow(chip) } label: {
                        Text(name)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(chip.isFollowed ? AnyShapeStyle(.white) : AnyShapeStyle(Native.secondary))
                            .lineLimit(1)
                            .padding(.horizontal, 8)
                            .frame(height: 20)
                            .background(chip.isFollowed ? AnyShapeStyle(Native.selection) : AnyShapeStyle(Native.group), in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.notch)
                    .accessibilityLabel(name)
                    .accessibilityAddTraits(chip.isFollowed ? AccessibilityTraits.isSelected : AccessibilityTraits())
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 4)
        }
    }

    private static func name(of bundleIdentifier: String) -> String {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first?.localizedName ?? bundleIdentifier
    }
}
