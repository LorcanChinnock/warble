import SwiftUI

/// The notch's outline: square bottom-up from `bottomRadius` corners, and top corners that flare outward into the top
/// edge, as the screen's own corners do around a real notch. A pill (`roundTop` above 0) isn't joined to the top edge,
/// so its top corners are rounded like the bottom ones and it has no flare.
struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat
    var roundTop: CGFloat = 0

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, CGFloat> {
        get { AnimatablePair(AnimatablePair(topRadius, bottomRadius), roundTop) }
        set { (topRadius, bottomRadius, roundTop) = (newValue.first.first, newValue.first.second, newValue.second) }
    }

    func path(in rect: CGRect) -> Path {
        let top = min(topRadius, rect.width / 2, rect.height / 2)
        let round = min(roundTop, rect.width / 2, rect.height / 2)
        let bottom = min(bottomRadius, (rect.width - 2 * top) / 2, rect.height - top - round)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + round, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - round, y: rect.minY))
        if round > 0 {
            path.addArc(center: CGPoint(x: rect.maxX - round, y: rect.minY + round), radius: round, startAngle: .degrees(-90), endAngle: .zero, clockwise: false)
        }
        path.addQuadCurve(to: CGPoint(x: rect.maxX - top, y: rect.minY + top + round), control: CGPoint(x: rect.maxX - top, y: rect.minY + round))
        path.addLine(to: CGPoint(x: rect.maxX - top, y: rect.maxY - bottom))
        path.addArc(center: CGPoint(x: rect.maxX - top - bottom, y: rect.maxY - bottom), radius: bottom, startAngle: .zero, endAngle: .degrees(90), clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX + top + bottom, y: rect.maxY))
        path.addArc(center: CGPoint(x: rect.minX + top + bottom, y: rect.maxY - bottom), radius: bottom, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX + top, y: rect.minY + top + round))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.minY + round), control: CGPoint(x: rect.minX + top, y: rect.minY + round))
        if round > 0 {
            path.addArc(center: CGPoint(x: rect.minX + round, y: rect.minY + round), radius: round, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        }
        path.closeSubpath()
        return path
    }
}
