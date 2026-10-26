# Design

Read this before changing how anything looks, or adding a colour, font or control. Back to the [architecture index](../../CLAUDE.md#architecture).

Warble's look is Native, its own and not Shot's; don't bring over Shot's Brutal tokens or controls. The notch is pure black so it merges with the camera housing, with the system font, white marks and grey for anything secondary, and no accent colour. Its tokens live in `Native` (`Sources/Warble/Design/Native.swift`), beside `NSView(hosting:)`. Fonts are the system's at fixed sizes. Settings is the same black and white, always dark, with its own controls (`SettingsControls.swift`): buttons use the soft white `Native.selection`, groups of rows `Native.group`, and a switch is white when on.
