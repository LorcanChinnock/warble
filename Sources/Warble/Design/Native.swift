import SwiftUI

/// Warble's look: pure black that merges with the camera housing, the system font, and white marks with grey for
/// anything secondary. No accent colour. The prototype is the "A · Native" artboard of the Warble notch directions canvas.
enum Native {
    /// The panel's fill, the same black as the notch whatever the appearance.
    static let panel = Color.black
    /// Bottom corner radius of the notch at rest. Peek and Expanded round more as they grow.
    static let restingRadius: CGFloat = 12
}
