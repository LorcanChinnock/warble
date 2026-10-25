# Doctor

Read this before changing the checks, their fixes or the "!" on the notch. Back to the [architecture index](../../CLAUDE.md#architecture).

`Doctor` (WarbleModel) turns facts into checks, each with a fix. The facts are the adapter's state, the macOS version, Automation for each scripted player and which players are open. Its words live in WarbleCore (`Doctor+Mac.swift`), which also asks macOS about Automation without prompting. `AppState.doctor` gathers the facts again only on events: the adapter going missing or giving up, a player opening or quitting, a script refused with -1743, and a notch opening. Each time `reduce` asks for `.gatherFacts` with a refresh number, so facts from an older refresh are dropped, and `PlatformEffects` gathers them. While the adapter works it asks macOS nothing. `DoctorModel` is what the cards draw, plus their fix buttons. While a check fails, every notch rests with a "!", even with nothing playing, and opens on a card (`NotchCard.doctor`, taller than the player's) that lists the checks.

The card's text follows Settings › General › Text size. Its height (`NotchLayout.doctorDrop`) is fixed, and is sized so two failing checks fit at Larger, with a title wrapping to two lines and the fix button never cut short. More failing checks than that can still overflow; the panel doesn't grow with Text size.
