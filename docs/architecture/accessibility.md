# Accessibility

Read this before adding or changing any control or label. Back to the [architecture index](../../CLAUDE.md#architecture).

Every notch control has a VoiceOver name, and what's playing reads "Now playing: <title> by <artist>". Nothing is shown by colour alone: shuffle and repeat draw a dot when on, the mute button's name says what a click does ("Mute" or "Unmute") while its symbol gains a slash, and the heart for Music's Favourites is filled when the song is a favourite and an outline when not, named "Remove from Favourites" or "Add to Favourites". Increase Contrast lightens `Native.secondary` and `Native.track` and swaps the glow for a border. Reduce Motion keeps the glow still, instead of drifting. A `Toggle` or `Picker` in a `Form` whose label has two `Text`s reports no name of its own, so give it `.accessibilityLabel` and the second line as `.accessibilityHint`, then check the name in the Accessibility Inspector.
